import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.services
import "../../designsystem/widgets" as Expressive
import "../../designsystem/widgets/shapes/material-shapes.js" as MaterialShapes
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
    // 2x2 play only: whether the tree-level visualizer cookie has painted -
    // the static body yields only on this proof.
    property bool liveCookiePainted: false

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

            // The body: a true capsule at 3x2 and the cookie elsewhere, one
            // Morph in one coordinate space (media_shapes.js). The library's
            // normalized "Pill" stretched to 192x66 is an ellipse - that
            // ellipse shipped, and this replaces it. Same colour at every
            // span: the colour flip was half of what read as a blink.
            Canvas {
                id: body
                anchors.fill: parent
                // At settled 2x2 the LIVE cookie (the visualizer) is the body,
                // and this static twin yields - stacked, the static cookie
                // masked every inward ripple and the visualizer read as
                // frozen. During any transition the static body carries the
                // morph and the visualizer is the one that yields.
                // ...and only on PROOF: the host tells this button its live
                // cookie has actually painted before the static body steps
                // aside. A dropped or non-compositing first paint otherwise
                // leaves the whole face blank - the sandbox reproduced that
                // with the visualizer nested in here, which is why it lives
                // at tree level now (the configuration that demonstrably
                // paints) and reports back through this flag.
                opacity: root.span === "2x2" && root.liveCookiePainted
                    && Math.abs(morphT - 1) < 0.01 ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                property real morphT: root.span === "3x2" ? 0 : 1
                Behavior on morphT { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
                readonly property color bodyColor: Appearance.colors.colPrimary

                onMorphTChanged: requestPaint()
                onBodyColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const shape = MediaShapes.bodyAt(body.morphT);
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
                width: root.span === "2x2" ? playRoot.side * 0.72 : 0
                height: width
                Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
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
                    opacity: !artClip.artLoaded ? 0 : (hitArea.containsMouse ? 0.55 : 0)
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                }
            }

            // The glyph. Over artwork it appears on hover, as it always did at
            // 2x2; everywhere else it is the button's face.
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                visible: !artClip.visible || !artClip.artLoaded || hitArea.containsMouse
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: (root.span === "3x2" ? 40 : root.span === "2x2" ? 34 : 30) * Appearance.effectiveScale
                fill: 0
                color: hitArea.pressed
                    ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.7)
                    : (artClip.visible && artClip.artLoaded ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary)
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
        onClicked: { root.activated(); root.trigger(); }
    }
}
