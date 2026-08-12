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

Item {
    id: root
    
    property var cfg: Config.ready ? Config.options.appearance.currencyWidget : null
    property string sizeMode: cfg ? cfg.sizeMode : "2x1"
    property bool useBlurBackground: false
    property point resizeBow: Qt.point(0, 0)
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

    implicitHeight: baseHeight
    implicitWidth: {
        if (sizeMode === "1x1") return width1x1;
        return width2x1;
    }

    // Geometry evaluates at the span's SETTLED box; Behaviors carry the
    // travel (the media tree's frozen-Behavior lesson). Reading implicitWidth
    // here instead would retarget every element every frame, and elements
    // whose x depends on the right edge - the panel, its cells - would crawl
    // behind the card instead of travelling with it.
    readonly property real spanW: root.sizeMode === "1x1" ? root.width1x1 : root.width2x1
    readonly property real spanH: root.baseHeight

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

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.bezierCurve: [0.2, 0, 0, 1]
        }
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
        tint: Appearance.colors.colPrimaryContainer
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
        tensionX: root.resizeBow.x
        tensionY: root.resizeBow.y

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

            // 2x1 only: the sparkline backdrop
            Canvas {
                id: sparklineCanvas
                anchors.fill: parent
                opacity: root.sizeMode === "2x1" ? 0.35 : 0
                Behavior on opacity { FadeBehavior {} }
                visible: opacity > 0
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = Appearance.colors.colOnPrimaryContainer;
                    ctx.lineWidth = 2 * Appearance.effectiveScale;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    let points = [0.8, 0.6, 0.75, 0.4, 0.55, 0.3, 0.45, 0.2];
                    let step = width / (points.length - 1);
                    ctx.moveTo(0, height * points[0]);
                    for (let i = 1; i < points.length; i++) {
                        let x = i * step;
                        let y = height * points[i];
                        let prevX = (i - 1) * step;
                        let prevY = height * points[i - 1];
                        ctx.bezierCurveTo(prevX + step/2, prevY, x - step/2, y, x, y);
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
                Behavior on x { TravelBehavior {} }
                Behavior on y { TravelBehavior {} }
                Behavior on width { TravelBehavior {} }
                Behavior on height { TravelBehavior {} }

                Canvas {
                    id: containerCanvas
                    anchors.fill: parent
                    property string shownShape: container.slot.shape
                    property string fromShape: container.slot.shape
                    property real morphT: 1
                    Behavior on morphT { id: morphGate; TravelBehavior {} }
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

                // 1x1 only: the payments badge glyph, fading as the container
                // becomes a data panel.
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "payments"
                    iconSize: 18 * Appearance.effectiveScale
                    color: Appearance.colors.colOnPrimary
                    opacity: root.sizeMode === "1x1" ? 1 : 0
                    Behavior on opacity { FadeBehavior {} }
                    visible: opacity > 0
                }
            }

            // ---- shared: "Rates" ------------------------------------------
            StyledText {
                objectName: "currencyRatesLabel"
                readonly property var slot: Geometry.ratesLabelRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                x: slot.x
                y: slot.y
                Behavior on x { TravelBehavior {} }
                Behavior on y { TravelBehavior {} }
                text: "Rates"
                font.pixelSize: root.sizeMode === "1x1" ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
                Behavior on font.pixelSize { TravelBehavior {} }
                font.weight: root.sizeMode === "1x1" ? Font.DemiBold : Font.Bold
                Behavior on font.weight { TravelBehavior {} }
                color: Appearance.colors.colOnPrimaryContainer
                opacity: root.sizeMode === "1x1" ? 0.6 : 0.8
                Behavior on opacity { FadeBehavior {} }
            }

            // ---- 1x1 only: the word "to" ----------------------------------
            // Its own element, because swapping the text of the code below
            // ("to USD" to "USD") would be a content snap in the middle of
            // the morph - exactly what this architecture exists to kill.
            StyledText {
                id: basePrefix
                objectName: "currencyBasePrefix"
                readonly property var slot: Geometry.basePrefixRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                readonly property var lastSlot: slot ?? ({ x: x, y: y, size: font.pixelSize })
                x: lastSlot.x
                y: lastSlot.y
                Behavior on x { TravelBehavior {} }
                Behavior on y { TravelBehavior {} }
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
                objectName: "currencyBase"
                readonly property var slot: Geometry.baseLabelRect(root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                // The group's left edge travels; the code then sits after
                // whatever width the fading prefix still occupies, so it
                // slides into that space instead of jumping when it vanishes.
                property real groupX: slot.x
                Behavior on groupX { TravelBehavior {} }
                x: groupX + (basePrefix.paintedWidth + 3 * Appearance.effectiveScale) * basePrefix.opacity
                y: slot.y
                Behavior on y { TravelBehavior {} }
                text: CurrencyService.baseCurrency
                font.pixelSize: Math.round(slot.size)
                Behavior on font.pixelSize { TravelBehavior {} }
                font.weight: Font.Bold
                color: root.sizeMode === "1x1" ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimaryContainer
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMove.duration } }
            }

            // ---- the quote cells: 1-2 shared, 3-4 enter and exit ----------
            Repeater {
                model: 4
                Item {
                    id: quoteCell
                    required property int index
                    readonly property var slot: Geometry.quoteCellRect(index, root.sizeMode, root.spanW, root.spanH, Appearance.effectiveScale)
                    readonly property var lastSlot: slot ?? ({ x: x, y: y, width: width, height: height, stacked: true })
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
                    Behavior on x { TravelBehavior {} }
                    Behavior on y { TravelBehavior {} }
                    Behavior on width { TravelBehavior {} }
                    opacity: slot !== null ? 1 : 0
                    Behavior on opacity { FadeBehavior {} }
                    visible: opacity > 0
                    z: 2

                    readonly property color inkColor: quoteCell.lastSlot.stacked
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnPrimaryContainer

                    StyledText {
                        // the code: top-left when stacked, left-middle in a row
                        x: 0
                        y: quoteCell.lastSlot.stacked ? 0 : (quoteCell.height - height) / 2
                        Behavior on y { TravelBehavior {} }
                        text: quoteCell.quoteCurrency
                        font.pixelSize: quoteCell.lastSlot.stacked
                            ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
                        Behavior on font.pixelSize { TravelBehavior {} }
                        font.weight: quoteCell.lastSlot.stacked ? Font.Bold : Font.DemiBold
                        color: quoteCell.inkColor
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMove.duration } }
                        opacity: quoteCell.lastSlot.stacked ? 1 : 0.6
                        Behavior on opacity { FadeBehavior {} }
                    }
                    StyledText {
                        // the value: under the code when stacked, right-aligned
                        // in a row
                        width: quoteCell.width
                        horizontalAlignment: quoteCell.lastSlot.stacked
                            ? Text.AlignLeft : Text.AlignRight
                        x: 0
                        y: quoteCell.lastSlot.stacked ? 14 * Appearance.effectiveScale
                            : (quoteCell.height - height) / 2
                        Behavior on y { TravelBehavior {} }
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
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMove.duration } }
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
