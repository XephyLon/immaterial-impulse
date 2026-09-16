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

    // The settings window is where the user sits making one deliberate change
    // at a time, so while it is up its writes are flushed on the next turn
    // rather than debounced. The claim is bound to the WINDOW being on screen:
    // this scope and the content inside it are built at `Config.ready` and
    // outlive every open, so a claim tied to their existence is the whole
    // session's - which is precisely what SettingsContent's old
    // `Config.readWriteDelay = 0` turned out to be.
    ConfigWriteDelayRef {
        active: settingsWindow.visible
    }

    // A real toplevel rather than an overlay layer: Settings is a place you sit
    // in and alt-tab back to, so it should be movable and managed by the
    // compositor like any other window.
    FloatingWindow {
        id: settingsWindow
        visible: GlobalStates.settingsOpen
        title: Translation.tr("Settings")
        // Constant on purpose, and it must stay constant: a window's clear
        // colour reaching alpha 255 even once permanently costs the surface its
        // compositor blur. See AGENT.md's layer-shell section - Qt pushes an
        // opaque Wayland region on the way to opaque and never retracts it, so
        // binding this to colLayer0 left Settings unblurred for the rest of the
        // session after one transparency round trip (#143). The backdrop below
        // carries the colour instead, where alpha is only ever painted.
        color: "transparent"

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

        Rectangle {
            id: windowBackdrop
            anchors.fill: parent
            color: Appearance.colors.colLayer0
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
        CloseButton {
            id: closeButton
            anchors {
                top: parent.top
                right: parent.right
                margins: Appearance.spacing.space150
            }
            onClicked: GlobalStates.settingsOpen = false
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen; }
        function open(): void   { GlobalStates.settingsOpen = true; }
        function close(): void  { GlobalStates.settingsOpen = false; }
        // Open on a page, optionally at a section: "appearance", or
        // "appearance:Frame" - the same "<page id>[:<section>]" the launcher's
        // settings results and the desktop menu hand GlobalStates.settingsPage.
        // The id is resolved against the catalogue first (test_settings_page_ids
        // wants every link built from a page's `id`), so a typo is a log line
        // here rather than the window silently opening on whatever page was
        // last shown.
        //   qs -c imi ipc call settings page "appearance:Frame"
        function page(target: string): void {
            const parts = String(target).split(":");
            const entry = settingsContent.pages.find(p => p.id === parts[0]);
            if (!entry) {
                console.warn(`[Settings] ipc page: no page with id "${parts[0]}" (ids: ${settingsContent.pages.map(p => p.id).join(", ")})`);
                return;
            }
            const section = parts.length > 1 ? ":" + parts.slice(1).join(":") : "";
            // Open first, then the page on the next tick - the launcher's
            // order: the content consumes settingsPage once it is up, and a
            // section jump needs the page laid out to have somewhere to go.
            GlobalStates.settingsOpen = true;
            Qt.callLater(() => { GlobalStates.settingsPage = entry.id + section; });
        }
    }

    GlobalShortcut {
        name: "settingsToggle"
        description: "Toggles settings panel"
        onPressed: GlobalStates.settingsOpen = !GlobalStates.settingsOpen;
    }
}
