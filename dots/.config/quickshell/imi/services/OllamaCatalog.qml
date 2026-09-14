pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "./ai/ollama_library.js" as Library

/**
 * The local Ollama daemon as a model store: what is installed and loaded,
 * pulls with progress, removal, and the curated library snapshot the browse
 * view offers (docs/proposals/ollama-catalog.md).
 *
 * Talks to the daemon's HTTP API through curl, never to the `ollama` CLI:
 * /api/tags (installed), /api/ps (loaded), /api/pull (NDJSON progress, one
 * line per event), /api/delete. The only thing that starts the daemon is the
 * explicit startDaemon() behind a button. Refreshes only while a view says
 * it is looking (`watchers` > 0) - nothing here polls in the background.
 */
Singleton {
    id: root

    // IMI_OLLAMA_URL is the test seam (a fake daemon); OLLAMA_HOST is the
    // daemon's own convention (host:port, scheme optional).
    readonly property string baseUrl: {
        const override = Quickshell.env("IMI_OLLAMA_URL");
        if (override && override.length > 0) return override.replace(/\/+$/, "");
        let host = Quickshell.env("OLLAMA_HOST") || "";
        if (host.length === 0) return "http://127.0.0.1:11434";
        if (host.indexOf("://") === -1) host = "http://" + host;
        return host.replace(/0\.0\.0\.0/, "127.0.0.1").replace(/\/+$/, "");
    }

    property bool daemonUp: false
    property bool refreshing: false
    property string error: ""
    // [{ name, size, family, parameterSize, quantization, modifiedAt }]
    property var installed: []
    // Names currently loaded in memory (from /api/ps).
    property var running: []
    property real diskFreeBytes: -1
    readonly property var library: Library.MODELS
    readonly property string librarySnapshotDate: Library.SNAPSHOT_DATE

    // Pull state - one at a time.
    property string pullName: ""
    property string pullStatus: ""
    property real pullFraction: -1
    property string pullError: ""
    readonly property bool pulling: pullProc.running

    // Views count themselves in while shown; the refresh timer runs only then.
    property int watchers: 0

    function isInstalled(ref) {
        const target = String(ref ?? "");
        return root.installed.some(m => m.name === target || m.name === target + ":latest");
    }

    function refresh() {
        if (tagsProc.running) return;
        root.refreshing = true;
        tagsProc.running = true;
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.watchers > 0
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: tagsProc
        command: ["curl", "-sf", "-m", "4", `${root.baseUrl}/api/tags`]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(text ?? "").trim();
                if (raw.length === 0) {
                    root.daemonUp = false;
                    root.installed = [];
                    root.running = [];
                    root.refreshing = false;
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    root.installed = (parsed.models ?? []).map(m => ({
                        name: m.name ?? m.model ?? "",
                        size: Number(m.size) || 0,
                        family: m.details?.family ?? "",
                        parameterSize: m.details?.parameter_size ?? "",
                        quantization: m.details?.quantization_level ?? "",
                        modifiedAt: m.modified_at ?? ""
                    })).sort((a, b) => a.name.localeCompare(b.name));
                    root.daemonUp = true;
                    root.error = "";
                    psProc.running = true;
                    dfProc.running = true;
                } catch (e) {
                    root.daemonUp = false;
                    root.error = `Unreadable answer from ${root.baseUrl}/api/tags`;
                    root.refreshing = false;
                }
            }
        }
    }

    Process {
        id: psProc
        command: ["curl", "-sf", "-m", "4", `${root.baseUrl}/api/ps`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(String(text ?? "").trim() || "{}");
                    root.running = (parsed.models ?? []).map(m => m.name ?? m.model ?? "");
                } catch (e) {
                    root.running = [];
                }
                root.refreshing = false;
            }
        }
    }

    // Free space where the daemon stores models: OLLAMA_MODELS or ~/.ollama.
    Process {
        id: dfProc
        command: ["sh", "-c", `dir="\${OLLAMA_MODELS:-$HOME/.ollama}"; while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do dir="$(dirname "$dir")"; done; df -Pk "$dir" | awk 'NR==2 {print $4 * 1024}'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = Number(String(text ?? "").trim());
                root.diskFreeBytes = isNaN(n) ? -1 : n;
            }
        }
    }

    /** Starts a pull. Returns "" or the reason it did not start. */
    function pull(ref) {
        const name = String(ref ?? "").trim();
        if (name.length === 0) return "No model named";
        if (pullProc.running) return `Already pulling ${root.pullName}`;
        if (!root.daemonUp) return "Ollama is not running";
        root.pullName = name;
        root.pullStatus = "starting";
        root.pullFraction = -1;
        root.pullError = "";
        pullProc.command = ["curl", "-sN", "-X", "POST", `${root.baseUrl}/api/pull`,
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({ "model": name, "name": name, "stream": true })];
        pullProc.running = true;
        return "";
    }

    function cancelPull() {
        if (!pullProc.running) return;
        root.pullStatus = "cancelled";
        pullProc.running = false;
    }

    Process {
        id: pullProc
        stdout: SplitParser {
            onRead: line => {
                const trimmed = String(line ?? "").trim();
                if (trimmed.length === 0) return;
                try {
                    const event = JSON.parse(trimmed);
                    if (event.error) { root.pullError = String(event.error); return; }
                    root.pullStatus = String(event.status ?? root.pullStatus);
                    const fraction = Library.pullFraction(event);
                    if (fraction >= 0) root.pullFraction = fraction;
                } catch (e) { /* a partial line; the next one carries the state */ }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.pullStatus !== "cancelled") {
                if (root.pullError.length === 0 && exitCode !== 0)
                    root.pullError = `curl exited ${exitCode}`;
                if (root.pullError.length === 0) {
                    root.pullStatus = "success";
                    root.pullFraction = 1;
                }
            }
            root.refresh();
            root.pullFinished(root.pullName, root.pullError.length === 0 && root.pullStatus === "success");
        }
    }
    signal pullFinished(string name, bool ok)

    function remove(ref) {
        const name = String(ref ?? "").trim();
        if (name.length === 0 || deleteProc.running) return;
        deleteProc.command = ["curl", "-sf", "-m", "10", "-X", "DELETE", `${root.baseUrl}/api/delete`,
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({ "model": name, "name": name })];
        deleteProc.pending = name;
        deleteProc.running = true;
    }
    Process {
        id: deleteProc
        property string pending: ""
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            root.removed(deleteProc.pending, exitCode === 0);
        }
    }
    signal removed(string name, bool ok)

    // The one thing here that starts a process other than curl, behind a
    // button: the user's systemd unit, if there is one.
    property string startResult: ""
    function startDaemon() {
        if (startProc.running) return;
        root.startResult = "";
        startProc.running = true;
    }
    Process {
        id: startProc
        command: ["sh", "-c", "systemctl --user start ollama.service 2>&1 || systemctl start ollama.service 2>&1"]
        stdout: StdioCollector { onStreamFinished: root.startResult = String(text ?? "").trim() }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) { root.startResult = ""; startSettle.start(); }
            else if (root.startResult.length === 0) root.startResult = `systemctl exited ${exitCode}`;
        }
    }
    Timer { id: startSettle; interval: 1500; onTriggered: root.refresh() }
}
