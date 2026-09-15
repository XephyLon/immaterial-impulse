pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Proton VPN through the official app's session
 * (scripts/accounts/protonvpn_ctl.py over python-proton-vpn-api-core).
 *
 * Detection is two-staged like Tailscale: `installed` (the Python package
 * imports) gates everything, `loggedIn` (the app has a session in the
 * keyring) gates the controls. The shell never sees the Proton password.
 * Every poll is a Python process, so the default cadence is gentler than
 * nmcli's; a NetworkManager event reconciles sooner. The connection the app
 * makes is still a NetworkManager profile, so Vpn.qml lists it as well.
 */
Singleton {
    id: root

    readonly property bool enableService: Config.options.accounts?.proton?.vpn?.enable ?? true
    readonly property int pollInterval: Config.options.accounts?.proton?.vpn?.pollInterval ?? 10000
    readonly property string helperPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/accounts/protonvpn_ctl.py`)

    property bool probed: false
    property bool installed: false
    property bool loggedIn: false
    property string state: "" // Disconnected | Connecting | Connected | Disconnecting | Error
    property string server: ""
    property string country: ""
    property string account: ""
    property bool busy: false
    property string lastError: ""

    readonly property bool available: root.installed && root.loggedIn
    readonly property bool connected: root.state === "Connected"
    readonly property bool transitioning: root.busy || root.state === "Connecting" || root.state === "Disconnecting"
    readonly property string materialSymbol: root.connected ? "vpn_lock" : "vpn_key_off"

    // Parses one status line from the helper. Returns null for anything that
    // is not a status document.
    function parseStatus(text) {
        let parsed = null;
        try { parsed = JSON.parse(String(text).trim().split("\n").pop()); } catch (e) { return null; }
        if (!parsed || typeof parsed !== "object" || !("installed" in parsed)) return null;
        return {
            installed: parsed.installed === true,
            loggedIn: parsed.logged_in === true,
            state: String(parsed.state ?? ""),
            server: String(parsed.server ?? ""),
            country: String(parsed.country ?? ""),
            account: String(parsed.account ?? ""),
        };
    }

    function applyStatus(text) {
        const s = root.parseStatus(text);
        root.probed = true;
        if (!s) return;
        root.installed = s.installed;
        root.loggedIn = s.loggedIn;
        root.state = s.state;
        root.server = s.server;
        root.country = s.country;
        root.account = s.account;
    }

    function refresh() {
        if (!root.enableService || statusProc.running) return;
        statusProc.running = true;
    }

    function connect(countryCode) {
        root.run(countryCode ? ["connect", String(countryCode)] : ["connect"]);
    }

    function disconnect() {
        root.run(["disconnect"]);
    }

    function toggle() {
        if (root.connected || root.state === "Connecting") root.disconnect();
        else root.connect("");
    }

    function run(args) {
        if (!root.available || root.busy) return;
        root.busy = true;
        root.lastError = "";
        cmdProc.command = ["python3", root.helperPath, ...args];
        cmdProc.running = true;
    }

    Process {
        id: cmdProc
        stdout: StdioCollector { id: cmdOut }
        onExited: (code, status) => {
            root.busy = false;
            let parsed = null;
            try { parsed = JSON.parse(cmdOut.text.trim().split("\n").pop()); } catch (e) { parsed = null; }
            if (code !== 0) {
                root.lastError = parsed?.error ?? parsed?.state ?? "Proton VPN command failed";
                Quickshell.execDetached(["notify-send", Translation.tr("Proton VPN"), root.lastError, "-a", "Shell"]);
            }
            root.refresh();
        }
    }

    // The status probe doubles as the presence check: the helper answers
    // {"installed": false} without the package, so it starts on its own.
    Process {
        id: statusProc
        running: root.enableService
        command: ["python3", root.helperPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
    }

    Timer {
        interval: root.pollInterval
        running: root.enableService && root.installed
        repeat: true
        onTriggered: root.refresh()
    }

    // Reconcile on NetworkManager's events (Vpn.qml piggybacks the same way).
    Connections {
        target: Network
        function onMonitorEvent() { if (root.available) root.refresh(); }
    }
}
