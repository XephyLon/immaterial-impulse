import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.services
import "../../designsystem/widgets" as Expressive
import "../../designsystem/widgets/shapes/material-shapes.js" as MaterialShapes
import "../../designsystem/widgets/shapes/path-length.js" as PathLength

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

    // ---- 3x2 prev/next: the cassette reels -------------------------------
    Loader {
        active: !root.isPlay && root.span === "3x2"
        anchors.fill: parent
        sourceComponent: Item {
            // Only the scalloped shape rotates; the icon and hit area are
            // siblings so the skip glyph stays upright. Both cogs spin the
            // same way like the two reels of a cassette while playing.
            Expressive.MaterialShape {
                id: reelShape
                anchors.fill: parent
                shape: Expressive.MaterialShape.Shape.Cookie12Sided
                color: root.controlColor

                property bool spinning: MprisController.isPlaying
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
                iconSize: 28 * Appearance.effectiveScale
                fill: 0
                color: hitArea.containsMouse
                    ? (Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimary)
                    : root.controlIconColor
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ---- 2x2/2x1 prev/next: the badge and pill circles -------------------
    Loader {
        active: !root.isPlay && root.span !== "3x2"
        anchors.fill: parent
        sourceComponent: Rectangle {
            radius: height / 2
            color: root.controlColor
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                text: root.role === "prev" ? "skip_previous" : "skip_next"
                // The badge sizes its glyph from its own height (the clock's
                // ratio); the pill uses the layout's fixed 26.
                iconSize: root.span === "2x2"
                    ? parent.height * 0.46
                    : 26 * Appearance.effectiveScale
                fill: 0
                color: hitArea.containsMouse ? Appearance.colors.colPrimary : root.controlIconColor
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }
        }
    }

    // ---- 3x2 play: the wide pill -----------------------------------------
    Loader {
        active: root.isPlay && root.span === "3x2"
        anchors.fill: parent
        sourceComponent: Rectangle {
            radius: 33 * Appearance.effectiveScale
            color: Appearance.colors.colPrimary
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: 40 * Appearance.effectiveScale
                fill: 0
                color: hitArea.pressed
                    ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.7)
                    : Appearance.colors.colOnPrimary
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Appearance.colors.colOnPrimary
                opacity: hitArea.pressed ? 0.15 : (hitArea.containsMouse ? 0.08 : 0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }

    // ---- 2x1 play: the cookie whose outline is the seek ring -------------
    Loader {
        active: root.isPlay && root.span === "2x1"
        anchors.fill: parent
        sourceComponent: Item {
            // The button body and the seek ring are two concentric draws of one
            // cookie outline: the body sits inside the ring rather than under
            // it, so the stroke reads as the button's border and not as a line
            // laid over its edge.
            Canvas {
                id: cookieCanvas
                anchors.fill: parent

                readonly property real strokeWidth: Appearance.borderWidth.heavy * Appearance.effectiveScale
                readonly property var polygon: MaterialShapes.getCookie12Sided()
                // Measured once: the shape never changes, so a moving progress
                // costs a dash pattern rather than a re-measure.
                readonly property real outlineLength: PathLength.measureCubics(cookieCanvas.polygon.cubics).total
                // The dash starts where the path does; turning that point to
                // the top makes progress start at twelve o'clock.
                readonly property real startRotation: {
                    const cubics = cookieCanvas.polygon.cubics;
                    if (cubics.length === 0)
                        return 0;
                    return -Math.PI / 2 - Math.atan2(cubics[0].anchor0Y - 0.5, cubics[0].anchor0X - 0.5);
                }

                // A Canvas repaints on resize and on nothing else - every
                // input onPaint reads is mirrored here to be observed.
                readonly property real ringProgress: root.progress
                readonly property color bodyColor: Appearance.colors.colPrimary
                readonly property color trackColor: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onRingProgressChanged: requestPaint()
                onBodyColorChanged: requestPaint()
                onTrackColorChanged: requestPaint()

                function trace(ctx, diameter) {
                    const cubics = cookieCanvas.polygon.cubics;
                    ctx.save();
                    ctx.translate(width / 2, height / 2);
                    ctx.rotate(cookieCanvas.startRotation);
                    ctx.scale(diameter, diameter);
                    ctx.translate(-0.5, -0.5);
                    ctx.beginPath();
                    ctx.moveTo(cubics[0].anchor0X, cubics[0].anchor0Y);
                    for (const cubic of cubics)
                        ctx.bezierCurveTo(cubic.control0X, cubic.control0Y,
                            cubic.control1X, cubic.control1Y, cubic.anchor1X, cubic.anchor1Y);
                    ctx.closePath();
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (cookieCanvas.polygon.cubics.length === 0)
                        return;

                    const size = Math.min(width, height);
                    const stroke = cookieCanvas.strokeWidth;
                    const ringDiameter = size - stroke;
                    const bodyDiameter = ringDiameter - stroke * 3;

                    trace(ctx, bodyDiameter);
                    ctx.fillStyle = cookieCanvas.bodyColor;
                    ctx.fill();
                    ctx.restore();

                    // lineWidth divided by the diameter because the scale
                    // drawing the path scales the pen; the dash pattern is in
                    // multiples of that width - Qt's unit, not HTML's.
                    trace(ctx, ringDiameter);
                    ctx.lineWidth = stroke / ringDiameter;
                    ctx.setLineDash([]);
                    ctx.strokeStyle = cookieCanvas.trackColor;
                    ctx.stroke();
                    ctx.restore();

                    if (cookieCanvas.ringProgress > 0) {
                        trace(ctx, ringDiameter);
                        ctx.lineWidth = stroke / ringDiameter;
                        ctx.setLineDash(PathLength.dashInPenWidths(
                            cookieCanvas.outlineLength, cookieCanvas.ringProgress, ctx.lineWidth));
                        ctx.strokeStyle = cookieCanvas.bodyColor;
                        ctx.stroke();
                        ctx.setLineDash([]);
                        ctx.restore();
                    }
                }
            }
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: 30 * Appearance.effectiveScale
                fill: 0
                color: hitArea.pressed
                    ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.7)
                    : Appearance.colors.colOnPrimary
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }
        }
    }

    // ---- 2x2 play: the artwork circle ------------------------------------
    Loader {
        active: root.isPlay && root.span === "2x2"
        anchors.fill: parent
        sourceComponent: Item {
            id: artCircle
            readonly property bool hasArt: root.artUrl !== "" && albumArt.status === Image.Ready
            // Clipped to a circle rather than to the cookie: the lobes are
            // what ripples, so masking the artwork with the moving outline
            // would swallow the motion. The circle sits inside the lobes'
            // valleys, leaving the scalloped edge visible all the way round.
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artCircle.width
                    height: artCircle.height
                    radius: width / 2
                }
            }
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colOnPrimary
            }
            Image {
                id: albumArt
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: artCircle.hasArt
            }
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colOnPrimary
                opacity: !artCircle.hasArt ? 0 : (hitArea.containsMouse ? 0.55 : 0)
                Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }
            Expressive.MaterialSymbol {
                anchors.centerIn: parent
                visible: !artCircle.hasArt || hitArea.containsMouse
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: 34 * Appearance.effectiveScale
                fill: 0
                color: Appearance.colors.colPrimary
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
