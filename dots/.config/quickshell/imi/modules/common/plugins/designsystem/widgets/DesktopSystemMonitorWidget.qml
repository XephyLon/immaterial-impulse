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

    // Scale dimensions cleanly based on Choice A (Grid: 132x108, Gap: 12)
    // Horizontal 3x1: 420 x 108
    // Vertical 1x3: 132 x 348 (108 * 3 + 12 * 2)
    property real baseWidth: isVertical ? 132 : 420
    property real baseHeight: isVertical ? 348 : 108
    implicitWidth: baseWidth * Appearance.effectiveScale
    implicitHeight: baseHeight * Appearance.effectiveScale

    // Spacings and sizes
    property real cardSpacing: 12 * Appearance.effectiveScale
    property real cardHeight: isVertical ? (108 * Appearance.effectiveScale) : (108 * Appearance.effectiveScale)
    property real cardWidth: isVertical ? (132 * Appearance.effectiveScale) : ((420 * Appearance.effectiveScale - cardSpacing * 2) / 3)
    // The grip sits at the widget's bottom-right, so the tension lands on the
    // card under it - thirdCard. All three bowing identically would read as
    // jelly, not as a pull.
    property point resizeBow: Qt.point(0, 0)
    // Handled state, for the cards' elevation.
    property bool dragging: false
    // The host's box is animating; the cards drop their shadow for it.
    property bool boxInMotion: false
    readonly property var blurRegions: [
        cpuCard.blurRegion,
        ramCard.blurRegion,
        thirdCard.blurRegion
    ]


    Grid {
        id: gridLayout
        columns: root.isVertical ? 1 : 3
        spacing: root.cardSpacing

        // CARD 1: CPU (Split-Level Centered Layout)
        WidgetCard {
            id: cpuCard
            implicitWidth: root.cardWidth
            implicitHeight: root.cardHeight
            dragging: root.dragging
            hostMotionActive: root.boxInMotion
            radius: Appearance.rounding.large
            tint: Appearance.colors.colPrimaryContainer
            useBlurBackground: root.useBlurBackground
            backgroundOpacity: root.backgroundOpacity

            // Sisi Atas: Liquid Gem (Centered Top)
            Item {
                id: cpuVisualContainer
                width: 38 * Appearance.effectiveScale
                height: 38 * Appearance.effectiveScale
                anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                    topMargin: 12 * Appearance.effectiveScale
                }

                MaterialShape {
                    id: cpuMask
                    anchors.fill: parent
                    shape: MaterialShape.Shape.Gem
                    color: "black"
                    visible: false
                }

                Item {
                    id: cpuContent
                    anchors.fill: parent
                    visible: false

                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Gem
                        color: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15)
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: parent.height * SystemData.cpuUsage
                        color: Appearance.colors.colPrimary
                    }
                }

                OpacityMask {
                    anchors.fill: parent
                    source: cpuContent
                    maskSource: cpuMask
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "planner_review"
                    iconSize: 16 * Appearance.effectiveScale
                    color: SystemData.cpuUsage > 0.55 ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                }
            }

            // Sisi Bawah: Text Info (Centered Bottom)
            ColumnLayout {
                spacing: -2 * Appearance.effectiveScale
                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: 10 * Appearance.effectiveScale
                }
                
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(SystemData.cpuUsage * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "CPU"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.6
                }
            }
        }

        // CARD 2: RAM (Split-Level Centered Layout)
        WidgetCard {
            id: ramCard
            implicitWidth: root.cardWidth
            implicitHeight: root.cardHeight
            dragging: root.dragging
            hostMotionActive: root.boxInMotion
            radius: Appearance.rounding.large
            tint: Appearance.colors.colSecondaryContainer
            useBlurBackground: root.useBlurBackground
            backgroundOpacity: root.backgroundOpacity

            // Sisi Atas: Liquid Cookie4Sided (Centered Top)
            Item {
                id: ramVisualContainer
                width: 38 * Appearance.effectiveScale
                height: 38 * Appearance.effectiveScale
                anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                    topMargin: 12 * Appearance.effectiveScale
                }

                MaterialShape {
                    id: ramMask
                    anchors.fill: parent
                    shape: MaterialShape.Shape.Cookie4Sided
                    color: "black"
                    visible: false
                }

                Item {
                    id: ramContent
                    anchors.fill: parent
                    visible: false

                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie4Sided
                        color: Functions.ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.15)
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: parent.height * SystemData.memUsage
                        color: Appearance.colors.colSecondary
                    }
                }

                OpacityMask {
                    anchors.fill: parent
                    source: ramContent
                    maskSource: ramMask
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "memory"
                    iconSize: 16 * Appearance.effectiveScale
                    color: SystemData.memUsage > 0.55 ? Appearance.colors.colOnSecondary : Appearance.colors.colSecondary
                }
            }

            // Sisi Bawah: Text Info (Centered Bottom)
            ColumnLayout {
                spacing: -2 * Appearance.effectiveScale
                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: 10 * Appearance.effectiveScale
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(SystemData.memUsage * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "RAM"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.6
                }
            }
        }

        // CARD 3: DISK or BATTERY (Split-Level Centered Layout)
        WidgetCard {
            id: thirdCard
            implicitWidth: root.cardWidth
            implicitHeight: root.cardHeight
            radius: Appearance.rounding.large
            tint: Appearance.colors.colTertiaryContainer
            useBlurBackground: root.useBlurBackground
            backgroundOpacity: root.backgroundOpacity
            tensionX: root.resizeBow.x
            tensionY: root.resizeBow.y
            dragging: root.dragging
            hostMotionActive: root.boxInMotion

            // Sisi Atas: Liquid Cookie12Sided (Centered Top)
            Item {
                id: thirdVisualContainer
                width: 38 * Appearance.effectiveScale
                height: 38 * Appearance.effectiveScale
                anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                    topMargin: 12 * Appearance.effectiveScale
                }

                MaterialShape {
                    id: thirdMask
                    anchors.fill: parent
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: "black"
                    visible: false
                }

                Item {
                    id: thirdContent
                    anchors.fill: parent
                    visible: false

                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: Functions.ColorUtils.applyAlpha(Appearance.colors.colTertiary, 0.15)
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: parent.height * root.thirdCardLevel
                        color: Appearance.colors.colTertiary
                    }
                }

                OpacityMask {
                    anchors.fill: parent
                    source: thirdContent
                    maskSource: thirdMask
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.thirdCardIcon
                    iconSize: 16 * Appearance.effectiveScale
                    // Inverts once the fill has risen past the glyph, so this
                    // tracks the fill level rather than meaning "too high".
                    color: root.thirdCardLevel > 0.55
                        ? Appearance.colors.colOnTertiary : Appearance.colors.colTertiary
                }
            }

            // Sisi Bawah: Text Info (Centered Bottom)
            ColumnLayout {
                spacing: -2 * Appearance.effectiveScale
                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: 10 * Appearance.effectiveScale
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(root.thirdCardLevel * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnTertiaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.thirdCardLabel
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnTertiaryContainer
                    opacity: 0.6
                }
            }
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
