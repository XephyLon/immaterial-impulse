pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * VPN service backed by NetworkManager (nmcli).
 * Lists NM connections whose type is a VPN (vpn / wireguard) and can toggle them.
 *
 * Every nmcli invocation is built as an argv array; connection names are never
 * spliced into a shell string, so names containing spaces, quotes or `;` stay safe.
 */
Singleton {
    id: root

    readonly property int pollInterval: Config.options.networking?.vpn?.pollInterval ?? 5000
    readonly property bool enableService: Config.options.networking?.vpn?.enable ?? true

    // [{ name: string, active: bool }]
    property var connections: []
    readonly property var activeConnections: root.connections.filter(c => c.active)
    readonly property bool anyActive: root.connections.some(c => c.active)
    readonly property string materialSymbol: root.anyActive ? "vpn_lock" : "vpn_key"

    // Parses `nmcli -t -f NAME,TYPE,ACTIVE con show`. The trailing two fields
    // (TYPE, ACTIVE) never contain colons, so everything before them is the NAME;
    // nmcli escapes any literal colon inside NAME as "\:", which we unescape.
    function parseConnections(text: string): var {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0) return [];
        const result = [];
        for (const raw of trimmed.split("\n")) {
            const parts = raw.split(":");
            if (parts.length < 3) continue;
            const active = parts[parts.length - 1] === "yes";
            const type = parts[parts.length - 2];
            if (!/vpn|wireguard/i.test(type)) continue;
            const name = parts.slice(0, parts.length - 2).join(":").replace(/\\:/g, ":");
            if (name.length === 0) continue;
            result.push({ name: name, active: active });
        }
        return result;
    }

    function refresh(): void {
        if (!root.enableService) return;
        listProc.running = true;
    }

    function setConnectionActive(name: string, active: bool): void {
        if (!name) return;
        toggleProc.exec(["nmcli", "con", active ? "up" : "down", "id", name]);
    }

    function toggleConnection(connection: var): void {
        if (!connection) return;
        setConnectionActive(connection.name, !connection.active);
    }

    function deactivateAll(): void {
        for (const c of root.activeConnections)
            setConnectionActive(c.name, false);
    }

    Timer {
        interval: root.pollInterval
        running: root.enableService
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Refresh immediately on any NetworkManager event, with the timer as a fallback.
    Process {
        id: monitor
        running: root.enableService
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.refresh()
        }
    }

    Process {
        id: listProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "con", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.connections = root.parseConnections(text)
        }
    }

    Process {
        id: toggleProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stderr: StdioCollector {
            id: toggleErr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("VPN"),
                    toggleErr.text.trim() || Translation.tr("Failed to toggle VPN connection"),
                    "-a", "Shell"
                ]);
            }
            root.refresh();
        }
    }
}
