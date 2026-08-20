pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Which physical keys are held down, for the on-screen keyboard to draw.
 *
 * The OSK shows what it types; this is what lets it also show what the real
 * keyboard is doing. `scripts/keyboard/key_monitor.py` reads /dev/input and
 * prints one keycode per event - the same evdev codes the OSK's own keys carry
 * for ydotool, so a code off the wire lines up with a drawn key directly.
 *
 * IT RUNS ONLY WHILE THE OSK IS ON SCREEN. `watching` is the OSK's own open
 * state, and nothing else may set it: a reader of every key on the machine is
 * a keylogger unless its lifetime is exactly the window in which the user
 * asked to see their keys drawn. It also holds no history - `pressed` is what
 * is DOWN, and a key leaves the set the moment it comes up - and it carries
 * keycodes rather than characters, so nothing here knows what was typed.
 *
 * Feature-detected the way Clight and Tailscale are: reading /dev/input needs
 * membership of the `input` group and nothing else, and a machine without it
 * gets `available: false` and an OSK that simply does not highlight. The shell
 * asks for no privilege it does not already have.
 */
Singleton {
    id: root

    // The one condition. Bound to the OSK's open state rather than settable,
    // because a second writer is a second answer to "may we read the keyboard
    // right now" and the wrong answer is a process nobody remembers starting.
    readonly property bool watching: GlobalStates.oskOpen
        && (Config.options.osk?.showPhysicalKeys ?? true)

    // Keycodes currently down. A set spelled as a map: a key can repeat, two
    // keyboards can hold the same code, and both must leave exactly one entry.
    property var pressed: ({})
    // Whether the last start found a device it could read. False on a machine
    // whose user is not in the `input` group, which is the common case and not
    // an error.
    property bool available: false
    property int deviceCount: 0

    function isDown(code): bool {
        return root.pressed[code] === true;
    }

    onWatchingChanged: {
        if (root.watching) {
            monitor.running = true;
            return;
        }
        monitor.running = false;
        // Cleared on the way down, not the way up: a key still held when the
        // OSK closes would otherwise be drawn as held the next time it opens,
        // and the release that would have cleared it went to a process that no
        // longer exists.
        root.pressed = ({});
    }

    Process {
        id: monitor
        running: false
        command: ["python3", `${Directories.scriptPath}/keyboard/key_monitor.py`]
        // No `running:` binding and no restart on exit: this is not a service
        // that must stay up. It is started by a user gesture and stopped by
        // the matching one, so a crashed reader means no highlighting until
        // the OSK is reopened - which is the failure this should have, rather
        // than a respawn loop reading the keyboard forever.
        onExited: (code, status) => {
            root.available = false;
            root.deviceCount = 0;
            root.pressed = ({});
        }
        stdout: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (text.length === 0) return;
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    return;
                }
                if (parsed.state === "watching") {
                    root.available = true;
                    root.deviceCount = parsed.devices ?? 0;
                    return;
                }
                if (parsed.state === "unavailable") {
                    root.available = false;
                    return;
                }
                if (typeof parsed.code !== "number") return;
                // Copy-on-write: a `property var` notifies on reassignment
                // only, so mutating the map in place would light a key and
                // never tell anything drawing it.
                const next = Object.assign({}, root.pressed);
                if (parsed.down === 1) next[parsed.code] = true;
                else delete next[parsed.code];
                root.pressed = next;
            }
        }
    }
}
