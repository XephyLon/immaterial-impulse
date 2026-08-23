pragma Singleton

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Exposes Caps Lock and Num Lock state.
 * `ready` stays false until the first successful read so consumers can
 * ignore the initial state and only react to real toggles.
 *
 * The state comes from the keyboard's own LEDs under /sys/class/leds - the
 * kernel keeps those in sync with the seat's xkb state - read by ONE
 * long-lived bash loop using only builtins, which emits a line when either
 * value changes. This replaces forking `hyprctl devices -j` 3.3 times a
 * second and parsing the full devices dump for two booleans (no Hyprland
 * IPC event carries lock-key state, so some poll is unavoidable - but it
 * can be a poll that costs two opens instead of a fork+exec+JSON). The
 * hyprctl poll survives below as the fallback for a machine whose keyboard
 * exposes no LED nodes, picked the moment the watcher exits.
 */
Singleton {
    id: root

    property bool capsLockOn: false
    property bool numLockOn: false
    property bool ready: false
    property int pollInterval: 300
    property bool useFallback: false

    // The OSD was the only consumer when this was written, so the poll
    // was gated on the OSD's own switch. The on-screen keyboard draws
    // Caps and Num as latched keys now, and a user who turned the OSD off
    // would have had those two keys frozen at whatever they read when
    // the poll stopped - stale, and silently so. Watching while either
    // consumer is interested keeps one source of truth instead of growing
    // a second poller for the keyboard.
    readonly property bool watching: (Config.options.osd.lockKeys ?? true) || GlobalStates.oskOpen

    Process {
        id: ledWatcher
        running: root.watching && !root.useFallback
        // Globbing (not ls) and `read -t` on a self-held pipe (not sleep):
        // after startup the loop is pure bash builtins - two file opens per
        // tick, zero forks. `sleep` would have forked /usr/bin/sleep 3.3
        // times a second, which is the cost this watcher exists to remove.
        command: ["bash", "-c",
            'shopt -s nullglob; caps=(/sys/class/leds/*::capslock/brightness); ' +
            'num=(/sys/class/leds/*::numlock/brightness); ' +
            '[ ${#caps[@]} -gt 0 ] && [ ${#num[@]} -gt 0 ] || exit 1; ' +
            'CAPS=${caps[0]}; NUM=${num[0]}; ' +
            'exec 3<> <(:); last=""; while :; do ' +
            'read c < "$CAPS" 2>/dev/null || exit 1; ' +
            'read n < "$NUM" 2>/dev/null || exit 1; ' +
            'cur="$c $n"; if [ "$cur" != "$last" ]; then echo "$cur"; last="$cur"; fi; ' +
            'read -t 0.3 -u 3 || :; done']
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ");
                if (parts.length !== 2)
                    return;
                // Set the values before flagging readiness so the very first
                // read never triggers an OSD on startup.
                root.capsLockOn = parts[0] !== "0";
                root.numLockOn = parts[1] !== "0";
                root.ready = true;
            }
        }
        // No LED nodes (exit 1 up front) or a keyboard unplug mid-watch:
        // fall back to hyprctl for the rest of the session rather than
        // respawning a loop that will just exit again.
        onExited: (exitCode, exitStatus) => {
            if (root.watching)
                root.useFallback = true;
        }
    }

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
                    // Same ordering rule as the LED path above.
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
        running: root.watching && root.useFallback
        repeat: true
        triggeredOnStart: true
        onTriggered: devicesProc.running = true
    }
}
