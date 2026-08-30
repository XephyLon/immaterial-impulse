import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.functions as Functions
import qs.services
import "../services"
import "."

Item {
    id: root
    
    // Read orientation from config
    property bool isVertical: Config.ready ? Config.options.appearance.systemMonitor.vertical : false
    property bool useBlurBackground: false
    // The host wrapper overrides this with its own plugin id; the fallback keeps
    // the toggle honoured for a component instantiated without one.

    property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("", 0.1)
    property bool interactive: true
    // Injected by the plugin wrapper. False keeps the upstream nandoroid
    // rendering, so a host that knows nothing about this flag is unchanged.
    property bool showBattery: false
    signal verticalRequested(bool value)
    readonly property bool managesBlurTint: true

    readonly property real thirdCardLevel: showBattery
        ? Battery.percentage
        : (SystemData.diskStats && SystemData.diskStats.length > 0
            ? SystemData.diskStats[0].usage : 0)
    readonly property string thirdCardIcon: showBattery ? "battery_full" : "storage"
    readonly property string thirdCardLabel: showBattery ? "Battery" : "Disk"

    // Which metrics this instance shows, in order. The default IS the
    // upstream rendering - CPU, RAM, and the disk/battery card - per the
    // port rule (docs/PLUGIN_DESIGN_SYSTEM.md): a host that knows nothing
    // about this property is unchanged. The GPU Monitor package sets
    // ["gpu", "vram", "swap"]; any composition of the six keys is legal,
    // and the palette cycles by POSITION (primary, secondary, tertiary),
    // which is what the upstream trio already did.
    property var cards: ["cpu", "ram", "third"]
    readonly property var metricTable: ({
        cpu:   { icon: "planner_review", shape: MaterialShape.Shape.Gem,           label: "CPU" },
        ram:   { icon: "memory",         shape: MaterialShape.Shape.Cookie4Sided,  label: "RAM" },
        third: { icon: root.thirdCardIcon, shape: MaterialShape.Shape.Cookie12Sided, label: root.thirdCardLabel },
        gpu:   { icon: "developer_board", shape: MaterialShape.Shape.Sunny,        label: "GPU" },
        vram:  { icon: "memory_alt",     shape: MaterialShape.Shape.Clover4Leaf,   label: "VRAM" },
        swap:  { icon: "swap_horiz",     shape: MaterialShape.Shape.Pentagon,      label: "Swap" }
    })
    function metricLevel(key) {
        switch (key) {
        case "cpu":   return SystemData.cpuUsage;
        case "ram":   return SystemData.memUsage;
        case "third": return root.thirdCardLevel;
        case "gpu":   return SystemData.gpuUsage;
        case "vram":  return SystemData.vramUsage;
        case "swap":  return SystemData.swapUsage;
        }
        return 0;
    }
    // The three-role palette, cycled by card position - card 1 was always
    // primary, card 2 secondary, card 3 tertiary, and a fourth card starts
    // the cycle again.
    readonly property var palettes: [
        { tint: Appearance.colors.colPrimaryContainer,   accent: Appearance.colors.colPrimary,
          onAccent: Appearance.colors.colOnPrimary,       onContainer: Appearance.colors.colOnPrimaryContainer },
        { tint: Appearance.colors.colSecondaryContainer, accent: Appearance.colors.colSecondary,
          onAccent: Appearance.colors.colOnSecondary,     onContainer: Appearance.colors.colOnSecondaryContainer },
        { tint: Appearance.colors.colTertiaryContainer,  accent: Appearance.colors.colTertiary,
          onAccent: Appearance.colors.colOnTertiary,      onContainer: Appearance.colors.colOnTertiaryContainer }
    ]

    // Scale dimensions cleanly based on Choice A (Grid: 132x108, Gap: 12)
    // Horizontal 3x1: 420 x 108
    // Vertical 1x3: 132 x 348 (108 * 3 + 12 * 2)
    // N cards on the widget-grid lattice: N cells plus the gaps between
    // them, which for the default three is the 420x108 / 132x348 it always
    // was (docs/widget-grid.md - the cell is 132x108, the gap 12).
    readonly property int cardCount: root.cards.length
    property real baseWidth: isVertical ? 132 : (cardCount * 132 + (cardCount - 1) * 12)
    property real baseHeight: isVertical ? (cardCount * 108 + (cardCount - 1) * 12) : 108
    implicitWidth: baseWidth * Appearance.effectiveScale
    implicitHeight: baseHeight * Appearance.effectiveScale

    // Spacings and sizes
    property real cardSpacing: 12 * Appearance.effectiveScale
    property real cardHeight: isVertical ? (108 * Appearance.effectiveScale) : (108 * Appearance.effectiveScale)
    property real cardWidth: 132 * Appearance.effectiveScale
    // The grip sits at the widget's bottom-right, so the tension lands on the
    // card under it - thirdCard. All three bowing identically would read as
    // jelly, not as a pull.
    property point resizeBow: Qt.point(0, 0)
    // Handled state, for the cards' elevation.
    property bool dragging: false
    // The host's box is animating; the cards drop their shadow for it.
    property bool boxInMotion: false
    // One region per card, rebuilt when the set or the layout changes.
    // `cardsReady` is the notify itemAt() does not have: the Repeater bumps
    // it as delegates land, so the binding re-runs once they exist rather
    // than reading nulls at creation. The regions themselves are static per
    // layout - a card never moves inside the widget - so those are the only
    // dependencies the list needs.
    property int cardsReady: 0
    readonly property var blurRegions: {
        void root.cardsReady;
        void root.isVertical;
        const out = [];
        for (let i = 0; i < cardRepeater.count; i++) {
            const card = cardRepeater.itemAt(i);
            if (card) out.push(card.blurRegion);
        }
        return out;
    }

    // One metric's face - the upstream card, generalised only in WHICH
    // metric it reads: the 38px liquid shape up top (fill height = usage,
    // glyph flips past 0.55), the % and label centred at the bottom.
    component MetricCard: WidgetCard {
        id: card
        required property int index
        required property string modelData
        readonly property var face: root.metricTable[card.modelData]
        readonly property real level: root.metricLevel(card.modelData)
        readonly property var roles: root.palettes[card.index % root.palettes.length]

        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight
        dragging: root.dragging
        hostMotionActive: root.boxInMotion
        radius: Appearance.rounding.large
        tint: card.roles.tint
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
        // The grip sits at the widget's bottom-right, so the tension lands
        // on the card under it - the last one. All bowing identically would
        // read as jelly, not as a pull.
        tensionX: card.index === root.cardCount - 1 ? root.resizeBow.x : 0
        tensionY: card.index === root.cardCount - 1 ? root.resizeBow.y : 0

        Item {
            id: visual
            width: 38 * Appearance.effectiveScale
            height: 38 * Appearance.effectiveScale
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                topMargin: 12 * Appearance.effectiveScale
            }

            MaterialShape {
                id: shapeMask
                anchors.fill: parent
                shape: card.face.shape
                color: "black"
                visible: false
            }

            Item {
                id: shapeContent
                anchors.fill: parent
                visible: false

                MaterialShape {
                    anchors.fill: parent
                    shape: card.face.shape
                    color: Functions.ColorUtils.applyAlpha(card.roles.accent, 0.15)
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: parent.height * card.level
                    color: card.roles.accent
                }
            }

            OpacityMask {
                anchors.fill: parent
                source: shapeContent
                maskSource: shapeMask
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: card.face.icon
                iconSize: 16 * Appearance.effectiveScale
                color: card.level > 0.55 ? card.roles.onAccent : card.roles.accent
            }
        }

        ColumnLayout {
            spacing: -2 * Appearance.effectiveScale
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                bottomMargin: 10 * Appearance.effectiveScale
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Math.round(card.level * 100) + "%"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: card.roles.onContainer
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: card.face.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: card.roles.onContainer
                opacity: 0.6
            }
        }
    }


    Grid {
        id: gridLayout
        columns: root.isVertical ? 1 : root.cardCount
        spacing: root.cardSpacing

        Repeater {
            id: cardRepeater
            model: root.cards
            onItemAdded: root.cardsReady++
            onItemRemoved: root.cardsReady++
            delegate: MetricCard {}
        }
    }

    // Toggle Handle to switch layout direction (only visible when hovered and not locked)
    Rectangle {
        id: toggleHandle
        z: 10 // Lift button above the passthrough widgetMouseArea
        width: 28 * Appearance.effectiveScale
        height: 28 * Appearance.effectiveScale
        radius: 10 * Appearance.effectiveScale
        color: Appearance.m3colors.darkmode ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSecondaryContainer
        
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 6 * Appearance.effectiveScale
        }
        
        opacity: root.interactive && (widgetMouseArea.containsMouse || toggleArea.containsMouse) ? 0.9 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "screen_rotation"
            iconSize: 15 * Appearance.effectiveScale
            color: Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colOnSecondaryContainer
        }

        MouseArea {
            id: toggleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onClicked: {
                root.verticalRequested(!root.isVertical)
            }
        }
    }

    // Outer hover area to trigger handles
    MouseArea {
        id: widgetMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton // Passthrough clicks
        cursorShape: Qt.ArrowCursor
    }
}
