import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as Functions
import qs.services
import "../../designsystem/widgets" as Expressive
import qs.modules.common.plugins.designsystem.services
import "../../designsystem/widgets/shapes/material-shapes.js" as MaterialShapes
import "../../designsystem/widgets/visualizer_bands.js" as VisualizerBands
import "../../designsystem/widgets/shapes/path-length.js" as PathLength
import "media_shapes.js" as MediaShapes

// One transport control, at every span.
//
// This is the element the whole expressive-morphing design exists for: the
// play button at 3x2 and the play button at 2x1 used to be different objects
// in different files that had never coexisted, so a span change destroyed one
// and constructed the other. Here the button is ONE object whose *style*
// follows the span - the tree repositions it (media_geometry.js owns where)
// and this file owns what it looks like when it gets there.
//
// The styles are the three layouts' own, moved rather than redesigned:
// - 3x2 prev/next: the spinning Cookie12Sided cassette reels (issue #60).
// - 3x2 play: the wide primary pill.
// - 2x2 prev/next: the clock's corner badges. 2x2 play: the artwork circle,
//   because tapping the cookie is what toggles playback there.
// - 2x1 prev/next: the small pills. 2x1 play: the cookie whose outline is
//   also the seek ring - two concentric draws of one path.
//
// Each style lives behind a Loader keyed on (role, span): only one exists at
// a time, so the 2x1's ring canvas is not painting at 3x2 and the 2x2's
// artwork holds no image elsewhere. The BUTTON survives a span change; its
// clothing is allowed to swap. (Cross-style shape morphing is step 6's work,
// on the resize's clock - not smuggled in here.)
Item {
    id: root

    // "prev" | "play" | "next"
    required property string role
    // "3x2" | "2x2" | "2x1"
    required property string span

    // 2x1 play only: the seek ring's fill.
    property real progress: 0
    // 2x2 play only: the artwork.
    property string artUrl: ""
    // 2x1 only: the seeker's wave, so the button's contour and the ring are
    // the same rotating spring. Phase is plumbed from the seeker; both sample
    // the same cookie by the same arc-length walk at the same frequency, so
    // the curves are identical by construction.
    property real ringPhase: 0
    property bool ringWaves: false
    // The seeker's wave amplitude level (0..1), so the body's spring fades
    // out with the ring's on pause instead of chopping flat.
    property real ringWaveLevel: 0
    // Play only: the seeker above this button reports hover it is holding
    // on the button's behalf, so the glyph-over-art and hover styling work
    // under the ring's cover.
    property bool coveredHover: false


    readonly property bool isPlay: root.role === "play"

    // The shared interaction states (step 9). The control keeps its own
    // painting; the model decides only how far into hover and press it is,
    // and on which tier it travels - so these buttons and every RippleButton
    // in the shell acknowledge a press on the same clock.
    // Hover has to be forwarded from the seeker (hover does not propagate);
    // the press does not, because the seeker rejects anything off its stroke
    // and an unaccepted press falls through to this button's own area.
    readonly property InteractionMotion motion: InteractionMotion {
        hovered: root.hoveredNow
        down: hitArea.pressed
    }

    // The colour pair the 2x1 pills and 2x2 badges share (LayoutCompact and
    // LayoutCookie declared them identically, which is why they read as one
    // widget's controls).
    readonly property color controlColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colOnTertiaryContainer
        : Appearance.colors.colSecondaryContainer
    readonly property color controlIconColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colTertiaryContainer
        : Appearance.colors.colOnSecondaryContainer

    // Emitted on every pointer activation, before the action - what the
    // pointer sweep scores, since the action itself would toggle whatever
    // the session is really playing.
    signal activated()

    function trigger() {
        if (root.role === "prev") MprisController.previous();
        else if (root.role === "next") MprisController.next();
        else MprisController.togglePlaying();
    }

    // ---- prev/next: one shape, every span --------------------------------
    //
    // The reel at 3x2 and the circle elsewhere are ONE MaterialShape whose
    // `shape` follows the span - ShapeCanvas morphs on any polygon change
    // (the wallpaper shape picker is the proof), so leaving 3x2 the scalloped
    // reel gracefully rounds into the badge/pill circle instead of being a
    // different object. The spin eases back to rest through the same
    // Behavior that always owned it, so the reel stops turning as it stops
    // being a reel.
    // What the badge is ACTUALLY drawn at. The model saying "hovered" is not
    // evidence the lift reached a pixel: the first version applied it through
    // a `Scale` whose `origin.x: width / 2` resolved against a scope with no
    // width, and every state property read correctly while the badge never
    // moved. A probe can watch this one.
    readonly property real appliedBadgeScale: badgeLoader.item ? badgeLoader.item.scale : 1
    Loader {
        id: badgeLoader
        active: !root.isPlay
        anchors.fill: parent
        sourceComponent: Item {
            // The badge lifts on hover and settles on press. The PLAY button
            // deliberately does not: the seek ring is a perfect circle inside
            // it at 2x2 and its own outline at 2x1, and scaling one and not
            // the other pulls apart an alignment the review asked for
            // explicitly. Its feedback is the wash on its own outline, which
            // is what the ring is drawn around anyway.
            // Item.scale, not a Scale transform: `origin.x: width / 2` inside
            // the transform resolved against a scope with no width and the
            // lift never reached a pixel, while every state property said it
            // had. `scale` is centred by default and cannot miss.
            scale: root.motion.scale

            Expressive.MaterialShape {
                id: reelShape
                anchors.fill: parent
                shape: root.span === "3x2"
                    ? Expressive.MaterialShape.Shape.Cookie12Sided
                    : Expressive.MaterialShape.Shape.Circle
                color: root.controlColor

                property bool spinning: root.span === "3x2" && MprisController.isPlaying
                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 9000
                    loops: Animation.Infinite
                    running: reelShape.spinning
                }
                onSpinningChanged: if (!spinning) rotation = 0
                Behavior on rotation {
                    enabled: !reelShape.spinning
                    RotationAnimation { direction: RotationAnimation.Shortest; duration: 300; easing.type: Easing.OutCubic }
                }
            }
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                text: root.role === "prev" ? "skip_previous" : "skip_next"
                iconSize: root.span === "3x2" ? 28 * Appearance.effectiveScale
                    : root.span === "2x2" ? parent.height * 0.46
                    : 26 * Appearance.effectiveScale
                fill: 0
                color: root.hoveredNow
                    ? (root.span === "3x2" && Appearance.m3colors.darkmode
                        ? Appearance.colors.colTertiaryContainer
                        : Appearance.colors.colPrimary)
                    : root.controlIconColor
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }
        }
    }

    // ---- play: the button that holds everything --------------------------
    //
    // The play button is the CONTAINER (the review's words): the artwork
    // lives inside it and appears from within when the span offers it; the
    // seek ring lives inside it, a perfect circle at 2x2 and the button's own
    // outline at 2x1. Nothing here is a per-span Loader any more - one body,
    // one artwork, one ring, each morphing between its per-span selves.
    Loader {
        active: root.isPlay
        anchors.fill: parent
        sourceComponent: Item {
            id: playRoot
            readonly property real side: Math.min(width, height)
            readonly property real strokeWidth: Appearance.borderWidth.heavy * Appearance.effectiveScale

            // The body: a true capsule at 3x2 and the cookie elsewhere, one
            // Morph in one coordinate space (media_shapes.js). The library's
            // normalized "Pill" stretched to 192x66 is an ellipse - that
            // ellipse shipped, and this replaces it. Same colour at every
            // span: the colour flip was half of what read as a blink.
            // THE BODY IS THE VISUALIZER (the review's question, answered
            // yes): one canvas that draws the capsule-to-cookie morph in
            // flight and, settled at 2x2, breathes the same cookie with
            // per-lobe audio levels. No separate visualizer object, so no
            // crossfade, no proof gate, no stacked twin masking the ripple -
            // the machinery that existed only because the breathing shape
            // and the button's shape were two objects is gone with the
            // second object.
            Canvas {
                id: body
                anchors.fill: parent
                // ONE painter owns the body at every span - handing the face
                // to a second canvas at any settle has now blanked it twice
                // (the visualizer crossfade, then a seeker-fill handoff), so
                // the rule is structural: this canvas never yields. At 2x1 it
                // waves in the seeker's phase instead.

                // Hover and press ride the BODY's own outline instead of a
                // rectangle laid over it: the flat wash was square-cornered
                // against a capsule at 3x2 and could not follow the cookie at
                // all. One painter owns this face, so it paints the state too.
                readonly property real washAlpha: 0.08 * root.motion.hoverProgress
                    + 0.07 * root.motion.pressProgress
                onWashAlphaChanged: requestPaint()
                readonly property color washColor: Appearance.colors.colOnPrimary

                property real morphT: root.span === "3x2" ? 0 : 1
                Behavior on morphT { Expressive.SpanTravel {} }
                readonly property color bodyColor: Appearance.colors.colPrimary

                // ---- the breath: the lobe envelope, tuned in visualizer_bands.js ----
                readonly property bool visualizing: root.span === "2x2"
                    && Math.abs(morphT - 1) < 0.01 && MprisController.isPlaying && root.visible
                property list<real> levels: []
                property bool settlingLevels: false
                readonly property var cavaClaim: CavaRef { active: body.visualizing }
                function stepLevels() {
                    const targets = VisualizerBands.toLobes(
                        body.visualizing ? CavaService.values : [], 12, CavaService.maxValue);
                    const next = [];
                    let moved = false;
                    for (let i = 0; i < 12; i++) {
                        const current = i < body.levels.length ? body.levels[i] : 0;
                        const level = VisualizerBands.envelope(
                            current, targets[i], VisualizerBands.ATTACK, VisualizerBands.DECAY);
                        const settled = Math.abs(targets[i] - level) <= VisualizerBands.SETTLE_EPSILON
                            ? targets[i] : level;
                        if (settled !== current) moved = true;
                        next.push(settled);
                    }
                    body.settlingLevels = moved;
                    if (moved) { body.levels = next; body.requestPaint(); }
                }
                onVisualizingChanged: body.settlingLevels = true
                readonly property Timer levelTimer: Timer {
                    interval: 16
                    repeat: true
                    running: body.visible && (body.visualizing || body.settlingLevels)
                    onTriggered: body.stepLevels()
                }

                // Fills the path that is already current - the wash is the
                // body's shape by construction, never an approximation of it.
                function washOver(ctx) {
                    if (body.washAlpha <= 0.001) return;
                    ctx.fillStyle = Functions.ColorUtils.applyAlpha(
                        body.washColor, body.washAlpha);
                    ctx.fill();
                }

                onMorphTChanged: requestPaint()
                readonly property real phaseNow: root.ringPhase
                onPhaseNowChanged: if (root.ringWaveLevel > 0.001) requestPaint()
                readonly property real ringLevelNow: root.ringWaveLevel
                onRingLevelNowChanged: requestPaint()
                readonly property bool wavesNow: root.ringWaves
                onWavesNowChanged: requestPaint()
                onBodyColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const waving2x1 = root.span === "2x1" && Math.abs(body.morphT - 1) < 0.01
                        && root.ringWaveLevel > 0.001;
                    if (waving2x1) {
                        const N = 160;
                        const stroke = Appearance.borderWidth.heavy * Appearance.effectiveScale;
                        const dia = Math.min(width, height) - stroke;
                        // Same cache the seeker uses - this canvas was
                        // rebuilding and re-measuring the identical constant
                        // shape (ringAt(1)) once per frame beside it.
                        const ring = MediaShapes.ringMeasuredAt(1, PathLength.measureCubics);
                        const cubics = ring.cubics;
                        const measure = ring.measure;
                        const amp = stroke * 0.6 * root.ringWaveLevel;
                        // VERBATIM the seeker's construction - arc-length
                        // samples, normals from RAW neighbours, sine along the
                        // normal - so the filled contour and the stroked ring
                        // are the same curve at the same phase, crest for
                        // crest. The first version improvised a radial-scale
                        // wobble and the two visibly disagreed.
                        const base = [];
                        for (let i = 0; i <= N; i++) {
                            const u = i / N;
                            const target = u * measure.total;
                            let index = 0;
                            while (index < cubics.length - 1 && measure.lengths[index + 1] < target) index++;
                            const span = measure.lengths[index + 1] - measure.lengths[index];
                            const t = span > 0 ? (target - measure.lengths[index]) / span : 0;
                            const point = PathLength.pointOnCubic(cubics[index], t);
                            base.push({ x: width / 2 + point.x * dia, y: height / 2 + point.y * dia });
                        }
                        ctx.beginPath();
                        for (let i = 0; i <= N; i++) {
                            const before = base[Math.max(0, i - 1)];
                            const after = base[Math.min(N, i + 1)];
                            let nx = -(after.y - before.y), ny = after.x - before.x;
                            const len = Math.hypot(nx, ny) || 1;
                            nx /= len; ny /= len;
                            const w = amp * Math.sin(12 * 2 * Math.PI * (i / N) + root.ringPhase);
                            const x = base[i].x + nx * w, y = base[i].y + ny * w;
                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                        }
                        ctx.closePath();
                        ctx.fillStyle = body.bodyColor;
                        ctx.fill();
                        body.washOver(ctx);
                        return;
                    }
                    // Breathing takes over only once a lobe actually moves:
                    // star() and starPerLobe() build the resting cookie by
                    // slightly different vertex paths, and swapping recipes at
                    // the settle threshold flickered one frame of not-quite-
                    // the-same shape. At rest the morph endpoint IS the shape.
                    const hasBreath = body.levels.some(l => l > 0.004);
                    const breathing = root.span === "2x2" && Math.abs(body.morphT - 1) < 0.01 && hasBreath;
                    const shape = breathing
                        // FIXED bounds for the breathing shape, on purpose:
                        // fitting the live bounds would rescale the whole
                        // cookie every frame, so a lobe pushing out shrinks
                        // the other eleven.
                        // The resting cookie spans the unit box; lobes breathe
                        // within and slightly past it.
                        ? { cubics: MediaShapes.liveCookieRaw(body.levels, 12).cubics,
                            minX: -0.5, minY: -0.5, maxX: 0.5, maxY: 0.5 }
                        : MediaShapes.bodyAt(body.morphT);
                    if (shape.cubics.length === 0) return;
                    // Fit the mid-flight bounds into the box: the capsule is
                    // wider than tall and the box is travelling, so scaling by
                    // either axis alone clips the other mid-morph.
                    const spanX = Math.max(0.001, shape.maxX - shape.minX);
                    const spanY = Math.max(0.001, shape.maxY - shape.minY);
                    const scale = Math.min(width / spanX, height / spanY);
                    ctx.save();
                    ctx.translate(width / 2 - (shape.minX + spanX / 2) * scale,
                                  height / 2 - (shape.minY + spanY / 2) * scale);
                    ctx.scale(scale, scale);
                    ctx.beginPath();
                    ctx.moveTo(shape.cubics[0].anchor0X, shape.cubics[0].anchor0Y);
                    for (const cubic of shape.cubics)
                        ctx.bezierCurveTo(cubic.control0X, cubic.control0Y,
                            cubic.control1X, cubic.control1Y, cubic.anchor1X, cubic.anchor1Y);
                    ctx.closePath();
                    ctx.fillStyle = body.bodyColor;
                    ctx.fill();
                    body.washOver(ctx);
                    ctx.restore();
                }
            }

            // The artwork, from WITHIN: a circle centred in the button that
            // grows out of nothing when the span is 2x2 and returns into the
            // button when it is not.
            //
            // Clipped by a Canvas clip path, NOT an OpacityMask: the mask's
            // ShaderEffect composited as opaque black on the sandbox's
            // software GL and blanked the entire play face there - and a
            // shader-free clip is also one less per-frame ShaderEffectSource
            // on the desktop. The fallback disc and hover wash are plain
            // radius rectangles, which never needed a mask at all.
            Item {
                id: artClip
                objectName: "playArtwork"
                anchors.centerIn: parent
                width: root.span === "2x2" ? playRoot.side * 0.66 : 0
                height: width
                Behavior on width { Expressive.SpanTravel {} }
                visible: width > 1
                property bool artLoaded: false

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colOnPrimary
                }
                Canvas {
                    id: artCanvas
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    property string artSource: root.artUrl
                    onArtSourceChanged: {
                        artClip.artLoaded = false;
                        if (artSource !== "") loadImage(artSource);
                        requestPaint();
                    }
                    Component.onCompleted: if (artSource !== "") loadImage(artSource)
                    onImageLoaded: {
                        artClip.artLoaded = artSource !== "" && isImageLoaded(artSource);
                        requestPaint();
                    }
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        if (!artClip.artLoaded) return;
                        ctx.save();
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, Math.min(width, height) / 2, 0, Math.PI * 2);
                        ctx.clip();
                        ctx.drawImage(artCanvas.artSource, 0, 0, width, height);
                        ctx.restore();
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colOnPrimary
                    opacity: !artClip.artLoaded ? 0 : (root.hoveredNow ? 0.55 : 0)
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                }
            }

            // The glyph. Over artwork it appears on hover, as it always did at
            // 2x2; everywhere else it is the button's face.
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                visible: !artClip.visible || !artClip.artLoaded || root.hoveredNow
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: (root.span === "3x2" ? 40 : root.span === "2x2" ? 34 : 30) * Appearance.effectiveScale
                fill: 0
                color: hitArea.pressed
                    ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.7)
                    : (artClip.visible && artClip.artLoaded ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary)
                Behavior on color { ColorAnimation { duration: 100 } }
            }

        }
    }

    // Plain MouseArea hover, deliberately: the HoverHandler detour set two
    // cooperative handlers arguing over the cursor (the seeker's, still
    // hovered under the button, answered Arrow while this one answered
    // pointing - the cursor never changed). The z ladder now guarantees the
    // interactive thing is topmost, so the bar's battle-tested pattern -
    // hoverEnabled + cursorShape on the input area itself - is sufficient
    // and unambiguous.
    // Hover STATE comes from a HoverHandler; the cursor and the clicks stay
    // with the MouseArea below. Those are different channels (the two-handlers
    // lesson was about both of them answering for the CURSOR), and this one
    // has to be the handler: at 2x2 and 2x1 the seek ring sits ABOVE this
    // button, so once a press grab ends, the pointer's leave is delivered to
    // the ring and a MouseArea's containsMouse here stays true forever - the
    // button sat permanently hovered, which at 2x2 means the play glyph never
    // leaves the artwork again. A HoverHandler tracks the scene position and
    // clears.
    readonly property bool hoveredNow: hoverTracker.hovered || root.coveredHover
    HoverHandler { id: hoverTracker }
    MouseArea {
        id: hitArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.activated(); root.trigger(); }
    }
}
