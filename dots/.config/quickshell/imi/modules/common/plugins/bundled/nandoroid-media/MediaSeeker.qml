import QtQuick
import qs.modules.common
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
    Behavior on bend { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
    // 0 = circle .. 1 = cookie outline
    property real ringT: root.span === "2x1" ? 1 : 0
    Behavior on ringT { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }

    property real phase: 0
    // The travelling wave, alive only while something plays and the item is
    // on screen - a FrameAnimation with no gate is the idle-repaint bug.
    FrameAnimation {
        running: root.visible && root.playing && root.opacity > 0
        onTriggered: { root.phase += frameTime * 2.5; canvas.requestPaint(); }
    }

    readonly property real lineWidthPx:
        (4 + (Appearance.borderWidth.heavy - 4) * root.bend) * Appearance.effectiveScale

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        readonly property real bendNow: root.bend
        readonly property real ringNow: root.ringT
        readonly property real progressNow: Math.max(0, Math.min(1, root.progress))
        readonly property color arcColor: root.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, root.bend)
        readonly property color trackColor: root.mix(
            Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25),
            Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.3), root.bend)
        readonly property bool playingNow: root.playing

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

            // The ring baseline, arc-length parameterised so the wave's
            // wavelength is even all the way round.
            const cubics = MediaShapes.ringAt(canvas.ringNow);
            const measure = PathLength.measureCubics(cubics);
            function ringPoint(u) {
                const target = u * measure.total;
                let index = 0;
                while (index < cubics.length - 1 && measure.lengths[index + 1] < target) index++;
                const span = measure.lengths[index + 1] - measure.lengths[index];
                const t = span > 0 ? (target - measure.lengths[index]) / span : 0;
                const point = PathLength.pointOnCubic(cubics[index], t);
                // raw shapes are centred on the origin at height 1
                return { x: cx + point.x * dia, y: cy + point.y * dia };
            }

            // Wavelength: 6 cycles across the bar; an INTEGER count around the
            // closed ring or the wave beats against its own seam (the spec's
            // arc-length note). 12 matches the cookie's lobes.
            const freq = Math.round(6 + (12 - 6) * canvas.bendNow);
            const amp = (canvas.playingNow ? stroke * 0.6 : 0);

            const points = [];
            for (let i = 0; i <= N; i++) {
                const u = i / N;
                const line = { x: pad + u * (width - 2 * pad), y: cy };
                const ring = ringPoint(u);
                const x = line.x + (ring.x - line.x) * canvas.bendNow;
                const y = line.y + (ring.y - line.y) * canvas.bendNow;
                points.push({ x: x, y: y });
            }
            // normals from neighbours, wave displacement along them
            for (let i = 0; i <= N; i++) {
                const before = points[Math.max(0, i - 1)];
                const after = points[Math.min(N, i + 1)];
                let nx = -(after.y - before.y), ny = after.x - before.x;
                const len = Math.hypot(nx, ny) || 1;
                nx /= len; ny /= len;
                const w = amp * Math.sin(freq * 2 * Math.PI * (i / N) + root.phase);
                points[i] = { x: points[i].x + nx * w, y: points[i].y + ny * w };
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

    MouseArea {
        anchors.fill: parent
        // A ring's hit area is its stroke, not its disc - a filled hit disc
        // over the play button would eat the button's own clicks.
        onPressed: mouse => root.seekTo(mouse)
        onPositionChanged: mouse => { if (pressed) root.seekTo(mouse); }
        enabled: MprisController.activePlayer !== null && (MprisController.activePlayer.canSeek ?? false)
    }

    function seekTo(mouse) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) return;
        let u;
        if (root.bend < 0.5) {
            u = Math.max(0, Math.min(1, (mouse.x - root.lineWidthPx) / (width - 2 * root.lineWidthPx)));
        } else {
            u = (Math.atan2(mouse.y - height / 2, mouse.x - width / 2) + Math.PI / 2) / (2 * Math.PI);
            if (u < 0) u += 1;
        }
        player.position = u * player.length;
    }
}
