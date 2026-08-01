pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/Vpn.qml. parseConnections() and the derived
// state properties are kept byte-for-byte in sync with the real service; the
// nmcli Process/Timer I/O is omitted so tests stay deterministic and offline.
Singleton {
    id: root

    // [{ name: string, active: bool }]
    property var connections: []
    readonly property var activeConnections: root.connections.filter(c => c.active)
    readonly property bool anyActive: root.connections.some(c => c.active)
    readonly property string materialSymbol: root.anyActive ? "vpn_lock" : "vpn_key"

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
}
