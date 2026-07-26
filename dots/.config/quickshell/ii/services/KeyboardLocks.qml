pragma Singleton

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Exposes Caps Lock and Num Lock state by polling `hyprctl devices`.
 * `ready` stays false until the first successful read so consumers can
 * ignore the initial state and only react to real toggles.
 */
Singleton {
    id: root

    property bool capsLockOn: false
    property bool numLockOn: false
    property bool ready: false
    property int pollInterval: 300

    Process {
        id: devicesProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    if (!data.keyboards || data.keyboards.length === 0)
                        return;
                    const keyboard = data.keyboards.find(k => k.main === true) ?? data.keyboards[0];
                    // Set the values before flagging readiness so the very first
                    // read never triggers an OSD on startup.
                    root.capsLockOn = keyboard.capsLock;
                    root.numLockOn = keyboard.numLock;
                    root.ready = true;
                } catch (e) {
                    console.log("[KeyboardLocks] Parse error:", e);
                }
            }
        }
    }

    Timer {
        interval: root.pollInterval
        running: Config.options.osd.lockKeys ?? true
        repeat: true
        triggeredOnStart: true
        onTriggered: devicesProc.running = true
    }
}
