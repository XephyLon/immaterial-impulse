import QtQuick
import qs.modules.common
import "../../designsystem/widgets" as Expressive
import qs.modules.common.functions as Functions
import qs.services
import "../../designsystem/widgets/shapes/path-length.js" as PathLength
import "media_shapes.js" as MediaShapes

// THE seek bar - one element at every span, as the review required.
//
// It is a wavy stroke along a BASELINE, and only the baseline changes: a
// straight line at 3x2, a perfect circle inside the play button at 2x2, and
// the button's own cookie outline at 2x1. `bend` carries line-to-ring,
// `ringT` carries circle-to-cookie, both on Behaviors, so every span change
// is the same stroke curling or unrolling - it never fades, never blinks,
// and the wave (present while playing, still while paused) rides whatever
// the baseline currently is with the same wiggly movement everywhere.
Item {
    id: root

    property string span: "3x2"
    property real progress: 0
    property bool playing: false

    // 0 = straight bar .. 1 = ring
    property real bend: root.span === "3x2" ? 0 : 1
    Behavior on bend { Expressive.SpanTravel {} }
    // 0 = circle .. 1 = cookie outline
    property real ringT: root.span === "2x1" ? 1 : 0
    // What the stroke sits ON decides its palette, not what shape it is: the
    // bar (3x2) and the floating 2x1 border both sit on the CARD and read in
    // primary; only the 2x2 circle sits on the button's light body and reads
    // in on-primary. Keyed on bend, the 2x1 ring came out dark-on-dark the
    // moment the margin moved it off the body.
    property real onBody: root.span === "2x2" ? 1 : 0
    Behavior on onBody { Expressive.SpanFade {} }
    Behavior on ringT { Expressive.SpanTravel {} }

    property real phase: 0
    // The travelling wave, alive only while something plays and the item is
    // on screen - a FrameAnimation with no gate is the idle-repaint bug. At
    // 2x2 the ring is a STILL perfect circle (the review's call): no wave,
    // no travel, so no frame ticks either.
    readonly property bool waves: root.playing && root.span !== "2x2"
    // The wave's amplitude is a LEVEL, not a switch: pause snapped it to zero
    // in one frame and the spring visibly chopped flat (the review). It eases
    // out and back in, and the frame clock runs until the fade completes so
    // the flattening itself is drawn.
    property real waveLevel: root.waves ? 1 : 0
    Behavior on waveLevel { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveEffects } }
    FrameAnimation {
        running: root.visible && root.opacity > 0 && root.waveLevel > 0.001
        onTriggered: { root.phase += frameTime * 2.5; canvas.requestPaint(); }
    }

    // Position arrives from MPRIS about once a second, so raw progress moves
    // in steps. The drawn progress glides between those steps - linear, a
    // touch under the update cadence, so it neither stutters nor lags a seek
    // by more than a beat.
    property real shownProgress: root.progress
    Behavior on shownProgress { NumberAnimation { duration: 700 } }

    readonly property real lineWidthPx:
        (4 + (Appearance.borderWidth.heavy - 4) * root.bend) * Appearance.effectiveScale

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    // The raw baseline, shared by the painter, the hit test and the probe -
    // one sampler, so what is drawn IS what is clickable.
    function baselinePoints(sampleCount) {
        const N = sampleCount || 160;
        const stroke = root.lineWidthPx;
        const pad = stroke;
        const cx = width / 2, cy = height / 2;
        const dia = Math.min(width, height) - stroke;
        // Cached against ringT: rebuilding the Morph and re-measuring 24
        // cubics here ran on every frame of the wave clock and on every mouse
        // move through strokeDistance(), for a shape that changes twice.
        const ring = MediaShapes.ringMeasuredAt(root.ringT, PathLength.measureCubics);
        const cubics = ring.cubics;
        const measure = ring.measure;
        const out = [];
        for (let i = 0; i <= N; i++) {
            const u = i / N;
            const line = { x: pad + u * (width - 2 * pad), y: cy };
            // At 3x2 the baseline IS the line: bend is 0, so every ring point
            // below was computed and then multiplied away. Measured, that was
            // 42% of the seeker's per-frame cost at that span.
            if (root.bend <= 0.0001) { out.push(line); continue; }
            const target = u * measure.total;
            let index = 0;
            while (index < cubics.length - 1 && measure.lengths[index + 1] < target) index++;
            const span = measure.lengths[index + 1] - measure.lengths[index];
            const t = span > 0 ? (target - measure.lengths[index]) / span : 0;
            const point = PathLength.pointOnCubic(cubics[index], t);
            const ring = { x: cx + point.x * dia, y: cy + point.y * dia };
            out.push({ x: line.x + (ring.x - line.x) * root.bend,
                       y: line.y + (ring.y - line.y) * root.bend });
        }
        return out;
    }

    // Distance from a point to the stroked baseline - the seeker's true hit
    // area. Anything further than this passes through to whatever is under
    // it, which at 2x2 and 2x1 is the play button this ring sits on.
    function strokeDistance(x, y) {
        const pts = root.baselinePoints(96);
        let best = Infinity;
        for (const p of pts) {
            const d = Math.hypot(p.x - x, p.y - y);
            if (d < best) best = d;
        }
        return best;
    }

    signal sought(real fraction)

    Canvas {
        id: canvas
        anchors.fill: parent

        readonly property real bendNow: root.bend
        readonly property real waveLevelNow: root.waveLevel
        onWaveLevelNowChanged: requestPaint()
        readonly property real ringNow: root.ringT
        readonly property real progressNow: Math.max(0, Math.min(1, root.shownProgress))
        readonly property color arcColor: root.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, root.onBody)
        readonly property color trackColor: root.mix(
            Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25),
            Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.3), root.onBody)
        readonly property bool playingNow: root.playing
        readonly property string spanNow: root.span
        onSpanNowChanged: requestPaint()

        onBendNowChanged: requestPaint()
        onRingNowChanged: requestPaint()
        onProgressNowChanged: requestPaint()
        onArcColorChanged: requestPaint()
        onTrackColorChanged: requestPaint()
        onPlayingNowChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const N = 160;
            const stroke = root.lineWidthPx;
            const pad = stroke;
            const cx = width / 2, cy = height / 2;
            const dia = Math.min(width, height) - stroke;

            // Wavelength: 6 cycles across the bar; an INTEGER count around the
            // closed ring or the wave beats against its own seam (the spec's
            // arc-length note). 12 matches the cookie's lobes.
            const freq = Math.round(6 + (12 - 6) * canvas.bendNow);
            const amp = stroke * 0.6 * root.waveLevel;

            const base = root.baselinePoints(N);
            // Normals from the RAW baseline, displaced into a second array.
            // Displacing in place fed each point's normal from an already-
            // displaced neighbour - a feedback loop that turned the sine into
            // a knotted scribble, and it shipped because the visual check was
            // graded at thumbnail size.
            const points = [];
            for (let i = 0; i <= N; i++) {
                const before = base[Math.max(0, i - 1)];
                const after = base[Math.min(N, i + 1)];
                let nx = -(after.y - before.y), ny = after.x - before.x;
                const len = Math.hypot(nx, ny) || 1;
                nx /= len; ny /= len;
                const w = amp * Math.sin(freq * 2 * Math.PI * (i / N) + root.phase);
                points.push({ x: base[i].x + nx * w, y: base[i].y + ny * w });
            }

            function strokeRun(from, to, colour) {
                if (to <= from) return;
                ctx.beginPath();
                ctx.moveTo(points[from].x, points[from].y);
                for (let i = from + 1; i <= to; i++) ctx.lineTo(points[i].x, points[i].y);
                ctx.strokeStyle = colour;
                ctx.lineWidth = stroke;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.stroke();
            }

            const split = Math.round(canvas.progressNow * N);
            strokeRun(split, N, canvas.trackColor);
            strokeRun(0, split, canvas.arcColor);

            // the bar's handle dot, dissolving as the bar curls up
            if (canvas.bendNow < 1) {
                const at = points[split] ?? points[N];
                ctx.beginPath();
                ctx.globalAlpha = 1 - canvas.bendNow;
                ctx.arc(at.x, at.y, 7 * Appearance.effectiveScale, 0, Math.PI * 2);
                ctx.fillStyle = Appearance.colors.colPrimary;
                ctx.fill();
                ctx.globalAlpha = 1;
            }
        }
    }

    // The play button under this ring (2x2 and 2x1). The ring holds hover
    // on top - paint order demands it stay above - so it answers for the
    // button too: pointer cursor over the button's face, and hover reported
    // back through hoveringPlay.
    property var playItem: null
    // Exposed for the probe's failure diagnostics: when a button reports
    // itself hovered with the pointer elsewhere, the next question is always
    // whether this area is the one holding it.
    readonly property bool seekAreaContainsMouse: seekArea.containsMouse
    readonly property bool hoveringPlay: seekArea.containsMouse && root.playItem
        && root.playItem.visible && (function () {
            const point = seekArea.mapToItem(root.playItem, seekArea.mouseX, seekArea.mouseY);
            return point.x >= 0 && point.y >= 0
                && point.x < root.playItem.width && point.y < root.playItem.height;
        })()

    MouseArea {
        id: seekArea
        anchors.fill: parent
        hoverEnabled: true
        // Points near the stroke (a press there seeks) and over the covered
        // play button (a press there is handed down to it).
        cursorShape: containsMouse
            && (root.strokeDistance(mouseX, mouseY) <= root.lineWidthPx * 2.5
                || root.hoveringPlay)
            ? Qt.PointingHandCursor : Qt.ArrowCursor
        // A ring's hit area is its STROKE, not its disc. The first version
        // said so in this comment and then filled the rect anyway - at 2x2
        // and 2x1 the ring sits on the play button, so every click on the
        // button died here and play/pause stopped working at those spans.
        // A press further than a few stroke-widths from the baseline is
        // rejected, which hands it to whatever is underneath.
        onPressed: mouse => {
            if (root.strokeDistance(mouse.x, mouse.y) > root.lineWidthPx * 2.5) {
                mouse.accepted = false;
                return;
            }
            root.seekTo(mouse);
        }
        onPositionChanged: mouse => { if (pressed) root.seekTo(mouse); }
    }

    function seekTo(mouse) {
        let u;
        if (root.bend < 0.5) {
            u = Math.max(0, Math.min(1, (mouse.x - root.lineWidthPx) / (width - 2 * root.lineWidthPx)));
        } else {
            u = (Math.atan2(mouse.y - height / 2, mouse.x - width / 2) + Math.PI / 2) / (2 * Math.PI);
            if (u < 0) u += 1;
        }
        root.sought(u);
        const player = MprisController.activePlayer;
        if (player && player.canSeek)
            player.position = u * player.length;
    }
}
