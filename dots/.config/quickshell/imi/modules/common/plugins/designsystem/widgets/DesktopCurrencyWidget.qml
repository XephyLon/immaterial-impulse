import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.functions as Functions
import qs.services
import "../services"
import "../services/CurrencyMath.js" as CurrencyMath
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "."
import "currency_geometry.js" as Geometry
import "currency_shapes.js" as CurrencyShapes
import "../services/currency_history.js" as History
import "../services/currency_daily.js" as Daily

Item {
    id: root
    
    property var cfg: Config.ready ? Config.options.appearance.currencyWidget : null
    property string sizeMode: cfg ? cfg.sizeMode : "2x1"
    property bool useBlurBackground: false
    property point resizeBow: Qt.point(0, 0)
    // Handled state, for the cards' elevation.
    property bool dragging: false
    // The host's box is animating; the cards drop their shadow for it.
    property bool boxInMotion: false
    // The host wrapper overrides this with its own plugin id; the fallback keeps
    // the toggle honoured for a component instantiated without one.

    property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("", 0.1)
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [card.blurRegion]
    signal baseCurrencyRequested(string value)
    signal quoteCurrencyRequested(int index, string value)

    HoverHandler {
        id: widgetHoverHandler
    }

    readonly property real baseWidth: 132 * Appearance.effectiveScale
    readonly property real baseHeight: 108 * Appearance.effectiveScale
    readonly property real gap: 12 * Appearance.effectiveScale

    readonly property real width1x1: baseWidth
    readonly property real width2x1: (baseWidth * 2) + gap
    readonly property real width3x1: (baseWidth * 3) + gap * 2
    readonly property real height2: (baseHeight * 2) + gap

    implicitHeight: sizeMode === "3x2" ? height2 : baseHeight
    implicitWidth: {
        if (sizeMode === "1x1") return width1x1;
        if (sizeMode === "3x1" || sizeMode === "3x2") return width3x1;
        return width2x1;
    }

    // Geometry evaluates at the span's SETTLED box; Behaviors carry the
    // travel (the media tree's frozen-Behavior lesson). Reading implicitWidth
    // here instead would retarget every element every frame, and elements
    // whose x depends on the right edge - the panel, its cells - would crawl
    // behind the card instead of travelling with it.
    readonly property real spanW: root.sizeMode === "1x1" ? root.width1x1
        : root.sizeMode === "3x1" || root.sizeMode === "3x2" ? root.width3x1 : root.width2x1
    readonly property real spanH: root.sizeMode === "3x2" ? root.height2 : root.baseHeight

    // The clock the 24h readings tick against: the movement columns, the
    // chart's x axis and the refresh stamp all age even when no new sample
    // arrives. A minute is plenty for all three.
    property double nowTick: Date.now()
    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.nowTick = Date.now()
    }
    // { pct, abs, direction } per quote. Day-over-day from the daily
    // closes first - the same data the trend charts read, so the arrow and
    // the chart cannot disagree. The 24h observed fold is the fallback for
    // a cold daily store, and null hides the column entirely.
    function movementFor(code) {
        const daily = Daily.changeFrom(CurrencyService.daily, code, root.nowTick);
        if (daily !== null) return daily;
        const current = CurrencyService.rates[code];
        if (current === undefined) return null;
        return History.changeOf(CurrencyService.history, code, root.nowTick, current);
    }
    function signedPct(change) {
        return (change.pct >= 0 ? "+" : "") + change.pct.toFixed(2) + "%";
    }
    function signedAbs(change) {
        // A zero delta is three quiet decimals, not six trailing zeros.
        const digits = change.abs === 0 ? 3
            : Math.min(6, CurrencyMath.fractionDigits(Math.abs(change.abs)) + 1);
        return "(" + (change.abs >= 0 ? "+" : "") + change.abs.toFixed(digits) + ")";
    }
    // The base currency's flag, from the ISO code's country half. EUR's
    // "EU" is a real regional-indicator pair; a code with no letters there
    // yields nothing and the element hides.
    // One painter for every trend chart: the smoothed line, optionally a
    // soft fill down to the baseline (the 3x2's look). Points are unit-box.
    function drawTrend(ctx, w, h, points, strokeColor, fill) {
        if (!points || points.length < 2) {
            // The honest-quiet placeholder: a flat baseline, not a fake curve.
            ctx.strokeStyle = Functions.ColorUtils.applyAlpha(strokeColor, 0.35);
            ctx.lineWidth = 2 * Appearance.effectiveScale;
            ctx.beginPath();
            ctx.moveTo(0, h - 2);
            ctx.lineTo(w, h - 2);
            ctx.stroke();
            return;
        }
        const pts = points.map(p => ({ x: p.x * w, y: (0.08 + p.y * 0.8) * h }));
        ctx.lineWidth = 2 * Appearance.effectiveScale;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) {
            const mid = (pts[i].x - pts[i - 1].x) / 2;
            ctx.bezierCurveTo(pts[i - 1].x + mid, pts[i - 1].y,
                pts[i].x - mid, pts[i].y, pts[i].x, pts[i].y);
        }
        if (fill) {
            ctx.save();
            ctx.lineTo(pts[pts.length - 1].x, h);
            ctx.lineTo(pts[0].x, h);
            ctx.closePath();
            ctx.fillStyle = Functions.ColorUtils.applyAlpha(strokeColor, 0.18);
            ctx.fill();
            ctx.restore();
            ctx.beginPath();
            ctx.moveTo(pts[0].x, pts[0].y);
            for (let i = 1; i < pts.length; i++) {
                const mid = (pts[i].x - pts[i - 1].x) / 2;
                ctx.bezierCurveTo(pts[i - 1].x + mid, pts[i - 1].y,
                    pts[i].x - mid, pts[i].y, pts[i].x, pts[i].y);
            }
        }
        ctx.strokeStyle = strokeColor;
        ctx.stroke();
    }

    function flagEmoji(code) {
        const letters = String(code || "").toUpperCase().slice(0, 2);
        if (!/^[A-Z]{2}$/.test(letters)) return "";
        return String.fromCodePoint(...[...letters].map(c => 0x1F1E6 + c.charCodeAt(0) - 65));
    }





    property bool showingSettings: false
    
    // Flip Card scale and animation
    transform: Scale {
        id: flipScale
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: 1
    }

    SequentialAnimation {
        id: flipAnim
        NumberAnimation {
            target: flipScale; property: "xScale"
            to: 0; duration: 150; easing.type: Easing.InQuad
        }
        ScriptAction {
            script: root.showingSettings = !root.showingSettings
        }
        NumberAnimation {
            target: flipScale; property: "xScale"
            to: 1; duration: 150; easing.type: Easing.OutQuad
        }
    }

    function toggleFlip() { flipAnim.start() }

    function formatRate(value) {
        return Number(value).toLocaleString(
            Qt.locale(), "f", CurrencyMath.fractionDigits(value));
    }

    // The shared card, on the currency tint.
    WidgetCard {
        id: card
        objectName: "nandoroidCurrencyCard"
        anchors.fill: parent
        // The card's own default tint - the darker surface the weather card
        // sits on (the maintainer: "use the darker background color... same
        // one used for weather"). The container-colour override this carried
        // was the one thing separating the two cards.
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
        tensionX: root.resizeBow.x
        tensionY: root.resizeBow.y
        dragging: root.dragging
        hostMotionActive: root.boxInMotion

        // --- PAGE 1: View Mode ---
        Item {
            anchors.fill: parent
            visible: !root.showingSettings

            // Settings button (appears on hover, hidden when locked)
            Item {
                width: 24 * Appearance.effectiveScale
                height: 24 * Appearance.effectiveScale
                z: 100
                visible: cfg ? !cfg.locked : true
                opacity: widgetHoverHandler.hovered ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 8 * Appearance.effectiveScale
                    rightMargin: 8 * Appearance.effectiveScale
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 12 * Appearance.effectiveScale
                    color: Appearance.colors.colPrimary
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "settings"
                        iconSize: 14 * Appearance.effectiveScale
                        color: Appearance.colors.colOnPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleFlip()
                    }
                }
            }

            // ---- one tree (spec 2026-08-11): the container, the labels and
            // the first two quote cells are single elements that travel;
            // quotes 3-4 and the sparkline belong to 2x1 alone and fade.
            // The container is the weather glyph's pattern, third adopter:
            // one canvas whose shape is a parameter, Bun at 1x1 morphing
            // into the full-height panel at 2x1.

            // The chart line - the 2x1's card-wide backdrop and the 3x1's
            // hero chart are ONE element in two homes. It draws the day the
            // shell actually observed (currency_history.js: one sample per
            // successful refresh, of the base against the first quote); the
            // decorative curve it shipped with survives only as the
            // placeholder while the history is younger than two samples.
            Canvas {
                id: sparklineCanvas
                readonly property var slot: Geometry.chartRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                x: slot ? slot.x : 0
                y: slot ? slot.y : 0
                width: slot ? slot.width : root.spanW
                height: slot ? slot.height : root.spanH
                Behavior on x { SpanTravel {} }
                Behavior on y { SpanTravel {} }
                Behavior on width { SpanTravel {} }
                Behavior on height { SpanTravel {} }
                opacity: root.sizeMode === "2x1" ? 0.35
                    : (root.sizeMode === "3x1" || root.sizeMode === "3x2") ? 0.6 : 0
                Behavior on opacity { SpanFade {} }
                visible: opacity > 0
                // The fetched week first (the maintainer's rule: the curve
                // is only decorative when there is no 7-day data), then the
                // observed 24h ring, then the ornament.
                readonly property var series: {
                    const week = Daily.trendFor(CurrencyService.daily,
                        CurrencyService.quote1, root.nowTick, 7).points;
                    if (week.length >= 2) return week;
                    return History.seriesFor(
                        CurrencyService.history, CurrencyService.quote1, root.nowTick);
                }
                onSeriesChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                // A requestPaint before the canvas is available is dropped
                // silently - the geometry and data settle during creation,
                // so without this the first REAL paint never comes and the
                // line simply is not there (the play-button canvas records
                // the same lesson).
                onAvailableChanged: if (available) requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = Appearance.colors.colOnPrimaryContainer;
                    ctx.lineWidth = 2 * Appearance.effectiveScale;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    // Normalised points: measured when there is a day to
                    // show, the authored curve until then.
                    let points = sparklineCanvas.series.length >= 2
                        ? sparklineCanvas.series.map(p => ({ x: p.x, y: 0.15 + p.y * 0.7 }))
                        : [0.8, 0.6, 0.75, 0.4, 0.55, 0.3, 0.45, 0.2].map(
                            (y, i, all) => ({ x: i / (all.length - 1), y: y }));
                    ctx.moveTo(points[0].x * width, points[0].y * height);
                    for (let i = 1; i < points.length; i++) {
                        let x = points[i].x * width;
                        let y = points[i].y * height;
                        let prevX = points[i - 1].x * width;
                        let prevY = points[i - 1].y * height;
                        let mid = (x - prevX) / 2;
                        ctx.bezierCurveTo(prevX + mid, prevY, x - mid, y, x, y);
                    }
                    ctx.stroke();
                }
            }

            // ---- shared: the container (Bun <-> panel) --------------------
            Item {
                id: container
                objectName: "currencyContainer"
                readonly property var slot: Geometry.containerRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                x: slot.x
                y: slot.y
                width: slot.width
                height: slot.height
                Behavior on x { SpanTravel {} }
                Behavior on y { SpanTravel {} }
                Behavior on width { SpanTravel {} }
                Behavior on height { SpanTravel {} }

                Canvas {
                    id: containerCanvas
                    anchors.fill: parent
                    property string shownShape: container.slot.shape
                    property string fromShape: container.slot.shape
                    property real morphT: 1
                    Behavior on morphT { id: morphGate; SpanTravel {} }
                    readonly property string targetShape: container.slot.shape
                    onTargetShapeChanged: {
                        containerCanvas.fromShape = containerCanvas.shownShape;
                        containerCanvas.shownShape = containerCanvas.targetShape;
                        // Through a CLOSED gate - written through the live
                        // Behavior, a reset retargets instead (the weather
                        // glyph shipped that snap).
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
                        const shape = CurrencyShapes.containerAt(
                            containerCanvas.fromShape, containerCanvas.shownShape, containerCanvas.morphT);
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
                        ctx.fillStyle = containerCanvas.fillColor;
                        ctx.fill();
                        ctx.restore();
                    }
                }

                // The payments badge glyph: on both badge-shaped homes (the
                // 1x1 Bun, the 3x1 chip), fading while the container is the
                // data panel.
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "payments"
                    iconSize: (root.sizeMode === "1x1" ? 18 : 14) * Appearance.effectiveScale
                    color: Appearance.colors.colOnPrimary
                    opacity: root.sizeMode !== "2x1" ? 1 : 0
                    Behavior on opacity { SpanFade {} }
                    visible: opacity > 0
                }
            }

            // ---- shared: "Rates" ------------------------------------------
            StyledText {
                objectName: "currencyRatesLabel"
                readonly property var slot: Geometry.ratesLabelRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                x: slot.x
                y: slot.y
                Behavior on x { SpanTravel {} }
                Behavior on y { SpanTravel {} }
                text: "Rates"
                font.pixelSize: root.sizeMode === "1x1" ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
                Behavior on font.pixelSize { SpanTravel {} }
                font.weight: root.sizeMode === "1x1" ? Font.DemiBold : Font.Bold
                Behavior on font.weight { SpanTravel {} }
                color: Appearance.colors.colOnPrimaryContainer
                opacity: root.sizeMode === "1x1" ? 0.6 : 0.8
                Behavior on opacity { SpanFade {} }
            }

            // ---- 1x1 only: the word "to" ----------------------------------
            // Its own element, because swapping the text of the code below
            // ("to USD" to "USD") would be a content snap in the middle of
            // the morph - exactly what this architecture exists to kill.
            StyledText {
                id: basePrefix
                objectName: "currencyBasePrefix"
                readonly property var slot: Geometry.basePrefixRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                // The last settled slot, HELD rather than read back off the
                // item. `slot ?? ({ ..., size: font.pixelSize })` looks like
                // the same thing, but while the slot is null the fallback
                // reads the very property it feeds - QML reported the loop on
                // font.pixelSize. Holding the values means the element still
                // fades out from exactly where it was, without asking itself
                // where that is.
                property real heldX: 0
                property real heldY: 0
                property real heldSize: font.pixelSize
                onSlotChanged: if (slot !== null) {
                    heldX = slot.x;
                    heldY = slot.y;
                    heldSize = slot.size;
                }
                readonly property var lastSlot: slot ?? ({ x: heldX, y: heldY, size: heldSize })
                x: lastSlot.x
                y: lastSlot.y
                Behavior on x { SpanTravel {} }
                Behavior on y { SpanTravel {} }
                text: "to"
                // It keeps its small size while it fades, so the growing code
                // beside it does not drag it up in scale on the way out.
                font.pixelSize: Math.round(lastSlot.size)
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                opacity: slot !== null ? 1 : 0
                // Quicker than the shared fade: "Rates" travels down onto this
                // line on the way to 2x1, and the two must not be legible on
                // top of each other while it passes.
                Behavior on opacity {
                    NumberAnimation {
                        duration: Math.round(Appearance.animation.elementMove.duration * 0.45)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    }
                }
                visible: opacity > 0
            }

            // ---- shared: the base currency --------------------------------
            StyledText {
                id: baseCode
                objectName: "currencyBase"
                readonly property var slot: Geometry.baseLabelRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                // The group's left edge travels; the code then sits after
                // whatever width the fading prefix still occupies, so it
                // slides into that space instead of jumping when it vanishes.
                property real groupX: slot.x
                Behavior on groupX { SpanTravel {} }
                x: groupX + (basePrefix.paintedWidth + 3 * Appearance.effectiveScale) * basePrefix.opacity
                y: slot.y
                Behavior on y { SpanTravel {} }
                text: CurrencyService.baseCurrency
                font.pixelSize: Math.round(slot.size)
                Behavior on font.pixelSize { SpanTravel {} }
                font.weight: Font.Bold
                color: root.sizeMode === "1x1" ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimaryContainer
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
            }

            // ---- 3x1 only: the flag, the dividers, the refresh stamp ------
            StyledText {
                readonly property var slot: Geometry.flagRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                readonly property string flag: root.flagEmoji(CurrencyService.baseCurrency)
                visible: opacity > 0 && flag !== ""
                opacity: slot !== null ? 1 : 0
                Behavior on opacity { SpanFade {} }
                // Riding the code's own painted end, superscript - the
                // geometry slot guessed a fixed x and floated the flag into
                // the divider when the code ran shorter ("mispositioned").
                x: baseCode.x + baseCode.paintedWidth + 4 * Appearance.effectiveScale
                y: baseCode.y + 2 * Appearance.effectiveScale
                text: flag
                font.pixelSize: Math.round((slot ? slot.size : 16) * 1.0)
            }
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    readonly property var slot: Geometry.dividerRect(index, root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                    visible: opacity > 0
                    opacity: slot !== null ? 0.18 : 0
                    Behavior on opacity { SpanFade {} }
                    x: slot ? slot.x : 0
                    y: slot ? slot.y : 0
                    width: slot ? slot.width : 1
                    height: slot ? slot.height : 0
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            StyledText {
                readonly property var slot: Geometry.updatedRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                readonly property string stamp: History.agoLabel(root.nowTick, CurrencyService.lastSuccessTime)
                visible: opacity > 0 && stamp !== ""
                opacity: slot !== null ? 0.6 : 0
                Behavior on opacity { SpanFade {} }
                x: slot ? slot.x : 0
                y: slot ? slot.y : 0
                width: slot ? slot.width : 0
                horizontalAlignment: Text.AlignRight
                text: "Last updated: " + stamp
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnPrimaryContainer
            }

            // ---- 3x2 only: the base spelled out, and its month ------------
            StyledText {
                readonly property var slot: Geometry.nameRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                visible: opacity > 0
                opacity: slot !== null ? 1 : 0
                Behavior on opacity { SpanFade {} }
                x: slot ? slot.x : 16 * Appearance.effectiveScale
                y: slot ? slot.y : root.spanH
                width: slot ? slot.width : 100
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: CurrencyService.nameFor(CurrencyService.baseCurrency)
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnPrimaryContainer
            }
            Canvas {
                id: monthCanvas
                readonly property var slot: Geometry.chart30Rect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                visible: opacity > 0
                opacity: slot !== null ? 0.9 : 0
                Behavior on opacity { SpanFade {} }
                x: slot ? slot.x : 16 * Appearance.effectiveScale
                y: slot ? slot.y : root.spanH
                width: slot ? slot.width : 100
                height: slot ? slot.height : 40
                readonly property var trend: Daily.trendFor(
                    CurrencyService.daily, CurrencyService.quote1, root.nowTick, 30)
                onTrendChanged: requestPaint()
                onWidthChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);
                    root.drawTrend(ctx, width, height, monthCanvas.trend.points,
                        Appearance.colors.colOnPrimaryContainer, true);
                }
            }
            StyledText {
                readonly property var slot: Geometry.caption30Rect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                visible: opacity > 0
                opacity: slot !== null ? 0.55 : 0
                Behavior on opacity { SpanFade {} }
                x: slot ? slot.x : 16 * Appearance.effectiveScale
                y: slot ? slot.y : root.spanH
                width: slot ? slot.width : 100
                text: monthCanvas.trend.points.length >= 2 ? "30 days period" : "collecting the month..."
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnPrimaryContainer
            }

            // ---- the quote cells: 1-2 shared, 3-4 enter and exit ----------
            Repeater {
                model: 4
                Item {
                    id: quoteCell
                    required property int index
                    readonly property var slot: Geometry.quoteCellRect(index, root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                    // Held, not read back. The fallback used to be
                    // `{ x: x, y: y, width: width, height: height }` - the very
                    // four properties it feeds - so while the slot was null the
                    // cell's geometry depended on itself. `quoteCellRect`
                    // returns null for cells 3 and 4 at 1x1
                    // (currency_geometry.js:51), so that state is reached every
                    // time the widget is shrunk, not in theory.
                    //
                    // Same fault, same file: the "to" label fifty lines up was
                    // fixed and this sibling was missed. Holding the last
                    // settled rect lets the cell fade out from where it was
                    // without asking itself where that is.
                    property real heldX: 0
                    property real heldY: 0
                    property real heldWidth: 0
                    property real heldHeight: 0
                    property bool heldStacked: true
                    onSlotChanged: if (slot !== null) {
                        heldX = slot.x;
                        heldY = slot.y;
                        heldWidth = slot.width;
                        heldHeight = slot.height;
                        heldStacked = slot.stacked ?? true;
                    }
                    readonly property var lastSlot: slot ?? ({
                        x: heldX, y: heldY, width: heldWidth, height: heldHeight, stacked: heldStacked
                    })
                    readonly property string quoteCurrency:
                        index === 0 ? CurrencyService.quote1
                        : index === 1 ? CurrencyService.quote2
                        : index === 2 ? CurrencyService.quote3
                        : CurrencyService.quote4
                    readonly property real rateVal: CurrencyService.rates[quoteCurrency] !== undefined
                        ? CurrencyService.rates[quoteCurrency] : 0.0
                    x: lastSlot.x
                    y: lastSlot.y
                    width: lastSlot.width
                    height: lastSlot.height
                    Behavior on x { SpanTravel {} }
                    Behavior on y { SpanTravel {} }
                    Behavior on width { SpanTravel {} }
                    opacity: slot !== null ? 1 : 0
                    Behavior on opacity { SpanFade {} }
                    visible: opacity > 0
                    z: 2

                    // Stacked cells sit on the panel (on-primary ink) at
                    // 2x1, but the 3x1's detailed cells sit straight on the
                    // card.
                    readonly property color inkColor: quoteCell.lastSlot.stacked && !(quoteCell.lastSlot.detailed ?? false)
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnPrimaryContainer
                    readonly property var movement: (quoteCell.lastSlot.detailed ?? false)
                        ? root.movementFor(quoteCell.quoteCurrency) : null

                    StyledText {
                        // the code: top-left when stacked, left-middle in a row
                        x: 0
                        y: quoteCell.lastSlot.stacked ? 0 : (quoteCell.height - height) / 2
                        Behavior on y { SpanTravel {} }
                        text: quoteCell.quoteCurrency
                        font.pixelSize: quoteCell.lastSlot.stacked
                            ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
                        Behavior on font.pixelSize { SpanTravel {} }
                        font.weight: quoteCell.lastSlot.stacked ? Font.Bold : Font.DemiBold
                        color: quoteCell.inkColor
                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Appearance.animation.elementMove.type
                                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                            }
                        }
                        opacity: quoteCell.lastSlot.stacked ? 1 : 0.6
                        Behavior on opacity { SpanFade {} }
                    }
                    // 3x1 only: which way the day went, beside the value.
                    MaterialSymbol {
                        visible: opacity > 0
                        opacity: quoteCell.movement !== null ? 1 : 0
                        Behavior on opacity { SpanFade {} }
                        x: valueText.x + valueText.implicitWidth + 3 * Appearance.effectiveScale
                        y: valueText.y + (valueText.height - height) / 2
                        // The flat state is a DASH: trending_flat renders as
                        // a rightward arrow, which beside a falling weekly
                        // chart read as a signal nobody could name.
                        text: quoteCell.movement === null ? "remove"
                            : quoteCell.movement.direction > 0 ? "trending_up"
                            : quoteCell.movement.direction < 0 ? "trending_down"
                            : "remove"
                        iconSize: Appearance.font.pixelSize.normal
                        color: quoteCell.movement === null ? Appearance.colors.colOnPrimaryContainer
                            : quoteCell.movement.direction > 0 ? Appearance.m3colors.m3success
                            : quoteCell.movement.direction < 0 ? Appearance.m3colors.m3error
                            : Appearance.colors.colOnPrimaryContainer
                    }

                    // 3x1 only: the movement column - percent over absolute.
                    // Centered against the value's own line and tucked in
                    // from the edge: pinned at y:0 in `smallest` it floated
                    // above the number it describes, tiny and adrift.
                    ColumnLayout {
                        id: movementColumn
                        visible: opacity > 0
                        opacity: quoteCell.movement !== null ? 1 : 0
                        Behavior on opacity { SpanFade {} }
                        anchors.right: parent.right
                        anchors.rightMargin: 2 * Appearance.effectiveScale
                        y: valueText.y + (valueText.height - movementColumn.implicitHeight) / 2
                        spacing: -2 * Appearance.effectiveScale
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: quoteCell.movement !== null ? root.signedPct(quoteCell.movement) : ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: quoteCell.inkColor
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: quoteCell.movement !== null ? root.signedAbs(quoteCell.movement) : ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            opacity: 0.7
                            color: quoteCell.inkColor
                        }
                    }

                    // 3x2 only: the quote's own week, drawn under the
                    // numbers in the direction's colour.
                    Canvas {
                        id: cellTrend
                        readonly property bool wanted: quoteCell.lastSlot.trend ?? false
                        visible: opacity > 0
                        opacity: wanted ? 1 : 0
                        Behavior on opacity { SpanFade {} }
                        x: 0
                        y: quoteCell.height * 0.45
                        width: quoteCell.width
                        height: quoteCell.height * 0.38
                        readonly property var trend: cellTrend.wanted
                            ? Daily.trendFor(CurrencyService.daily, quoteCell.quoteCurrency, root.nowTick, 7)
                            : ({ points: [], direction: 0 })
                        readonly property color trendColor: trend.direction > 0 ? Appearance.m3colors.m3success
                            : trend.direction < 0 ? Appearance.m3colors.m3error
                            : Appearance.colors.colOnPrimaryContainer
                        onTrendChanged: requestPaint()
                        onTrendColorChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onAvailableChanged: if (available) requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.clearRect(0, 0, width, height);
                            root.drawTrend(ctx, width, height,
                                cellTrend.trend.points, cellTrend.trendColor, true);
                        }
                    }
                    StyledText {
                        visible: opacity > 0
                        opacity: (quoteCell.lastSlot.trend ?? false) ? 0.55 : 0
                        Behavior on opacity { SpanFade {} }
                        width: quoteCell.width
                        y: quoteCell.height - height
                        horizontalAlignment: Text.AlignHCenter
                        text: cellTrend.trend.points.length >= 2 ? "7-Day Trend" : "collecting..."
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        id: valueText
                        // the value: under the code when stacked, right-aligned
                        // in a row
                        width: (quoteCell.lastSlot.detailed ?? false)
                            ? quoteCell.width * 0.55 : quoteCell.width
                        horizontalAlignment: quoteCell.lastSlot.stacked
                            ? Text.AlignLeft : Text.AlignRight
                        x: 0
                        y: quoteCell.lastSlot.stacked ? 14 * Appearance.effectiveScale
                            : (quoteCell.height - height) / 2
                        Behavior on y { SpanTravel {} }
                        text: {
                            if (quoteCell.rateVal > 0.0) return root.formatRate(quoteCell.rateVal);
                            if (CurrencyService.loading) return "...";
                            return CurrencyService.errorMessage || "...";
                        }
                        // A JPY-sized rate is six decimals wide and used to run
                        // straight into the next column; shrinking to fit keeps
                        // the precision without the collision.
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: Math.round(8 * Appearance.effectiveScale)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: quoteCell.inkColor
                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Appearance.animation.elementMove.type
                                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                            }
                        }
                    }
                }
            }
        }

        // --- PAGE 2: Flip Settings Mode (Zero Overflow / Scrollable Flickable) ---
        Flickable {
            anchors.fill: parent
            visible: root.showingSettings
            contentHeight: settingsCol.implicitHeight + 20 * Appearance.effectiveScale
            clip: true
            interactive: true

            ColumnLayout {
                id: settingsCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 12 * Appearance.effectiveScale
                    rightMargin: 12 * Appearance.effectiveScale
                    topMargin: 10 * Appearance.effectiveScale
                }
                spacing: 8 * Appearance.effectiveScale

                // Header Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * Appearance.effectiveScale

                    // Back button
                    Rectangle {
                        width: 24 * Appearance.effectiveScale
                        height: 24 * Appearance.effectiveScale
                        radius: 12 * Appearance.effectiveScale
                        color: Appearance.m3colors.darkmode ? "#1AFFFFFF" : "#0D000000"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            iconSize: 14 * Appearance.effectiveScale
                            color: Appearance.m3colors.m3onSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleFlip()
                        }
                    }

                    StyledText {
                        text: root.sizeMode === "1x1" ? "Config" : "Config Currencies"
                        font.pixelSize: root.sizeMode === "1x1" ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                        Layout.fillWidth: true
                    }
                }

                // Base currency input
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * Appearance.effectiveScale

                    StyledText {
                        text: "Base:"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.m3colors.m3onSurface
                        Layout.preferredWidth: 32 * Appearance.effectiveScale
                    }
                    TextField {
                        id: baseInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24 * Appearance.effectiveScale
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        placeholderText: CurrencyService.baseCurrency
                        color: Appearance.m3colors.m3onSurface
                        background: Rectangle {
                            color: Appearance.m3colors.darkmode ? "#1E2A38" : "#E8EFF8"
                            radius: 6 * Appearance.effectiveScale
                        }
                        onAccepted: {
                            if (text.trim() !== "") root.baseCurrencyRequested(text.toUpperCase().trim())
                        }
                    }
                }

                // Row 1: Quote 1 & 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * Appearance.effectiveScale

                    TextField {
                        id: quote1Input
                        Layout.fillWidth: true
                        Layout.preferredWidth: 50 * Appearance.effectiveScale
                        Layout.preferredHeight: 24 * Appearance.effectiveScale
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        placeholderText: "Q1: " + CurrencyService.quote1
                        color: Appearance.m3colors.m3onSurface
                        background: Rectangle {
                            color: Appearance.m3colors.darkmode ? "#1E2A38" : "#E8EFF8"
                            radius: 6 * Appearance.effectiveScale
                        }
                        onAccepted: {
                            if (text.trim() !== "") root.quoteCurrencyRequested(1, text.toUpperCase().trim())
                        }
                    }

                    TextField {
                        id: quote2Input
                        Layout.fillWidth: true
                        Layout.preferredWidth: 50 * Appearance.effectiveScale
                        Layout.preferredHeight: 24 * Appearance.effectiveScale
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        placeholderText: "Q2: " + CurrencyService.quote2
                        color: Appearance.m3colors.m3onSurface
                        background: Rectangle {
                            color: Appearance.m3colors.darkmode ? "#1E2A38" : "#E8EFF8"
                            radius: 6 * Appearance.effectiveScale
                        }
                        onAccepted: {
                            if (text.trim() !== "") root.quoteCurrencyRequested(2, text.toUpperCase().trim())
                        }
                    }
                }

                // Row 2: Quote 3 & 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * Appearance.effectiveScale

                    TextField {
                        id: quote3Input
                        Layout.fillWidth: true
                        Layout.preferredWidth: 50 * Appearance.effectiveScale
                        Layout.preferredHeight: 24 * Appearance.effectiveScale
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        placeholderText: "Q3: " + CurrencyService.quote3
                        color: Appearance.m3colors.m3onSurface
                        background: Rectangle {
                            color: Appearance.m3colors.darkmode ? "#1E2A38" : "#E8EFF8"
                            radius: 6 * Appearance.effectiveScale
                        }
                        onAccepted: {
                            if (text.trim() !== "") root.quoteCurrencyRequested(3, text.toUpperCase().trim())
                        }
                    }

                    TextField {
                        id: quote4Input
                        Layout.fillWidth: true
                        Layout.preferredWidth: 50 * Appearance.effectiveScale
                        Layout.preferredHeight: 24 * Appearance.effectiveScale
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        placeholderText: "Q4: " + CurrencyService.quote4
                        color: Appearance.m3colors.m3onSurface
                        background: Rectangle {
                            color: Appearance.m3colors.darkmode ? "#1E2A38" : "#E8EFF8"
                            radius: 6 * Appearance.effectiveScale
                        }
                        onAccepted: {
                            if (text.trim() !== "") root.quoteCurrencyRequested(4, text.toUpperCase().trim())
                        }
                    }
                }
            }
        }
    }
}
