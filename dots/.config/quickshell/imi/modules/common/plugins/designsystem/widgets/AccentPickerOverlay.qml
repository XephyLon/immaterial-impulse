pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.services
import "../services"
import "."

PanelWindow {
    id: root
    
    WlrLayershell.namespace: "quickshell:accentPicker"
    WlrLayershell.layer: WlrLayer.Overlay 
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    
    // Explicitly cover everything
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    color: "black"
    visible: GlobalStates.accentPickerOpen

    onVisibleChanged: {
        if (visible) {
            Wallpapers.pickAccent(GlobalStates.accentPickerTarget)
        }
    }

    // A more reliable way to catch ESC globally in a window
    Shortcut {
        sequence: "Escape"
        onActivated: GlobalStates.accentPickerOpen = false
    }

    Image {
        id: bgImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: {
            // If picking for lockscreen, show lockscreen wallpaper (if it exists and separate wallpaper is enabled)
            if (GlobalStates.accentPickerTarget === "lock") {
                if (Config.options.lock && Config.options.lock.useSeparateWallpaper && Config.options.lock.wallpaperPath !== "") {
                    return Config.options.lock.wallpaperPath;
                }
                return Config.options.appearance.background.wallpaperPath;
            }

            // If picking for desktop, check for Wallpaper Engine
            if (WallpaperEngineService.active && WallpaperEngineService.screenshotPath !== "") {
                return "file://" + WallpaperEngineService.screenshotPath + "?v=" + WallpaperEngineService.screenshotVersion;
            }

            return Config.options.appearance.background.wallpaperPath;
        }
        asynchronous: true
    }

    // Subtle dim overlay to help text readability at the bottom
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 150 * Appearance.effectiveScale
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.5) }
        }
    }

    ColumnLayout {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48 * Appearance.effectiveScale
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4 * Appearance.effectiveScale

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12 * Appearance.effectiveScale
            
            MaterialSymbol {
                text: "colorize"
                iconSize: 24 * Appearance.effectiveScale
                color: "white"
            }

            StyledText {
                text: "Select a color from the wallpaper"
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: "white"
            }
        }

        StyledText {
            text: "Click anywhere to pick a color, or press ESC to cancel"
            font.pixelSize: Appearance.font.pixelSize.normal
            color: "#CCFFFFFF"
            Layout.alignment: Qt.AlignHCenter
        }
    }
    
    // Transparent MouseArea to block clicks to layers below while Picker is active
    MouseArea {
        anchors.fill: parent
    }
}
