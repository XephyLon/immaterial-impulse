pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // Latest scan results as plain objects: { path: string, isDir: bool }
    property var results: []
    property string pendingQuery: ""
    property int searchId: 0

    readonly property bool enabled: Config.options.search.fileSearch?.enable ?? true
    readonly property int maxResults: Config.options.search.fileSearch?.maxResults ?? 20

    readonly property string searchRoot: {
        const configured = String(Config.options.search.fileSearch?.root ?? "").trim();
        return FileUtils.trimFileProtocol(configured.length > 0 ? configured : Directories.home);
    }

    // Fixed scan script. The user query, root and limit are passed as argv
    // positionals ($1, $2, $3) and are NEVER interpolated into the script text,
    // so there is no shell injection surface. Prefers fd, falls back to find.
    readonly property string scanScript: "if command -v fd >/dev/null 2>&1; then\n" +
        "  fd --hidden --type f --type d --color never --absolute-path --max-results \"$3\" -- \"$1\" \"$2\"\n" +
        "else\n" +
        "  find \"$2\" -iname \"*$1*\" 2>/dev/null | head -n \"$3\"\n" +
        "fi | while IFS= read -r p; do\n" +
        "  if [ -d \"$p\" ]; then printf 'd\\t%s\\n' \"$p\"; else printf 'f\\t%s\\n' \"$p\"; fi\n" +
        "done"

    function search(query) {
        const trimmed = String(query || "").trim();
        if (!root.enabled || trimmed.length < 2) {
            reset();
            return;
        }
        root.pendingQuery = trimmed;
        debounceTimer.restart();
    }

    function reset() {
        root.pendingQuery = "";
        if (scanProc.running)
            scanProc.running = false;
        if (root.results.length > 0)
            root.results = [];
    }

    function runSearch(query) {
        const trimmed = String(query || "").trim();
        if (!root.enabled || trimmed.length < 2) {
            reset();
            return;
        }
        if (scanProc.running)
            scanProc.running = false;
        root.searchId += 1;
        scanProc.runId = root.searchId;
        scanProc.buffer = [];
        scanProc.command = ["bash", "-c", root.scanScript, "fileSearch", trimmed, root.searchRoot, String(root.maxResults)];
        scanProc.running = true;
    }

    Timer {
        id: debounceTimer
        interval: Config.options.search.fileSearch?.delay ?? 150
        repeat: false
        onTriggered: root.runSearch(root.pendingQuery)
    }

    Process {
        id: scanProc
        property int runId: 0
        property var buffer: []

        stdout: SplitParser {
            onRead: line => {
                if (scanProc.runId !== root.searchId)
                    return;
                const raw = String(line || "");
                const tab = raw.indexOf("\t");
                if (tab < 0)
                    return;
                const path = raw.slice(tab + 1);
                if (path.length === 0)
                    return;
                if (scanProc.buffer.length >= root.maxResults)
                    return;
                scanProc.buffer.push({
                    path: path,
                    isDir: raw.slice(0, tab) === "d"
                });
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (scanProc.runId !== root.searchId)
                return;
            root.results = scanProc.buffer.slice();
        }
    }
}
