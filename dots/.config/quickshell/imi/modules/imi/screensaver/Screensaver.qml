import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool active: GlobalStates.screensaverActive
    readonly property string mode: Config.options.screensaver?.mode ?? "black"

    Variants { // One overlay surface per screen
        model: Quickshell.screens

        delegate: Loader {
            id: screenLoader
            required property ShellScreen modelData
            active: root.active

            sourceComponent: PanelWindow {
                id: saverWindow
                screen: screenLoader.modelData
                visible: true

                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:screensaver"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                color: "transparent"

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                // Mapping a fullscreen overlay under the cursor makes the
                // compositor send a pointer enter/motion event, which would
                // instantly self-dismiss the screensaver. Ignore all input until
                // armed a moment after it appears; real input then wakes it.
                property bool armed: false
                Timer {
                    id: armTimer
                    interval: 600
                    running: true
                    onTriggered: saverWindow.armed = true
                }

                function dismiss() {
                    if (!saverWindow.armed)
                        return;
                    GlobalStates.screensaverActive = false;
                }

                Item {
                    id: inputScope
                    anchors.fill: parent
                    focus: true

                    // Any input (once armed) dismisses; unloading resets the drift.
                    Keys.onPressed: saverWindow.dismiss()

                    ScreensaverContent {
                        anchors.fill: parent
                        mode: root.mode
                        active: root.active
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: saverWindow.dismiss()
                        onPressed: saverWindow.dismiss()
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "screensaver"

        function show(): void {
            if (!(Config.options.screensaver?.enable ?? false))
                return;
            GlobalStates.screensaverActive = true;
        }

        function hide(): void {
            GlobalStates.screensaverActive = false;
        }

        function toggle(): void {
            if (GlobalStates.screensaverActive)
                GlobalStates.screensaverActive = false;
            else if (Config.options.screensaver?.enable ?? false)
                GlobalStates.screensaverActive = true;
        }
    }
}
