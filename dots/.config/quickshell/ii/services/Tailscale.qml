pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * Tailscale state and control (CLI-backed, like Vpn.qml is for nmcli).
 *
 * Detection is two-staged: `installed` (binary on PATH, checked once at
 * startup) gates everything else, and `available` (the daemon answered the
 * last `tailscale status --json` poll) tracks whether tailscaled is up.
 * UI should hide entirely when !installed and degrade when !available.
 *
 * Exposes the peers that advertise themselves as exit nodes and which one
 * (if any) is currently in use. Selecting one runs `tailscale set
 * --exit-node=…`; toggling runs `tailscale up` / `tailscale down`. On
 * machines where the user is not the Tailscale operator the plain command is
 * denied, so a failed command is retried once through `pkexec` (a polkit
 * prompt). Running `sudo tailscale set --operator=$USER` once makes it
 * seamless.
 *
 * Every invocation is built as an argv array; values are never spliced into
 * a shell string.
 */
Singleton {
    id: root

    readonly property int pollInterval: Config.options.networking?.tailscale?.pollInterval ?? 5000
    readonly property bool enableService: Config.options.networking?.tailscale?.enable ?? true

    property bool installed: false // tailscale binary found on PATH
    property bool available: false // daemon answered the last status poll
    property bool running: false // BackendState === "Running"
    property string backendState: ""
    property string currentExitNodeId: "" // stable ID of the active exit node, "" if none
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

    function refresh(): void {
        if (!root.enableService || !root.installed) return;
        statusProc.running = true;
    }

    function toggle(): void {
        root.runCommand(["tailscale", root.running ? "down" : "up"]);
    }

    function setExitNode(ip: string): void {
        if (!ip) return;
        root.runCommand(["tailscale", "set", `--exit-node=${ip}`, "--exit-node-allow-lan-access=true"]);
    }

    function clearExitNode(): void {
        root.runCommand(["tailscale", "set", "--exit-node="]);
    }

    // ---- command plumbing ----

    property var pendingCommand: []
    property bool triedPkexec: false

    function runCommand(argv: var): void {
        root.pendingCommand = argv;
        root.triedPkexec = false;
        cmdProc.exec(argv);
    }

    Process {
        id: cmdProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stderr: StdioCollector {
            id: cmdErr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.triedPkexec) {
                // Likely not the Tailscale operator: retry once through polkit.
                root.triedPkexec = true;
                cmdProc.exec(["pkexec", ...root.pendingCommand]);
                return;
            }
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Tailscale"),
                    cmdErr.text.trim() || Translation.tr("Tailscale command failed"),
                    "-a", "Shell"
                ]);
            }
            root.refresh();
        }
    }

    // One-shot presence check; everything else is gated on it.
    Process {
        id: whichProc
        running: root.enableService
        command: ["sh", "-c", "command -v tailscale"]
        onExited: (exitCode, exitStatus) => {
            root.installed = (exitCode === 0);
            if (root.installed) root.refresh();
        }
    }

    Process {
        id: statusProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
    }

    Timer {
        interval: root.pollInterval
        running: root.enableService && root.installed
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
