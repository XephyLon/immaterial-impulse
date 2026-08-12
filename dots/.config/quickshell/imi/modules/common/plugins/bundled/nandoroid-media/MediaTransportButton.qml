import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.services
import "../../designsystem/widgets" as Expressive
import "../../designsystem/widgets/shapes/material-shapes.js" as MaterialShapes
import "../../designsystem/widgets/shapes/path-length.js" as PathLength
import "../../designsystem/widgets/shapes/morph.js" as MorphLib

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

    readonly property bool isPlay: root.role === "play"

    // The colour pair the 2x1 pills and 2x2 badges share (LayoutCompact and
    // LayoutCookie declared them identically, which is why they read as one
    // widget's controls).
    readonly property color controlColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colOnTertiaryContainer
        : Appearance.colors.colSecondaryContainer
    readonly property color controlIconColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colTertiaryContainer
        : Appearance.colors.colOnSecondaryContainer

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
    Loader {
        active: !root.isPlay
        anchors.fill: parent
        sourceComponent: Item {
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
                color: hitArea.containsMouse
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

            // The body: a pill at 3x2, the cookie elsewhere. One MaterialShape,
            // stretched to the button's box, so ShapeCanvas morphs pill to
            // cookie the way it morphs everything else. Same colour at every
            // span - the colour flip was half of what read as a blink.
            Expressive.MaterialShape {
                id: body
                anchors.fill: parent
                stretch: true
                shape: root.span === "3x2"
                    ? Expressive.MaterialShape.Shape.Pill
                    : Expressive.MaterialShape.Shape.Cookie12Sided
                color: Appearance.colors.colPrimary
            }

            // The living cookie: audio-reactive lobes over the static body at
            // 2x2. It fades in over a body that is already the same cookie, so
            // its arrival is a shimmer, not an appearance.
            Loader {
                anchors.fill: parent
                active: root.span === "2x2"
                sourceComponent: Expressive.VisualizerCookie {
                    lobes: 12
                    audioReactive: MprisController.isPlaying
                    color: Appearance.colors.colPrimary
                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveEffects } }
                }
            }

            // The artwork, from WITHIN: a circle centred in the button that
            // grows out of nothing when the span is 2x2 and returns into the
            // button when it is not.
            Item {
                id: artClip
                objectName: "playArtwork"
                anchors.centerIn: parent
                width: root.span === "2x2" ? playRoot.side * 0.72 : 0
                height: width
                Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
                visible: width > 1
                readonly property bool hasArt: root.artUrl !== "" && albumArt.status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: artClip.width
                        height: artClip.height
                        radius: width / 2
                    }
                }
                Rectangle { anchors.fill: parent; color: Appearance.colors.colOnPrimary }
                Image {
                    id: albumArt
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: artClip.hasArt
                }
                Rectangle {
                    anchors.fill: parent
                    color: Appearance.colors.colOnPrimary
                    opacity: !artClip.hasArt ? 0 : (hitArea.containsMouse ? 0.55 : 0)
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                }
            }

            // The seek ring: a perfect circle inside the button at 2x2, the
            // button's own cookie outline at 2x1, and faded out at 3x2 (the
            // wavy bar is the seeker there). The two shapes are one Morph -
            // the same feature-matching the wallpaper picker uses - driven by
            // a Behavior, so leaving 2x2 the circle GROWS AND CRINKLES into
            // the outline rather than being replaced by it.
            Canvas {
                id: ring
                objectName: "playRing"
                anchors.fill: parent

                // 0 = inner circle (2x2) .. 1 = outline cookie (2x1)
                property real morphT: root.span === "2x1" ? 1 : 0
                Behavior on morphT { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
                opacity: root.span === "3x2" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveEffects } }
                visible: opacity > 0

                readonly property var ringMorph: new MorphLib.Morph(
                    MaterialShapes.getCircle(), MaterialShapes.getCookie12Sided())
                readonly property real ringProgress: root.progress
                readonly property color arcColor: Appearance.colors.colOnPrimary
                readonly property color trackColor: Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.3)
                // circle sits just outside the artwork; outline sits on the
                // button's edge. The diameter rides the same morph clock.
                readonly property real diameter: (playRoot.side * 0.82)
                    + ((playRoot.side - ring.strokePx) - playRoot.side * 0.82) * ring.morphT
                readonly property real strokePx: playRoot.strokeWidth

                onMorphTChanged: requestPaint()
                onRingProgressChanged: requestPaint()
                onArcColorChanged: requestPaint()
                onTrackColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: requestPaint()

                function trace(ctx, cubics, dia) {
                    // Start angle turned to twelve o'clock, as the 2x1 always did.
                    const first = cubics[0];
                    const startRotation = -Math.PI / 2 - Math.atan2(first.anchor0Y - 0.5, first.anchor0X - 0.5);
                    ctx.save();
                    ctx.translate(width / 2, height / 2);
                    ctx.rotate(startRotation);
                    ctx.scale(dia, dia);
                    ctx.translate(-0.5, -0.5);
                    ctx.beginPath();
                    ctx.moveTo(first.anchor0X, first.anchor0Y);
                    for (const cubic of cubics)
                        ctx.bezierCurveTo(cubic.control0X, cubic.control0Y,
                            cubic.control1X, cubic.control1Y, cubic.anchor1X, cubic.anchor1Y);
                    ctx.closePath();
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (!visible) return;
                    const cubics = ring.ringMorph.asCubics(ring.morphT);
                    if (cubics.length === 0) return;
                    // Re-measured because the outline is mid-morph; at rest the
                    // inputs stop changing and so do the repaints.
                    const total = PathLength.measureCubics(cubics).total;

                    trace(ctx, cubics, ring.diameter);
                    ctx.lineWidth = ring.strokePx / ring.diameter;
                    ctx.setLineDash([]);
                    ctx.strokeStyle = ring.trackColor;
                    ctx.stroke();
                    ctx.restore();

                    if (ring.ringProgress > 0) {
                        trace(ctx, cubics, ring.diameter);
                        ctx.lineWidth = ring.strokePx / ring.diameter;
                        ctx.setLineDash(PathLength.dashInPenWidths(total, ring.ringProgress, ctx.lineWidth));
                        ctx.strokeStyle = ring.arcColor;
                        ctx.stroke();
                        ctx.setLineDash([]);
                        ctx.restore();
                    }
                }
            }

            // The glyph. Over artwork it appears on hover, as it always did at
            // 2x2; everywhere else it is the button's face.
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                visible: !artClip.visible || !artClip.hasArt || hitArea.containsMouse
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: (root.span === "3x2" ? 40 : root.span === "2x2" ? 34 : 30) * Appearance.effectiveScale
                fill: 0
                color: hitArea.pressed
                    ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.7)
                    : (artClip.visible && artClip.hasArt ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary)
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            // The 3x2 pill's hover/press wash, riding the body's own shape is
            // step 8's interaction-model work; the flat wash keeps parity.
            Rectangle {
                anchors.fill: parent
                radius: playRoot.side / 2
                color: Appearance.colors.colOnPrimary
                visible: root.span === "3x2"
                opacity: hitArea.pressed ? 0.15 : (hitArea.containsMouse ? 0.08 : 0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }

    MouseArea {
        id: hitArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.trigger()
    }
}
