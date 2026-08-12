import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.services
import "../../designsystem/widgets" as Expressive
import "../../designsystem/widgets/shapes/material-shapes.js" as MaterialShapes
import "../../designsystem/widgets/shapes/path-length.js" as PathLength

// The 2x1 media widget: prev, play/pause, next, centred. No text and no
// artwork - but playback progress is there, stroked around the centre button's
// own cookie outline rather than drawn as a separate track underneath, which is
// what makes the three controls read as one object.
//
// The cookie here is static, unlike the 2x2's. A rippling outline carrying a
// progress ring would fight it: two things moving on one edge, neither
// readable.
Item {
    id: root

    implicitWidth: Appearance.sizes.widgetGridSpanX(2)
    implicitHeight: Appearance.sizes.widgetGridSpanY(1)

    readonly property bool useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_media")

    property point resizeBow: Qt.point(0, 0)
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [{
        x: bgCard.x, y: bgCard.y, width: bgCard.width, height: bgCard.height, radius: bgCard.radius
    }]

    readonly property real controlSize: 56 * Appearance.effectiveScale
    readonly property real playSize: 72 * Appearance.effectiveScale
    readonly property real progress: MprisController.length > 0
        ? MprisController.position / MprisController.length : 0

    readonly property color controlColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSecondaryContainer
    readonly property color controlIconColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colTertiaryContainer : Appearance.colors.colOnSecondaryContainer

    // MprisPlayer caches its position and refetches when something asks, so a
    // widget that only reads it draws a ring frozen where the track started.
    // The bar's media widget pokes it on exactly this interval; a desktop widget
    // cannot assume the bar is on screen.
    Timer {
        running: MprisController.isPlaying
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: MprisController.activePlayer?.positionChanged()
    }

    Expressive.WidgetCard {
        id: bgCard
        anchors.fill: parent
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
        tensionX: root.resizeBow.x
        tensionY: root.resizeBow.y
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: Appearance.spacing.space150

        Rectangle {
            id: prevPill
            implicitWidth: root.controlSize
            implicitHeight: root.controlSize
            radius: height / 2
            color: root.controlColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "skip_previous"
                iconSize: 26 * Appearance.effectiveScale
                fill: 0
                color: prevArea.containsMouse ? Appearance.colors.colPrimary : root.controlIconColor
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }

            MouseArea {
                id: prevArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MprisController.previous()
            }
        }

        Item {
            id: playButton
            implicitWidth: root.playSize
            implicitHeight: root.playSize

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
                // The dash starts where the path does, which is wherever the
                // first vertex happens to sit. Turning that point to the top
                // makes progress start at twelve o'clock and travel clockwise;
                // a twelve-lobed cookie is symmetric every 30 degrees, so
                // nothing about the shape reads as rotated.
                readonly property real startRotation: {
                    const cubics = cookieCanvas.polygon.cubics;
                    if (cubics.length === 0)
                        return 0;
                    return -Math.PI / 2 - Math.atan2(cubics[0].anchor0Y - 0.5, cubics[0].anchor0X - 0.5);
                }

                // A Canvas repaints on resize and on nothing else, so every
                // input it reads is mirrored here to be observed. A colour
                // reached only from inside onPaint is the silent half: the
                // ring would keep the old theme's colours until something
                // resized the widget.
                readonly property real progress: root.progress
                readonly property color bodyColor: Appearance.colors.colPrimary
                readonly property color trackColor: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onProgressChanged: requestPaint()
                onBodyColorChanged: requestPaint()
                onTrackColorChanged: requestPaint()

                // Opens a path under the transform that puts the normalized
                // polygon on screen at `diameter`, and leaves the transform in
                // place: the caller fills or strokes, then restores.
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
                    // The ring's outer edge lands on the button's bounds, and
                    // the body clears its inner edge by half a stroke.
                    const ringDiameter = size - stroke;
                    const bodyDiameter = ringDiameter - stroke * 3;

                    trace(ctx, bodyDiameter);
                    ctx.fillStyle = cookieCanvas.bodyColor;
                    ctx.fill();
                    ctx.restore();

                    // The line width is divided by the diameter because the
                    // scale drawing the path scales the pen with it. The dash
                    // pattern is then in multiples of *that* width, which is
                    // Qt's unit for it rather than HTML's path length.
                    trace(ctx, ringDiameter);
                    ctx.lineWidth = stroke / ringDiameter;
                    ctx.setLineDash([]);
                    ctx.strokeStyle = cookieCanvas.trackColor;
                    ctx.stroke();
                    ctx.restore();

                    // Skipped rather than dashed at zero: `[0, total]` is an
                    // honest pattern and a degenerate thing to hand a painter.
                    if (cookieCanvas.progress > 0) {
                        trace(ctx, ringDiameter);
                        ctx.lineWidth = stroke / ringDiameter;
                        ctx.setLineDash(PathLength.dashInPenWidths(
                            cookieCanvas.outlineLength, cookieCanvas.progress, ctx.lineWidth));
                        ctx.strokeStyle = cookieCanvas.bodyColor;
                        ctx.stroke();
                        ctx.setLineDash([]);
                        ctx.restore();
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: 30 * Appearance.effectiveScale
                fill: 0
                color: playArea.pressed
                    ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.7)
                    : Appearance.colors.colOnPrimary
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }

            MouseArea {
                id: playArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MprisController.togglePlaying()
            }
        }

        Rectangle {
            id: nextPill
            implicitWidth: root.controlSize
            implicitHeight: root.controlSize
            radius: height / 2
            color: root.controlColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "skip_next"
                iconSize: 26 * Appearance.effectiveScale
                fill: 0
                color: nextArea.containsMouse ? Appearance.colors.colPrimary : root.controlIconColor
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }

            MouseArea {
                id: nextArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MprisController.next()
            }
        }
    }
}
