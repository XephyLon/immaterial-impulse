import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Handles EasyEffects active state and presets.
 */
Singleton {
    id: root

    property bool available: false
    property bool active: false
    // How long a spawned daemon gets to appear (or a killed one to exit)
    // before the optimistic flip below is checked against reality. A test
    // shortens it; nothing else should.
    property int verifyInterval: 1500

    function fetchAvailability() {
        fetchAvailabilityProc.running = true
    }

    function fetchActiveState() {
        fetchActiveStateProc.running = true
    }

    // enable()/disable() flip `active` optimistically so the toggle answers
    // the click, then verify against the real process list once the launch or
    // kill has had time to happen - without that, a failed launch (easyeffects
    // uninstalled between checks, or crashing at startup) left the toggle
    // saying on for the rest of the session.
    function disable() {
        root.active = false
        Quickshell.execDetached(["bash", "-c", "pkill easyeffects || flatpak pkill com.github.wwmm.easyeffects"])
        verifyTimer.restart()
    }

    function enable() {
        root.active = true
        Quickshell.execDetached(["bash", "-c", "easyeffects --hide-window --service-mode || flatpak run com.github.wwmm.easyeffects --hide-window --service-mode"])
        verifyTimer.restart()
    }

    Timer {
        id: verifyTimer
        interval: root.verifyInterval
        onTriggered: root.fetchActiveState()
    }

    function toggle() {
        if (root.active) {
            root.disable()
        } else {
            root.enable()
        }
    }

    Process {
        id: fetchAvailabilityProc
        running: true
        command: ["bash", "-c", "command -v easyeffects || flatpak info com.github.wwmm.easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0
        }
    }

    Process {
        id: fetchActiveStateProc
        running: true
        command: ["bash", "-c", "pidof easyeffects || flatpak ps | grep com.github.wwmm.easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.active = exitCode === 0
        }
    }
}
