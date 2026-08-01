//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
import Quickshell.Io
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    readonly property int windowWidth: 980
    readonly property int windowHeight: 665

    Component.onCompleted: {
        GlobalStates.settingsOpen = false;
    }

    // A real toplevel rather than an overlay layer: Settings is a place you sit
    // in and alt-tab back to, so it should be movable and managed by the
    // compositor like any other window.
    FloatingWindow {
        id: settingsWindow
        visible: GlobalStates.settingsOpen
        title: Translation.tr("Settings")
        color: Appearance.colors.colLayer0

        // Fixed size: the layout is designed around these dimensions, and a
        // floating utility window has no reason to be resized.
        implicitWidth: root.windowWidth
        implicitHeight: root.windowHeight
        minimumSize.width: root.windowWidth
        minimumSize.height: root.windowHeight
        maximumSize.width: root.windowWidth
        maximumSize.height: root.windowHeight

        // Closing from the titlebar has to feed back into the state the IPC
        // handler and the shortcut both drive.
        onVisibleChanged: {
            if (!visible && GlobalStates.settingsOpen)
                GlobalStates.settingsOpen = false;
        }

        SettingsContent {
            id: settingsContent
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.settingsOpen = false;
                    event.accepted = true;
                }
            }
        }

        // Hyprland draws no server-side decorations, so the window carries its
        // own close affordance.
        RippleButton {
            id: closeButton
            anchors {
                top: parent.top
                right: parent.right
                margins: Appearance.spacing.space150
            }
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: GlobalStates.settingsOpen = false

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "close"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer0
            }

            StyledToolTip {
                text: Translation.tr("Close")
            }
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen; }
        function open(): void   { GlobalStates.settingsOpen = true; }
        function close(): void  { GlobalStates.settingsOpen = false; }
    }

    GlobalShortcut {
        name: "settingsToggle"
        description: "Toggles settings panel"
        onPressed: GlobalStates.settingsOpen = !GlobalStates.settingsOpen;
    }
}
