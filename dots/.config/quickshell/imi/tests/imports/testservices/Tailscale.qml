pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/Tailscale.qml. firstIpv4()/parseStatus() and
// the derived state properties are kept byte-for-byte in sync with the real
// service; the CLI Process/Timer I/O is omitted so tests stay deterministic
// and offline.
Singleton {
    id: root

    property bool installed: false
    property bool available: false
    property bool running: false
    property string backendState: ""
    property string currentExitNodeId: ""
    // [{ id: string, name: string, ip: string, online: bool, active: bool }]
    property var exitNodes: []

    readonly property bool exitNodeActive: root.currentExitNodeId.length > 0
    readonly property string currentExitNodeName: root.exitNodes.find(n => n.active)?.name ?? ""
    readonly property string materialSymbol: !root.running ? "vpn_key_off" : root.exitNodeActive ? "vpn_lock" : "vpn_key"

    // Prefer the IPv4 address (cleaner for `--exit-node=`), fall back to the first.
    function firstIpv4(ips: var): string {
        if (!ips || ips.length === 0) return "";
        for (const ip of ips) {
            const bare = ip.split("/")[0];
            if (!bare.includes(":")) return bare;
        }
        return ips[0].split("/")[0];
    }

    // Parses `tailscale status --json`. Returns null when the text is not a
    // status document (empty output, daemon down, malformed JSON); otherwise
    // { backendState, running, currentExitNodeId, exitNodes } with exit-node
    // peers sorted online-first then alphabetically.
    function parseStatus(text: string): var {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0) return null;
        let data;
        try {
            data = JSON.parse(trimmed);
        } catch (e) {
            return null;
        }
        if (!data || typeof data !== "object") return null;
        const backendState = data.BackendState ?? "";
        const exitId = data.ExitNodeStatus?.ID ?? "";
        const peers = data.Peer ?? {};
        const nodes = [];
        for (const key in peers) {
            const p = peers[key];
            if (!p?.ExitNodeOption) continue;
            const name = (p.HostName && p.HostName.length > 0) ? p.HostName : (p.DNSName ?? "").split(".")[0];
            nodes.push({
                id: p.ID ?? "",
                name: name,
                ip: root.firstIpv4(p.TailscaleIPs),
                online: p.Online ?? false,
                active: (p.ExitNode === true) || (exitId.length > 0 && p.ID === exitId)
            });
        }
        nodes.sort((a, b) => {
            if (a.online !== b.online) return a.online ? -1 : 1;
            return a.name.localeCompare(b.name);
        });
        // ExitNodeStatus can lag behind the per-peer ExitNode flag; trust either.
        let currentId = exitId;
        if (currentId.length === 0) currentId = nodes.find(n => n.active)?.id ?? "";
        return {
            backendState: backendState,
            running: backendState === "Running",
            currentExitNodeId: currentId,
            exitNodes: nodes
        };
    }

    function applyStatus(text: string): void {
        const status = root.parseStatus(text);
        if (status === null) {
            root.available = false;
            root.running = false;
            root.backendState = "";
            root.currentExitNodeId = "";
            root.exitNodes = [];
            return;
        }
        root.available = true;
        root.backendState = status.backendState;
        root.running = status.running;
        root.currentExitNodeId = status.currentExitNodeId;
        root.exitNodes = status.exitNodes;
    }
}
