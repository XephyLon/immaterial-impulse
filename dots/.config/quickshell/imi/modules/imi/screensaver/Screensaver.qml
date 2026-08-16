import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "screensaver_screens.js" as ScreensaverScreens

Scope {
    id: root

    // Two ways in, and they are not the same thing.
    //
    // `screensaverActive` is the idle path: hypridle's 240s listener calls
    // show(), every screen goes black, and the lock/DPMS/suspend ladder behind
    // it (300/600/900s) must keep running - nobody is here.
    //
    // `screensaverScreens` is the deliberate path: the user named a monitor,
    // so that monitor blacks out, the others are untouched, and an idle
    // inhibitor is held (services/Idle.qml) so blanking a panel on purpose
    // cannot walk the session into a lock or a suspend.
    property bool idleActive: GlobalStates.screensaverActive
    readonly property var deliberateScreens: GlobalStates.screensaverScreens
    readonly property string mode: Config.options.screensaver?.mode ?? "black"

    function showOn(name: string): void {
        GlobalStates.screensaverScreens = ScreensaverScreens.withScreen(root.deliberateScreens, name);
    }

    function hideOn(name: string): void {
        GlobalStates.screensaverScreens = ScreensaverScreens.withoutScreen(root.deliberateScreens, name);
    }

    function toggleOn(name: string): void {
        GlobalStates.screensaverScreens = ScreensaverScreens.toggledScreen(root.deliberateScreens, name);
    }

    function toggleAll(): void {
        const next = ScreensaverScreens.toggledAll(root.deliberateScreens, Quickshell.screens.map(screen => screen.name), root.idleActive);
        GlobalStates.screensaverActive = false;
        GlobalStates.screensaverScreens = next;
    }

    Connections {
        target: Quickshell

        // An unplugged monitor's overlay goes away with its delegate, but its
        // name would stay in the list - and the inhibitor derived from the list
        // would be held for the rest of the session with nothing on screen to
        // explain it.
        function onScreensChanged(): void {
            const live = ScreensaverScreens.pruned(root.deliberateScreens, Quickshell.screens.map(screen => screen.name));
            if (live.length !== root.deliberateScreens.length)
                GlobalStates.screensaverScreens = live;
        }
    }

    Variants { // One overlay surface per screen
        model: Quickshell.screens

        delegate: Loader {
            id: screenLoader
            required property ShellScreen modelData
            readonly property bool deliberate: ScreensaverScreens.isBlanked(root.deliberateScreens, modelData.name)
            active: root.idleActive || screenLoader.deliberate

            sourceComponent: PanelWindow {
                id: saverWindow
                screen: screenLoader.modelData
                visible: true

                readonly property bool deliberate: screenLoader.deliberate

                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:screensaver"
                WlrLayershell.layer: WlrLayer.Overlay
                // The idle saver takes the keyboard so any key wakes it and no
                // keystroke leaks into whatever was focused. A deliberately
                // blanked monitor must not: the whole point is that the user
                // keeps typing on another screen, and an exclusive grab here
                // would swallow that and dismiss itself on the first letter.
                WlrLayershell.keyboardFocus: saverWindow.deliberate ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
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

                function dismiss(pointerMotion: bool): void {
                    if (!saverWindow.armed)
                        return;
                    // Motion alone does not take down a deliberate blank. The
                    // user chose it and then has to move the pointer off that
                    // monitor to get back to work, which is motion across this
                    // very surface; a click or the keybind is the way out.
                    if (pointerMotion && saverWindow.deliberate)
                        return;
                    if (saverWindow.deliberate)
                        root.hideOn(screenLoader.modelData.name);
                    GlobalStates.screensaverActive = false;
                }

                Item {
                    id: inputScope
                    anchors.fill: parent
                    focus: true

                    // Any input (once armed) dismisses; unloading resets the drift.
                    Keys.onPressed: saverWindow.dismiss(false)

                    ScreensaverContent {
                        anchors.fill: parent
                        mode: root.mode
                        active: root.idleActive || saverWindow.deliberate
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: saverWindow.dismiss(true)
                        onPressed: saverWindow.dismiss(false)
                    }
                }
            }
        }
    }

    // Deliberate, so it is not gated on screensaver.enable: that switch arms
    // the idle trigger in hypridle.conf, and swallowing a key the user just
    // pressed would be a silent no-op with nothing to explain it.
    GlobalShortcut {
        name: "screensaverToggleMonitor"
        description: "Blanks the focused monitor (OLED screensaver)"
        onPressed: root.toggleOn(Hyprland.focusedMonitor?.name ?? "")
    }

    IpcHandler {
        target: "screensaver"

        // The idle path. hypridle drives exactly these two and neither touches
        // the deliberate list, so neither takes an inhibitor.
        function show(): void {
            if (!(Config.options.screensaver?.enable ?? false))
                return;
            GlobalStates.screensaverActive = true;
        }

        function hide(): void {
            GlobalStates.screensaverActive = false;
            GlobalStates.screensaverScreens = [];
        }

        // The deliberate path.
        function toggle(): void {
            root.toggleAll();
        }

        function showMonitor(name: string): void {
            root.showOn(name);
        }

        function hideMonitor(name: string): void {
            root.hideOn(name);
        }

        function toggleMonitor(name: string): void {
            root.toggleOn(name);
        }
    }
}
