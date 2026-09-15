pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Proton VPN through the official app's session
 * (scripts/accounts/protonvpn_ctl.py over python-proton-vpn-api-core).
 *
 * Detection is two-staged like Tailscale: `installed` asks whether the
 * Python package is importable (find_spec, importing nothing), and
 * `loggedIn` (the app has a session in the keyring) gates the controls.
 * The shell never sees the Proton password.
 *
 * Every status read is a Python process (~0.5 s, ~47 MB), so it is not a
 * background poll: it runs only while something is looking - the quick
 * panel (the right sidebar open) or a page that acquired it - on a slow
 * reconcile tick, and once more, debounced, after a NetworkManager event
 * (the app's connection is a NetworkManager profile, so that event IS the
 * transition). The profile is also listed by Vpn.qml, so nothing regresses.
 */
Singleton {
    id: root

    readonly property bool enableService: Config.options.accounts?.proton?.vpn?.enable ?? true
    readonly property int pollInterval: Config.options.accounts?.proton?.vpn?.pollInterval ?? 60000
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
    property bool everRead: false

    // Who is looking: the right sidebar (the quick-panel tile) and pages
    // that call acquire()/release() while shown.
    property int watchers: 0
    readonly property bool watched: root.watchers > 0 || GlobalStates.sidebarRightOpen
    function acquire() { root.watchers += 1; }
    function release() { root.watchers = Math.max(0, root.watchers - 1); }

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
        root.everRead = true;
        if (!s) return;
        root.installed = s.installed;
        root.loggedIn = s.loggedIn;
        root.state = s.state;
        root.server = s.server;
        root.country = s.country;
        root.account = s.account;
    }

    function refresh() {
        if (!root.enableService || !root.installed || statusProc.running) return;
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
        onExited: (code, exitStatus) => {
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

    // Presence: whether the package is importable, wherever this distro
    // puts it (dist-packages, a user site, a venv) - find_spec imports
    // nothing, ~40 ms once per session against the 470 ms read it gates.
    // Starts on its own (capability probe gating).
    Process {
        id: presenceProc
        running: root.enableService
        command: ["python3", "-c", "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('proton.vpn.core.api') else 1)"]
        onExited: (code, exitStatus) => {
            root.installed = (code === 0);
            root.probed = true;
        }
    }

    // The status read. Started only by refresh(); never a `running:` binding
    // beside an assignment (the assignment would destroy the binding).
    Process {
        id: statusProc
        command: ["python3", root.helperPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
    }

    // The slow reconcile, only while someone is looking.
    Timer {
        interval: root.pollInterval
        running: root.enableService && root.installed && root.watched
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // A NetworkManager event is the transition itself; one debounced read,
    // only while someone is looking (the tile is not on screen to show the
    // result otherwise; the reconcile tick's triggeredOnStart reads fresh
    // state the moment someone looks again).
    Timer {
        id: nmDebounce
        interval: 2000
        repeat: false
        onTriggered: root.refresh()
    }
    Connections {
        target: Network
        function onMonitorEvent() { if (root.watched && root.installed && root.everRead) nmDebounce.restart(); }
    }
}
