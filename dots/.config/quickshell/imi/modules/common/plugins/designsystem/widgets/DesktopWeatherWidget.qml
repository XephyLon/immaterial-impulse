import qs.modules.common
import qs.modules.common.functions as Functions
import qs.services
import "."
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    // Config configuration linkage
    property var cfg: Config.ready ? Config.options.appearance.weatherWidget : null
    property string sizeMode: cfg ? cfg.sizeMode : "3x1"
    property bool interactive: true
    property bool useBlurBackground: false
    property real backgroundOpacity: 0.1
    signal sizeModeRequested(string value)
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [{
        x: card.x, y: card.y, width: card.width, height: card.height, radius: card.radius
    }]
    
    HoverHandler {
        id: widgetHoverHandler
    }
    
    // Choice A Grid System Specs
    readonly property real baseWidth: 132 * Appearance.effectiveScale
    readonly property real baseHeight: 108 * Appearance.effectiveScale
    readonly property real gap: 12 * Appearance.effectiveScale
    
    // Snap mode dimensions
    readonly property real width1x1: baseWidth
    readonly property real width2x1: (baseWidth * 2) + gap
    readonly property real width3x1: (baseWidth * 3) + (gap * 2)

    implicitHeight: baseHeight
    implicitWidth: {
        if (sizeMode === "1x1") return width1x1;
        if (sizeMode === "2x1") return width2x1;
        return width3x1;
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.bezierCurve: Appearance.animation.elementResize.numberAnimation?.easing?.bezierCurve || [0.2, 0, 0, 1]
        }
    }

    // CustomIcon lives one directory below this imported widget's former location.
    // Walk back to the shared, preserved upstream icon set at repository /assets.
    readonly property string weatherIconsDir: "../../../../assets/icons/google-weather"
    readonly property color contentColor: Appearance.m3colors.m3onSurface
    readonly property real midOpacity: 0.8
    readonly property real lowOpacity: 0.6
    // Adapt end4's OpenWeather service schema to the original nandoroid visual.
    // The widget remains visually unchanged; only its data source is translated.
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

    // Helper logic to convert dragged width into matching size modes
    function getModeForWidth(targetWidth) {
        let mid1 = (width1x1 + width2x1) / 2;
        let mid2 = (width2x1 + width3x1) / 2;
        if (targetWidth < mid1) return "1x1";
        if (targetWidth < mid2) return "2x1";
        return "3x1";
    }

    // Flat Material 3 container (No shadows for clean widget look)
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 30 * Appearance.effectiveScale
        color: root.useBlurBackground
            ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, root.backgroundOpacity)
            : Appearance.colors.colOnPrimary

        // Mask the entire card contents to ensure split vertical panels and slanted leaves clip perfectly at the rounded corners
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: card.width
                height: card.height
                radius: card.radius
            }
        }

        // Layout Loader based on sizeMode
        Loader {
            anchors.fill: parent
            sourceComponent: {
                if (root.sizeMode === "1x1") return mode1x1Layout;
                if (root.sizeMode === "2x1") return mode2x1Layout;
                return mode3x1Layout;
            }
        }

        // ──────────────────────────────
        // TATA LETAK 1x1
        // ──────────────────────────────
        Component {
            id: mode1x1Layout
            Item {
                anchors.fill: parent

                // Kiri Atas: Suhu Utama Sangat Besar
                ColumnLayout {
                    anchors {
                        left: parent.left
                        top: parent.top
                        leftMargin: 16 * Appearance.effectiveScale
                        topMargin: 14 * Appearance.effectiveScale
                    }
                    spacing: 2 * Appearance.effectiveScale

                    StyledText {
                        text: root.temperature + "°"
                        font.pixelSize: Math.round(44 * Appearance.effectiveScale)
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        text: root.condition
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        color: root.contentColor
                        opacity: 0.8
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        Layout.maximumWidth: 58 * Appearance.effectiveScale // Clean wrap before reaching the leaf
                    }
                }

                // Kanan Bawah: Giant Slanted Leaf Overlay (Rotated Pill overlapping the edge)
                Item {
                    width: 50 * Appearance.effectiveScale
                    height: 50 * Appearance.effectiveScale
                    
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        rightMargin: -6 * Appearance.effectiveScale // Elegant overlap
                        bottomMargin: -6 * Appearance.effectiveScale
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 16 * Appearance.effectiveScale
                        color: Appearance.colors.colPrimary
                        rotation: -22 // Bold Android slanted shape
                    }

                    CustomIcon {
                        anchors.centerIn: parent
                        source: root.weatherIcon
                        iconFolder: root.weatherIconsDir
                        width: 28 * Appearance.effectiveScale
                        height: 28 * Appearance.effectiveScale
                        colorize: true
                        color: Appearance.colors.colOnPrimary
                        rotation: 22 // Rotate icon back straight
                    }
                }
            }
        }

        // ──────────────────────────────
        // TATA LETAK 2x1
        // ──────────────────────────────
        Component {
            id: mode2x1Layout
            Item {
                anchors.fill: parent

                // Area Kiri: Info Cuaca Vertikal - Terpusat Vertikal Secara Geometris
                ColumnLayout {
                    id: textCol
                    spacing: 2 * Appearance.effectiveScale
                    
                    anchors {
                        left: parent.left
                        right: rightIconCard.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 20 * Appearance.effectiveScale
                        rightMargin: 12 * Appearance.effectiveScale
                    }

                    StyledText {
                        text: root.temperature + "°"
                        font.pixelSize: Math.round(44 * Appearance.effectiveScale)
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.condition
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: root.contentColor
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `Feels like ${root.feelsLike}°`
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.contentColor
                        opacity: 0.6
                        elide: Text.ElideRight
                    }
                }

                // Area Kanan: Split Solid Panel dengan sudut KIRI membulat (Rounded Left Edge)
                Rectangle {
                    id: rightIconCard
                    width: 76 * Appearance.effectiveScale
                    radius: 30 * Appearance.effectiveScale // Rounds the left-top and left-bottom edges beautifully
                    color: Appearance.colors.colPrimary
                    
                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }

                    CustomIcon {
                        anchors.centerIn: parent
                        source: root.weatherIcon
                        iconFolder: root.weatherIconsDir
                        width: 36 * Appearance.effectiveScale
                        height: 36 * Appearance.effectiveScale
                        colorize: true
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        // ──────────────────────────────
        // TATA LETAK 3x1
        // ──────────────────────────────
        Component {
            id: mode3x1Layout
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16 * Appearance.effectiveScale
                anchors.leftMargin: 20 * Appearance.effectiveScale
                spacing: 16 * Appearance.effectiveScale

                // 1. Suhu Utama Raksasa di Kiri
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2 * Appearance.effectiveScale

                    StyledText {
                        text: root.temperature + "°"
                        font.pixelSize: Math.round(48 * Appearance.effectiveScale)
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                    
                    StyledText {
                        text: `High ${root.highTemperature}° · Low ${root.lowTemperature}°`
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.contentColor
                        opacity: 0.6
                    }
                }

                // Divider line vertical
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: root.contentColor
                    opacity: 0.15
                }

                // 2. Deskripsi & Mini Badge Pills
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 8 * Appearance.effectiveScale

                    StyledText {
                        Layout.fillWidth: true
                        text: root.condition
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: root.contentColor
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8 * Appearance.effectiveScale

                        // Humidity Badge (Clean Solid Text via RGBA Background Color)
                        Rectangle {
                            Layout.preferredHeight: 22 * Appearance.effectiveScale
                            implicitWidth: humidityLayout.implicitWidth + (16 * Appearance.effectiveScale)
                            radius: 11 * Appearance.effectiveScale
                            color: Appearance.m3colors.darkmode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)

                            RowLayout {
                                id: humidityLayout
                                anchors.centerIn: parent
                                spacing: 4 * Appearance.effectiveScale
                                MaterialSymbol {
                                    iconSize: 14 * Appearance.effectiveScale
                                    text: "humidity_mid"
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: root.humidity
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: root.contentColor
                                }
                            }
                        }

                        // Wind Speed Badge (Clean Solid Text via RGBA Background Color)
                        Rectangle {
                            Layout.preferredHeight: 22 * Appearance.effectiveScale
                            implicitWidth: windLayout.implicitWidth + (16 * Appearance.effectiveScale)
                            radius: 11 * Appearance.effectiveScale
                            color: Appearance.m3colors.darkmode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)

                            RowLayout {
                                id: windLayout
                                anchors.centerIn: parent
                                spacing: 4 * Appearance.effectiveScale
                                MaterialSymbol {
                                    iconSize: 14 * Appearance.effectiveScale
                                    text: "air"
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: root.wind
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: root.contentColor
                                }
                            }
                        }
                    }
                }

                // 3. Ikon Cuaca berbentuk Ghostish Raksasa (Estetika Premium & Anti-Luber) di Kanan
                MaterialShape {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 72 * Appearance.effectiveScale
                    implicitHeight: 72 * Appearance.effectiveScale
                    shape: MaterialShape.Shape.Ghostish // Sleek asymmetric wavy shape
                    color: Appearance.colors.colPrimary

                    CustomIcon {
                        anchors.centerIn: parent
                        source: root.weatherIcon
                        iconFolder: root.weatherIconsDir
                        width: 42 * Appearance.effectiveScale
                        height: 42 * Appearance.effectiveScale
                        colorize: true
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }

    }

    // ──────────────────────────────
    // Drag Handle to Resize (Horizontal) - Placed outside card to prevent OpacityMask clipping
    // ──────────────────────────────
    Rectangle {
        id: resizeHandle
        z: 10
        width: 28 * Appearance.effectiveScale
        height: 28 * Appearance.effectiveScale
        radius: 10 * Appearance.effectiveScale
        
        // Restore dynamic colors matching AtAGlance/SystemMonitor
        color: Appearance.m3colors.darkmode ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSecondaryContainer
        
        anchors {
            right: root.right
            bottom: root.bottom
            margins: 6 * Appearance.effectiveScale
        }
        
        opacity: root.interactive && (cfg && !cfg.locked) && (widgetHoverHandler.hovered || resizeArea.containsMouse || resizeArea.pressed) ? 0.9 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "swap_horiz"
            iconSize: 15 * Appearance.effectiveScale
            color: Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colOnSecondaryContainer
        }

        MouseArea {
            id: resizeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            preventStealing: true

            property real startWidth: 0
            property real startGlobalX: 0

            onPressed: (mouse) => {
                startWidth = root.width;
                let p = mapToItem(null, mouse.x, mouse.y);
                startGlobalX = p.x;
            }

            onPositionChanged: (mouse) => {
                if (!pressed) return;
                let p = mapToItem(null, mouse.x, mouse.y);
                let deltaX = p.x - startGlobalX;
                let targetWidth = startWidth + deltaX;
                
                let targetMode = root.getModeForWidth(targetWidth);
                if (targetMode !== root.sizeMode) {
                    root.sizeModeRequested(targetMode)
                }
            }
        }
    }
}
