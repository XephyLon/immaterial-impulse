import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.functions as Functions
import qs.services
import "."
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "weather_geometry.js" as Geometry
import "weather_glyphs.js" as WeatherGlyphs
import "weather_shapes.js" as WeatherShapes
import "sun_arc.js" as SunArc
import "../../../functions/weatherForecast.js" as WeatherForecast

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
// Unshared content fades - it has nothing to morph into: feels-like at 2x1,
// the high/low line at 3x1, and the day-by-day forecast band at 3x2. The
// column rule and the badge pills live at BOTH wide spans and travel between
// them; only the narrow spans are a fade for those two.
//
// 3x2 is the one span with two rows. It is split into two bands - current
// conditions above, the forecast below - and everything in the top band
// travels into it from 3x1 rather than being redrawn there.
Item {
    id: root

    property var cfg: Config.ready ? Config.options.appearance.weatherWidget : null
    property string sizeMode: cfg ? cfg.sizeMode : "3x1"
    property bool useBlurBackground: false
    property point resizeBow: Qt.point(0, 0)
    // Handled state, for the cards' elevation.
    property bool dragging: false
    // The host's box is animating; the cards drop their shadow for it.
    property bool boxInMotion: false

    property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("", 0.1)
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [card.blurRegion]

    readonly property real baseWidth: 132 * Appearance.effectiveScale
    readonly property real baseHeight: 108 * Appearance.effectiveScale
    readonly property real gap: 12 * Appearance.effectiveScale
    readonly property real width1x1: baseWidth
    readonly property real width2x1: (baseWidth * 2) + gap
    readonly property real width3x1: (baseWidth * 3) + (gap * 2)
    readonly property real height2Rows: (baseHeight * 2) + gap

    implicitHeight: sizeMode === "3x2" ? height2Rows : baseHeight
    implicitWidth: {
        if (sizeMode === "1x1") return width1x1;
        if (sizeMode === "2x1") return width2x1;
        return width3x1;
    }

    // Geometry evaluates at the span's SETTLED box (the media tree's lesson:
    // live-box rects made size snap and are per-frame Behavior targets, the
    // frozen-Behavior shape). Rects change once per span; Behaviors carry.
    // implicitWidth is NOT that box - it animates, so reading it here
    // retargets every rect every frame and a right-edge rect like the glyph's
    // crawls behind the card instead of travelling with it.
    readonly property real spanW: {
        if (sizeMode === "1x1") return width1x1;
        if (sizeMode === "2x1") return width2x1;
        return width3x1;
    }
    readonly property real spanH: {
        if (sizeMode === "3x2") return height2Rows;
        return baseHeight;
    }
    readonly property var tempSlot: Geometry.temperatureRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
    readonly property var conditionSlot: Geometry.conditionRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
    readonly property var glyphSlot: Geometry.glyphRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)

    // The two wide spans are the only ones with a second column, and the
    // elements that live in it (the high/low line, the pills, the column
    // rule) fade at the narrow spans rather than travelling to them. A fade
    // happens WHERE THE ELEMENT STANDS, so they still need somewhere to
    // stand: resolving them against whichever wide layout the card is at or
    // heading for gives them one, while the module keeps returning null for
    // the narrow spans so nothing can mistake that for a home.
    readonly property string bandSpan: root.sizeMode === "3x2" ? "3x2" : "3x1"
    readonly property real bandH: root.bandSpan === "3x2" ? root.height2Rows : root.baseHeight
    readonly property var highLowSlot: Geometry.highLowRect(root.bandSpan, root.width3x1, root.bandH, Appearance.effectiveScale)
    readonly property var pillsSlot: Geometry.pillsRect(root.bandSpan, root.width3x1, root.bandH, Appearance.effectiveScale)
    readonly property var columnRuleSlot: Geometry.columnDividerRect(root.bandSpan, root.width3x1, root.bandH, Appearance.effectiveScale)

    // The forecast band exists at 3x2 and nowhere else, so its rect is its one
    // home and the span test is what decides whether it is drawn - the null
    // the module returns elsewhere is what says "fade", never a rect to travel
    // to.
    readonly property bool showsForecast: Geometry.forecastStripRect(
        root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale) !== null
    readonly property var stripSlot: Geometry.forecastStripRect("3x2", root.width3x1, root.height2Rows, Appearance.effectiveScale)
    readonly property var bandRuleSlot: Geometry.bandDividerRect("3x2", root.width3x1, root.height2Rows, Appearance.effectiveScale)

    // The sun arc has a home at every span but 1x1, where the card is fully
    // occupied and the module returns null (its comment has the numbers). So
    // it fades there, like every other element with nowhere to be - and a fade
    // happens WHERE THE ELEMENT STANDS, so it still needs somewhere to stand.
    // 2x1 is the nearest span that has a home for it, and the three one-row
    // spans share a height, so standing there means the curve holds exactly
    // the shape it is fading out of and comes back on it rather than arriving
    // from somewhere.
    readonly property bool showsSunArc: Geometry.sunArcRect(
        root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale) !== null
    readonly property string arcSpan: root.sizeMode === "1x1" ? "2x1" : root.sizeMode
    readonly property var sunArcSlot: Geometry.sunArcRect(
        root.arcSpan, root.spanW, root.spanH, Appearance.effectiveScale)

    // wttr.in answers with three days, OpenWeatherMap with four, and a failed
    // forecast request with none - all three are real and the row is laid out
    // from whatever arrives (#111 deliberately padded to no fixed count).
    readonly property var forecastDays: Weather.forecast || []
    // Recomputed whenever the forecast is, which is often enough to keep the
    // "Today" label honest: a card mislabelled at midnight would need the
    // desktop to sit untouched across it, and a fetch lands every
    // fetchInterval.
    readonly property string todayIso: {
        Weather.forecast;
        return WeatherForecast.localIsoDate(new Date());
    }

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
    // A weather code means nothing without the provider that reported it:
    // `wCode` is an OpenWeatherMap condition id on `owm` and a World Weather
    // Online code on `wttr`, and this expression used to read both through
    // OWM's ranges. weather_glyphs.js is the split.
    readonly property string weatherIcon: WeatherGlyphs.glyphFor(
        Weather.provider, root.weatherData.wCode, Icons.isNight())


    WidgetCard {
        id: card
        anchors.fill: parent
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
        clipContent: true
        tensionX: root.resizeBow.x
        tensionY: root.resizeBow.y
        dragging: root.dragging
        hostMotionActive: root.boxInMotion

        // ---- the sun's day, across the card's background --------------
        //
        // The currency sparkline's place in the composition, except this line
        // is a claim: the curve is today's daylight, the disc is where the sun
        // is in it. First in the tree, so everything else draws over it.
        //
        // The curve carries on PAST both horizons and dips below them, dimmed.
        // That is what makes the horizon read as a horizon rather than as a
        // baseline the curve happens to rest on - and at 3x2 the horizon is
        // not drawn here at all: it lands exactly on the hairline the card
        // already draws between its two bands, so the divider and the horizon
        // are one line doing both jobs.
        Canvas {
            id: sunArc
            objectName: "weatherSunArc"
            anchors.fill: parent
            // 1x1 has no home for the arc, so it leaves the way anything else
            // in this tree leaves a span it does not live at.
            opacity: root.showsSunArc ? 0.32 : 0
            Behavior on opacity { SpanFade {} }
            visible: opacity > 0
            z: -1

            readonly property real nightMargin: SunArc.NIGHT_MARGIN
            readonly property real tailFlatten: SunArc.TAIL_FLATTEN
            readonly property var window: SunArc.windowFor(sunArc.nightMargin)

            // The horizon and the apex come from the SETTLED span's box, like
            // every other rect in this tree, and travel on their own
            // Behaviors - the card's animating height is not the box.
            property real horizonY: root.sunArcSlot.horizonY
            Behavior on horizonY { SpanTravel {} }
            property real apexRise: root.sunArcSlot.apexRise
            Behavior on apexRise { SpanTravel {} }

            // Local minutes, repainted on the minute rather than per frame:
            // the sun moves about a pixel a minute across a card this wide.
            property int nowMinutes: 0
            function refreshNow() {
                const now = new Date();
                sunArc.nowMinutes = now.getHours() * 60 + now.getMinutes();
            }
            Component.onCompleted: sunArc.refreshNow()
            // The clock is only read while the arc is on screen, so a card
            // that spent the afternoon at 1x1 comes back holding a stale
            // minute until the timer's next tick - up to a minute of the sun
            // sitting where it was an hour ago. The repaint is the same
            // thought for the canvas: every return from 1x1 happens to change
            // the width, which requests one, but that is a property of 1x1
            // being the only span of its width rather than a rule.
            onVisibleChanged: if (visible) { sunArc.refreshNow(); sunArc.requestPaint(); }
            Timer {
                interval: 60000
                repeat: true
                running: sunArc.visible
                onTriggered: sunArc.refreshNow()
            }

            readonly property string sunriseText: Weather.data.sunrise ?? "0"
            readonly property string sunsetText: Weather.data.sunset ?? "0"
            readonly property var sunPosition: SunArc.sunU(
                sunArc.nowMinutes, sunArc.sunriseText, sunArc.sunsetText, sunArc.window)
            readonly property bool daylight: SunArc.isDaylight(
                sunArc.nowMinutes, sunArc.sunriseText, sunArc.sunsetText)
            readonly property color inkColor: root.contentColor

            onNowMinutesChanged: requestPaint()
            onSunriseTextChanged: requestPaint()
            onSunsetTextChanged: requestPaint()
            onInkColorChanged: requestPaint()
            onHorizonYChanged: requestPaint()
            onApexRiseChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);
                if (width < 2 || height < 2) return;

                const step = Math.max(1.5, width / 120);
                const yAt = u => SunArc.curveY(u, sunArc.window,
                    sunArc.horizonY, sunArc.apexRise, sunArc.tailFlatten);

                // Two passes over the same curve, split at the horizon: the
                // daylight stretch at full strength, the night dips faint.
                // Drawn as separate strokes rather than one path with a
                // changing alpha, because a canvas stroke takes one alpha for
                // the whole path it is closing.
                const strokeRange = (from, to, alpha) => {
                    if (to - from < 0.0005) return;
                    ctx.globalAlpha = alpha;
                    ctx.beginPath();
                    let first = true;
                    for (let x = from * width; x <= to * width + 0.001; x += step) {
                        const u = Math.min(to, x / width);
                        const y = yAt(u);
                        first ? ctx.moveTo(u * width, y) : ctx.lineTo(u * width, y);
                        first = false;
                    }
                    const endY = yAt(to);
                    ctx.lineTo(to * width, endY);
                    ctx.stroke();
                };

                ctx.strokeStyle = sunArc.inkColor;
                ctx.lineWidth = 1.5 * Appearance.effectiveScale;
                ctx.lineCap = "round";

                strokeRange(0, sunArc.window.uRise, 0.35);
                strokeRange(sunArc.window.uRise, sunArc.window.uSet, 1);
                strokeRange(sunArc.window.uSet, 1, 0.35);
                ctx.globalAlpha = 1;

            }
        }

        // The sun on the curve, moving along it as the day does.
        //
        // A MaterialSymbol rather than the google-weather `clear_day` asset
        // the card draws its condition from: colorised down to 14px that
        // asset's lobes fall under a pixel and it reads as a plain disc, while
        // the symbol's rays survive. The condition glyph keeps the richer
        // asset because it has 84px to spend.
        //
        // Outside the canvas so it is not repainted with the curve - the curve
        // changes when the card resizes, this changes every minute.
        MaterialSymbol {
            objectName: "weatherSunMarker"
            readonly property real u: sunArc.sunPosition ?? 0
            readonly property real markerSize:
                Math.max(12, Math.min(18, sunArc.height * 0.15)) * Appearance.effectiveScale
            width: markerSize
            height: markerSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            x: sunArc.width * u - width / 2
            y: SunArc.curveY(u, sunArc.window, sunArc.horizonY,
                sunArc.apexRise, sunArc.tailFlatten) - height / 2
            Behavior on x { SpanTravel {} }
            Behavior on y { SpanTravel {} }
            // Below its own horizon it is not the sun that is showing.
            text: sunArc.daylight ? "sunny" : "bedtime"
            iconSize: markerSize
            fill: 1
            color: root.contentColor
            // Brighter than the curve it rides - it is the one part of this
            // background that is a reading rather than a frame.
            //
            // Two separate reasons to be invisible, and they must stay
            // separate: an unknown sunrise ("0" from either provider) hides
            // the marker while the curve stays, and 1x1 takes both away.
            opacity: sunArc.sunPosition === null ? 0
                : root.showsSunArc ? 0.8 : 0
            Behavior on opacity { SpanFade {} }
            visible: opacity > 0 && sunArc.visible
            z: -1
        }

        // ---- shared: the glyph container, one shape-parameterised canvas --
        Item {
            id: glyph
            objectName: "weatherGlyph"
            x: root.glyphSlot.x
            y: root.glyphSlot.y
            width: root.glyphSlot.width
            height: root.glyphSlot.height
            rotation: root.glyphSlot.rotation
            Behavior on x { SpanTravel {} }
            Behavior on y { SpanTravel {} }
            Behavior on width { SpanTravel {} }
            Behavior on height { SpanTravel {} }
            Behavior on rotation { SpanTravel {} }

            Canvas {
                id: glyphCanvas
                anchors.fill: parent

                // The morph: on every span change the previous shape becomes
                // the start and morphT runs 0 -> 1 (the ShapeCanvas idiom).
                property string shownShape: root.glyphSlot.shape
                property string fromShape: root.glyphSlot.shape
                property real morphT: 1
                Behavior on morphT { id: morphGate; SpanTravel {} }
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
                Behavior on width { SpanTravel {} }
                Behavior on height { SpanTravel {} }
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
            Behavior on x { SpanTravel {} }
            Behavior on y { SpanTravel {} }
            text: root.temperature + "°"
            font.pixelSize: Math.round(root.tempSlot.size)
            Behavior on font.pixelSize { SpanTravel {} }
            font.weight: Font.Bold
            color: Appearance.colors.colPrimary
        }

        // ---- shared: condition --------------------------------------------
        StyledText {
            objectName: "weatherCondition"
            x: root.conditionSlot.x
            y: root.conditionSlot.y
            width: root.conditionSlot.w
            Behavior on x { SpanTravel {} }
            Behavior on y { SpanTravel {} }
            Behavior on width { SpanTravel {} }
            text: root.condition
            // The size and weight are part of the element's travel - snapped,
            // the same text visibly becomes a different text at the boundary.
            font.pixelSize: root.sizeMode === "1x1" ? Appearance.font.pixelSize.smallest
                : root.sizeMode === "2x1" ? Appearance.font.pixelSize.normal
                : Appearance.font.pixelSize.large
            Behavior on font.pixelSize { SpanTravel {} }
            font.weight: root.sizeMode === "1x1" ? Font.Medium : Font.DemiBold
            Behavior on font.weight { SpanTravel {} }
            color: root.contentColor
            opacity: root.sizeMode === "1x1" ? 0.8 : 1
            Behavior on opacity { SpanFade {} }
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
            Behavior on opacity { SpanFade {} }
            visible: opacity > 0
        }

        StyledText {
            // 3x1 always, and 3x2 only while there is no forecast to draw.
            // The strip opens on today's card, which carries this same range
            // and says it better - but the forecast is a request that can fail
            // on its own (OpenWeatherMap fetches it separately), and a 3x2 card
            // answering that by silently dropping the high and low would tell
            // the user LESS than the 3x1 does.
            objectName: "weatherHighLow"
            x: root.highLowSlot.x
            y: root.highLowSlot.y
            Behavior on x { SpanTravel {} }
            Behavior on y { SpanTravel {} }
            text: `High ${root.highTemperature}° · Low ${root.lowTemperature}°`
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.contentColor
            opacity: (root.sizeMode === "3x1"
                || (root.showsForecast && root.forecastDays.length === 0)) ? 0.6 : 0
            Behavior on opacity { SpanFade {} }
            visible: opacity > 0
        }

        Rectangle {
            // 3x1 and 3x2: the boundary between the temperature column and the
            // condition column, which both wide spans have.
            objectName: "weatherColumnRule"
            x: root.columnRuleSlot.x
            y: root.columnRuleSlot.y
            width: 1
            height: root.columnRuleSlot.height
            Behavior on y { SpanTravel {} }
            Behavior on height { SpanTravel {} }
            color: root.contentColor
            opacity: root.sizeMode === "3x1" || root.sizeMode === "3x2" ? 0.15 : 0
            Behavior on opacity { SpanFade {} }
            visible: opacity > 0
        }

        RowLayout {
            // 3x1 and 3x2: the humidity and wind pills
            objectName: "weatherPills"
            x: root.pillsSlot.x
            y: root.pillsSlot.y
            Behavior on y { SpanTravel {} }
            spacing: 8 * Appearance.effectiveScale
            opacity: root.sizeMode === "3x1" || root.sizeMode === "3x2" ? 1 : 0
            Behavior on opacity { SpanFade {} }
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

        Rectangle {
            // 3x2 only: the seam between the two bands
            objectName: "weatherBandRule"
            x: root.bandRuleSlot.x
            y: root.bandRuleSlot.y
            width: root.bandRuleSlot.width
            height: 1
            color: root.contentColor
            opacity: root.showsForecast && root.forecastDays.length > 0 ? 0.15 : 0
            Behavior on opacity { SpanFade {} }
            visible: opacity > 0
        }

        // ---- unshared: the second row's day-by-day forecast ---------------
        //
        // 3x2 only, so it fades rather than travelling - and unlike the other
        // fades in this tree it is worth UNLOADING as well as hiding. Each
        // card holds a CustomIcon, and an invisible-but-alive strip is four
        // SVG loads and a dozen bindings kept warm for three spans that never
        // show them (spec 2026-08-11, §6: in a reflowing tree, unloaded beats
        // invisible-but-alive wherever the element has no home).
        //
        // The unload waits for the fade to land rather than following the
        // span, because removing a delegate destroys it in the same frame and
        // an exit transition is impossible after that - the rule the desktop
        // plugin loaders already follow.
        Item {
            id: forecastStrip
            objectName: "weatherForecast"
            x: root.stripSlot.x
            y: root.stripSlot.y
            width: root.stripSlot.width
            height: root.stripSlot.height
            opacity: root.showsForecast && root.forecastDays.length > 0 ? 1 : 0
            Behavior on opacity { SpanFade {} }
            visible: opacity > 0

            Repeater {
                model: root.showsForecast || forecastStrip.opacity > 0 ? root.forecastDays : []

                Item {
                    id: dayCard
                    required property int index
                    required property var modelData

                    readonly property var slot: Geometry.forecastCardRect(
                        dayCard.index, root.forecastDays.length,
                        forecastStrip.width, forecastStrip.height, Appearance.effectiveScale)
                    x: dayCard.slot ? dayCard.slot.x : 0
                    width: dayCard.slot ? dayCard.slot.width : 0
                    height: forecastStrip.height

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small * Appearance.effectiveScale
                        // The pills' tint, because these are the same kind of
                        // object one band up: a small tonal container holding
                        // one reading. A MaterialShape here would put four more
                        // morphing outlines under the one the card already has.
                        color: Appearance.m3colors.darkmode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2 * Appearance.effectiveScale

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            // Plain English, like the "Feels like" and "High"
                            // one band up: nothing in the vendored design
                            // system reaches for the translation singleton,
                            // and one word is not the place to start.
                            text: WeatherForecast.isToday(dayCard.modelData.date, root.todayIso)
                                ? "Today" : WeatherForecast.shortDayName(dayCard.modelData.date, Qt.locale())
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.contentColor
                            opacity: 0.8
                        }

                        CustomIcon {
                            Layout.alignment: Qt.AlignHCenter
                            // The day icon, never the night variant: this card
                            // is a claim about Thursday, not about tonight's
                            // sky, and after 20:00 every one of them would
                            // otherwise flip.
                            source: WeatherGlyphs.glyphFor(Weather.provider, dayCard.modelData.wCode, false)
                            iconFolder: root.weatherIconsDir
                            width: 26 * Appearance.effectiveScale
                            height: 26 * Appearance.effectiveScale
                            colorize: true
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4 * Appearance.effectiveScale

                            StyledText {
                                // An absent reading is not 0° - the service
                                // keeps it null and the card says so.
                                text: dayCard.modelData.high === null ? "—" : `${dayCard.modelData.high}°`
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: root.contentColor
                            }
                            StyledText {
                                text: dayCard.modelData.low === null ? "—" : `${dayCard.modelData.low}°`
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.contentColor
                                opacity: 0.6
                            }
                        }
                    }
                }
            }
        }
    }
}
