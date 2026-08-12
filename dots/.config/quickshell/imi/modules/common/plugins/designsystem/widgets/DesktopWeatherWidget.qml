import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.functions as Functions
import qs.services
import "."
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "weather_geometry.js" as Geometry
import "weather_shapes.js" as WeatherShapes

// The weather widget as ONE tree (spec 2026-08-11, §3b - this widget is the
// element the morphing design was specified around).
//
// It used to be a Loader over three inline Components, so a span change
// destroyed one layout and constructed another: the temperature at 3x1 and
// the temperature at 1x1 were different objects, and the glyph's container
// was three different TYPES - a Ghostish MaterialShape, a radius-30 panel and
// a radius-16 leaf. Now the shared three - temperature, condition, the glyph
// container - are declared once and travel; the container is one canvas whose
// shape is a parameter, morphing Ghostish -> panel -> leaf through
// weather_shapes.js. The card's content clip is what cuts the leaf at the
// corner, which is the half the spec called unsolved before the card owned
// clipping.
//
// Unshared content (feels-like at 2x1; high/low, the divider and the badge
// pills at 3x1) fades and scales - it has nothing to morph into.
Item {
    id: root

    property var cfg: Config.ready ? Config.options.appearance.weatherWidget : null
    property string sizeMode: cfg ? cfg.sizeMode : "3x1"
    property bool useBlurBackground: false
    property point resizeBow: Qt.point(0, 0)

    property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("", 0.1)
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [card.blurRegion]

    readonly property real baseWidth: 132 * Appearance.effectiveScale
    readonly property real baseHeight: 108 * Appearance.effectiveScale
    readonly property real gap: 12 * Appearance.effectiveScale
    readonly property real width1x1: baseWidth
    readonly property real width2x1: (baseWidth * 2) + gap
    readonly property real width3x1: (baseWidth * 3) + (gap * 2)

    implicitHeight: baseHeight
    implicitWidth: {
        if (sizeMode === "1x1") return width1x1;
        if (sizeMode === "2x1") return width2x1;
        return width3x1;
    }

    // Geometry evaluates at the span's SETTLED box (the media tree's lesson:
    // live-box rects made size snap and are per-frame Behavior targets, the
    // frozen-Behavior shape). Rects change once per span; Behaviors carry.
    readonly property real spanW: root.implicitWidth
    readonly property real spanH: root.baseHeight
    readonly property var tempSlot: Geometry.temperatureRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
    readonly property var conditionSlot: Geometry.conditionRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
    readonly property var glyphSlot: Geometry.glyphRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)

    readonly property string weatherIconsDir: "../../../../assets/icons/google-weather"
    readonly property color contentColor: Appearance.m3colors.m3onSurface
    readonly property var weatherData: Weather.data || ({})
    readonly property string temperature: (weatherData.temp || "--").replace(/[^0-9+\-.]/g, "")
    readonly property string feelsLike: (weatherData.tempFeelsLike || "--").replace(/[^0-9+\-.]/g, "")
    readonly property string highTemperature: (weatherData.tempHigh || "--").replace(/[^0-9+\-.]/g, "")
    readonly property string lowTemperature: (weatherData.tempLow || "--").replace(/[^0-9+\-.]/g, "")
    readonly property string condition: weatherData.description || "Unknown"
    readonly property string humidity: weatherData.humidity || "--"
    readonly property string wind: weatherData.wind || "--"
    readonly property string weatherIcon: {
        const code = Number(weatherData.wCode || 0)
        if (code === 800) return Icons.isNight() ? "clear_night" : "clear_day"
        if (code === 801) return Icons.isNight() ? "partly_cloudy_night" : "partly_cloudy_day"
        if (code >= 200 && code < 300) return "strong_thunderstorms"
        if (code >= 300 && code < 600) return "heavy_rain"
        if (code >= 600 && code < 700) return "heavy_snow"
        if (code >= 700 && code < 800) return "haze_fog_dust_smoke"
        return "cloudy"
    }

    component TravelBehavior: NumberAnimation {
        duration: Appearance.animation.elementMove.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
    }
    component FadeBehavior: NumberAnimation {
        duration: Appearance.animation.elementMove.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
        clipContent: true
        tensionX: root.resizeBow.x
        tensionY: root.resizeBow.y

        // ---- shared: the glyph container, one shape-parameterised canvas --
        Item {
            id: glyph
            objectName: "weatherGlyph"
            x: root.glyphSlot.x
            y: root.glyphSlot.y
            width: root.glyphSlot.width
            height: root.glyphSlot.height
            rotation: root.glyphSlot.rotation
            Behavior on x { TravelBehavior {} }
            Behavior on y { TravelBehavior {} }
            Behavior on width { TravelBehavior {} }
            Behavior on height { TravelBehavior {} }
            Behavior on rotation { TravelBehavior {} }

            Canvas {
                id: glyphCanvas
                anchors.fill: parent

                // The morph: on every span change the previous shape becomes
                // the start and morphT runs 0 -> 1 (the ShapeCanvas idiom).
                property string shownShape: root.glyphSlot.shape
                property string fromShape: root.glyphSlot.shape
                property real morphT: 1
                Behavior on morphT { id: morphGate; TravelBehavior {} }
                readonly property string targetShape: root.glyphSlot.shape
                onTargetShapeChanged: {
                    glyphCanvas.fromShape = glyphCanvas.shownShape;
                    glyphCanvas.shownShape = glyphCanvas.targetShape;
                    // The gate is the whole trick (ShapeCanvas's own idiom,
                    // cited and then not copied): written through a live
                    // Behavior, `morphT = 0` RETARGETS the animation toward 0
                    // instead of resetting, the immediate `= 1` retargets it
                    // back from wherever it got, and the shape flips at
                    // nearly full morphT - a snap wearing a morph's clothes.
                    morphGate.enabled = false;
                    morphT = 0;
                    morphGate.enabled = true;
                    morphT = 1;
                }
                readonly property color fillColor: Appearance.colors.colPrimary

                onMorphTChanged: requestPaint()
                onFillColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const shape = WeatherShapes.containerAt(
                        glyphCanvas.fromShape, glyphCanvas.shownShape, glyphCanvas.morphT);
                    if (shape.cubics.length === 0) return;
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
                    ctx.fillStyle = glyphCanvas.fillColor;
                    ctx.fill();
                    ctx.restore();
                }
            }

            CustomIcon {
                anchors.centerIn: parent
                source: root.weatherIcon
                iconFolder: root.weatherIconsDir
                width: root.glyphSlot.icon
                height: root.glyphSlot.icon
                Behavior on width { TravelBehavior {} }
                Behavior on height { TravelBehavior {} }
                colorize: true
                color: Appearance.colors.colOnPrimary
                // The leaf slants; the glyph inside stays upright.
                rotation: -glyph.rotation
            }
        }

        // ---- shared: temperature ------------------------------------------
        StyledText {
            objectName: "weatherTemp"
            x: root.tempSlot.x
            y: root.tempSlot.y
            Behavior on x { TravelBehavior {} }
            Behavior on y { TravelBehavior {} }
            text: root.temperature + "°"
            font.pixelSize: Math.round(root.tempSlot.size)
            Behavior on font.pixelSize { TravelBehavior {} }
            font.weight: Font.Bold
            color: Appearance.colors.colPrimary
        }

        // ---- shared: condition --------------------------------------------
        StyledText {
            objectName: "weatherCondition"
            x: root.conditionSlot.x
            y: root.conditionSlot.y
            width: root.conditionSlot.w
            Behavior on x { TravelBehavior {} }
            Behavior on y { TravelBehavior {} }
            Behavior on width { TravelBehavior {} }
            text: root.condition
            // The size and weight are part of the element's travel - snapped,
            // the same text visibly becomes a different text at the boundary.
            font.pixelSize: root.sizeMode === "1x1" ? Appearance.font.pixelSize.smallest
                : root.sizeMode === "2x1" ? Appearance.font.pixelSize.normal
                : Appearance.font.pixelSize.large
            Behavior on font.pixelSize { TravelBehavior {} }
            font.weight: root.sizeMode === "1x1" ? Font.Medium : Font.DemiBold
            Behavior on font.weight { TravelBehavior {} }
            color: root.contentColor
            opacity: root.sizeMode === "1x1" ? 0.8 : 1
            Behavior on opacity { FadeBehavior {} }
            elide: root.sizeMode === "1x1" ? Text.ElideNone : Text.ElideRight
            wrapMode: root.sizeMode === "1x1" ? Text.WordWrap : Text.NoWrap
            maximumLineCount: root.sizeMode === "1x1" ? 2 : 1
        }

        // ---- unshared: enters and exits -----------------------------------
        StyledText {
            // 2x1 only
            x: 20 * Appearance.effectiveScale
            y: 84 * Appearance.effectiveScale
            text: `Feels like ${root.feelsLike}°`
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.contentColor
            opacity: root.sizeMode === "2x1" ? 0.6 : 0
            Behavior on opacity { FadeBehavior {} }
            visible: opacity > 0
        }

        StyledText {
            // 3x1 only
            x: 20 * Appearance.effectiveScale
            y: 74 * Appearance.effectiveScale
            text: `High ${root.highTemperature}° · Low ${root.lowTemperature}°`
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.contentColor
            opacity: root.sizeMode === "3x1" ? 0.6 : 0
            Behavior on opacity { FadeBehavior {} }
            visible: opacity > 0
        }

        Rectangle {
            // 3x1 only: the column divider
            x: 132 * Appearance.effectiveScale
            y: 16 * Appearance.effectiveScale
            width: 1
            height: root.spanH - 32 * Appearance.effectiveScale
            color: root.contentColor
            opacity: root.sizeMode === "3x1" ? 0.15 : 0
            Behavior on opacity { FadeBehavior {} }
            visible: opacity > 0
        }

        RowLayout {
            // 3x1 only: the humidity and wind pills
            x: 148 * Appearance.effectiveScale
            y: 60 * Appearance.effectiveScale
            spacing: 8 * Appearance.effectiveScale
            opacity: root.sizeMode === "3x1" ? 1 : 0
            Behavior on opacity { FadeBehavior {} }
            visible: opacity > 0

            Repeater {
                model: [
                    { icon: "humidity_mid", value: root.humidity },
                    { icon: "air", value: root.wind }
                ]
                Rectangle {
                    required property var modelData
                    Layout.preferredHeight: 22 * Appearance.effectiveScale
                    implicitWidth: pillRow.implicitWidth + (16 * Appearance.effectiveScale)
                    radius: 11 * Appearance.effectiveScale
                    color: Appearance.m3colors.darkmode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                    RowLayout {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 4 * Appearance.effectiveScale
                        MaterialSymbol {
                            iconSize: 14 * Appearance.effectiveScale
                            text: parent.parent.modelData.icon
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: parent.parent.modelData.value
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: root.contentColor
                        }
                    }
                }
            }
        }
    }
}
