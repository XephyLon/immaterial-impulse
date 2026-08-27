import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.osk.pinnedOnStartup ?? false

    component OskControlButton: GroupButton { // Pin button
        baseWidth: 40
        baseHeight: 40
        clickedWidth: baseWidth
        clickedHeight: baseHeight + 10
        buttonRadius: Appearance.rounding.normal
    }

    Loader {
        id: oskLoader
        active: GlobalStates.oskOpen
        onActiveChanged: {
            if (!oskLoader.active) {
                Ydotool.releaseAllKeys();
            }
        }
        
        sourceComponent: PanelWindow { // Window
            id: oskRoot
            visible: oskLoader.active && !GlobalStates.screenLocked

            anchors {
                bottom: true
                left: true
                right: true
            }

            function hide() {
                GlobalStates.oskOpen = false
            }
            exclusiveZone: root.pinned ? implicitHeight - Appearance.sizes.hyprlandGapsOut : 0
            implicitWidth: oskBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: oskBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:osk"
            WlrLayershell.layer: WlrLayer.Overlay
            // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            mask: Region {
                item: oskBackground
            }

            // Make it usable with other panels
            Component.onCompleted: {
                GlobalFocusGrab.addPersistent(oskRoot);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removePersistent(oskRoot);
            }

            // Blur is scoped to the body rather than left to the surface.
            // The catch-all `blur = true` for `quickshell:.*` frosts every
            // pixel over `ignore_alpha` (0.05), and this shadow sits well
            // above that - so the compositor blurred the shadow along with
            // the keyboard, which reads as a keyboard with a smudge under it
            // instead of a shadow. Same fix the bars, the dock, the OSDs and
            // the cheatsheet already carry (#82, #89); the layer rule turning
            // the surface-wide blur off is the other half and
            // `lint_blur_region_pairing.py` fails if either half is missing.
            WindowBlurRegion {
                targetWindow: oskRoot
                regionItem: oskBackground
                regionRadius: oskBackground.radius
            }

            // Background
            StyledRectangularShadow {
                target: oskBackground
            }
            Rectangle {
                id: oskBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.windowRounding
                property real padding: Appearance.spacing.space150
                implicitWidth: oskRowLayout.implicitWidth + padding * 2
                implicitHeight: oskRowLayout.implicitHeight + padding * 2

                Keys.onPressed: (event) => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        oskRoot.hide()
                    }
                }

                RowLayout {
                    id: oskRowLayout
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space100
                    VerticalButtonGroup {
                        OskControlButton { // Pin button
                            toggled: root.pinned
                            downAction: () => root.pinned = !root.pinned
                            contentItem: MaterialSymbol {
                                verticalAlignment: Text.AlignVCenter
                                text: "keep"
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                            }
                        }
                        OskControlButton {
                            onClicked: () => {
                                oskRoot.hide()
                            }
                            contentItem: MaterialSymbol {
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: "keyboard_hide"
                                iconSize: Appearance.font.pixelSize.larger
                            }
                        }
                    }
                    Rectangle {
                        Layout.topMargin: Appearance.spacing.space250
                        Layout.bottomMargin: Appearance.spacing.space250
                        Layout.fillHeight: true
                        implicitWidth: 1
                        color: Appearance.colors.colOutlineVariant
                    }
                    OskContent {
                        id: oskContent
                        Layout.fillWidth: true
                    }
                }
            }

        }
    }

    IpcHandler {
        target: "osk"

        function toggle(): void {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }

        function close(): void {
            GlobalStates.oskOpen = false
        }

        function open(): void {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskToggle"
        description: "Toggles on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }
    }

    GlobalShortcut {
        name: "oskOpen"
        description: "Opens on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskClose"
        description: "Closes on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = false
        }
    }

}
