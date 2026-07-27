pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.plugins
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Plugin store client: fetches the official registry index, caches it on
 * disk so the store page renders offline, and merges it against the
 * installed/bundled plugin state from PluginManager into per-entry statuses
 * ("installed" | "update" | "bundled" | "incompatible" | "available").
 *
 * The index URL is a constant - it is never built from user input - and
 * every process invocation is an argv array; values are never spliced into
 * a shell string. A fetch downloads to a temp file and atomically renames
 * it over the cache so readers never see a torn index. A failed fetch or a
 * malformed index sets lastError and keeps the last good entries.
 *
 * install()/upgrade() delegate to PluginManager's hardened installer
 * pipeline (HTTPS-only, same-origin, size caps, atomic staging); the store
 * is a catalog and UX layer on top of it, not a second install path.
 */
Singleton {
    id: root

    // Official registry index. Constant and https-only.
    readonly property string indexUrl: "https://raw.githubusercontent.com/XephyLon/imi-plugin-registry/main/index.json"

    property var entries: []
    property string lastError: ""
    readonly property bool fetching: mkdirProc.running || curlProc.running || mvProc.running

    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/plugin-store`)
    readonly property string cachePath: `${root.cacheDir}/index.json`
    // curl writes here; a successful fetch renames this over cachePath.
    readonly property string tmpPath: `${root.cacheDir}/index.json.part`
    readonly property int cacheMaxAgeSeconds: 24 * 60 * 60

    // Shell version, read from the VERSION file like the About page does.
    property string shellVersion: "0.0.0"

    // { id: { version, origin } } for every user-installed plugin. The
    // manifest's own version wins; the provenance sidecar's recorded
    // installedVersion is the fallback for manifests without one.
    readonly property var installedMap: {
        const map = {};
        for (const plugin of PluginManager.availablePlugins) {
            if (plugin._origin !== "installed")
                continue;
            map[plugin.id] = {
                version: plugin.version ?? plugin._store?.installedVersion ?? "",
                origin: plugin._origin
            };
        }
        return map;
    }

    readonly property var bundledIds: PluginManager.availablePlugins
        .filter(plugin => plugin._origin === "bundled")
        .map(plugin => plugin.id)

    // Count for the update badge on the Plugins page navigation.
    readonly property int updatesAvailable: root.entries
        .filter(entry => root.statusForEntry(entry) === "update").length

    // Referenced from shell.qml-style startup hooks if ever needed; today the
    // store page instantiates this singleton lazily on first reference.
    function load() {}

    // Pure: -1 / 0 / 1; dotted numeric segments, missing = 0; a non-numeric
    // segment falls back to string compare of that segment.
    function compareVersions(a, b) {
        const as = String(a ?? "").split("."), bs = String(b ?? "").split(".");
        const n = Math.max(as.length, bs.length);
        for (let i = 0; i < n; i++) {
            const ra = as[i] ?? "0", rb = bs[i] ?? "0";
            const na = Number(ra), nb = Number(rb);
            if (Number.isFinite(na) && Number.isFinite(nb)) {
                if (na !== nb) return na < nb ? -1 : 1;
            } else if (ra !== rb) {
                return ra < rb ? -1 : 1;
            }
        }
        return 0;
    }

    // Pure: parses registry index text into { entries: [...], error: string|null }.
    // Never throws. Rejects an index whose schema version is unknown; drops
    // malformed entries (missing/empty id, name or version, or a manifestUrl
    // that is not https) while keeping the good ones; coerces missing
    // capabilities/permissions/tags to []; keeps unknown fields verbatim.
    function parseIndex(text) {
        let data;
        try {
            data = JSON.parse(String(text ?? ""));
        } catch (e) {
            return { entries: [], error: "Registry index is not valid JSON" };
        }
        if (!data || typeof data !== "object" || Array.isArray(data))
            return { entries: [], error: "Registry index is not an object" };
        if (data.version !== 1)
            return { entries: [], error: `Unsupported registry index version: ${data.version}` };
        if (!Array.isArray(data.plugins))
            return { entries: [], error: "Registry index has no plugins array" };
        const entries = [];
        for (const raw of data.plugins) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw))
                continue;
            let malformed = false;
            for (const field of ["id", "name", "version"]) {
                if (typeof raw[field] !== "string" || raw[field].length === 0)
                    malformed = true;
            }
            if (typeof raw.manifestUrl !== "string" || !raw.manifestUrl.startsWith("https://"))
                malformed = true;
            if (malformed)
                continue;
            const entry = Object.assign({}, raw);
            for (const field of ["capabilities", "permissions", "tags"]) {
                if (!Array.isArray(entry[field]))
                    entry[field] = [];
            }
            entries.push(entry);
        }
        return { entries: entries, error: null };
    }

    // Pure: "installed" | "update" | "bundled" | "incompatible" | "available".
    // installedMap: { id: { version, origin } }, bundledIds: [..],
    // shellApi: int, shellVersion: "x.y.z".
    function statusFor(entry, installedMap, bundledIds, shellApi, shellVersion) {
        if (bundledIds.includes(entry.id)) return "bundled";
        if ((entry.apiVersion ?? 1) > shellApi) return "incompatible";
        if (entry.minShellVersion && compareVersions(shellVersion, entry.minShellVersion) < 0) return "incompatible";
        const inst = installedMap[entry.id];
        if (!inst) return "available";
        return compareVersions(entry.version, inst.version) > 0 ? "update" : "installed";
    }

    // Convenience over statusFor() using live PluginManager + shell state.
    function statusForEntry(entry) {
        return root.statusFor(entry, root.installedMap, root.bundledIds,
            PluginManager.apiVersion, root.shellVersion);
    }

    function install(entry) {
        return PluginManager.installFromManifest(entry?.manifestUrl ?? "");
    }

    function upgrade(entry) {
        return PluginManager.upgradeFromManifest(entry?.manifestUrl ?? "");
    }

    function refresh() {
        if (root.fetching)
            return;
        mkdirProc.running = true;
    }

    // Fetch only when the on-disk cache is missing or older than 24h; the
    // store page calls this on open so a fresh cache costs nothing.
    function refreshIfStale() {
        if (root.fetching || staleProc.running)
            return;
        staleProc.running = true;
    }

    function applyIndexText(text) {
        const result = root.parseIndex(text);
        if (result.error !== null) {
            root.lastError = result.error;
            return; // Keep the last good entries.
        }
        root.entries = result.entries;
        root.lastError = "";
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.cacheDir]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.lastError = "Could not create the plugin store cache directory";
                return;
            }
            curlProc.running = true;
        }
    }

    Process {
        id: curlProc
        // Constant argv plus own-element paths - nothing is shell-spliced.
        command: ["curl", "-sfL", "--max-time", "15", "-o", root.tmpPath, root.indexUrl]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.lastError = `Registry fetch failed (curl exit ${exitCode})`;
                return;
            }
            mvProc.running = true;
        }
    }

    Process {
        id: mvProc
        // Atomic publish: readers only ever see the old or the new index.
        command: ["mv", "-f", root.tmpPath, root.cachePath]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.lastError = "Could not store the fetched registry index";
                return;
            }
            cacheView.reload();
        }
    }

    Process {
        id: staleProc
        command: ["stat", "-c", "%Y", root.cachePath]
        stdout: StdioCollector {
            id: staleOutput
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.refresh(); // No cache yet.
                return;
            }
            const mtime = parseInt(staleOutput.text.trim(), 10);
            if (!Number.isFinite(mtime) || Date.now() / 1000 - mtime > root.cacheMaxAgeSeconds)
                root.refresh();
        }
    }

    // Loads the cached index at startup so the store renders offline; a
    // missing cache simply never fires onLoaded.
    FileView {
        id: cacheView
        path: root.cachePath
        onLoaded: root.applyIndexText(cacheView.text())
    }

    FileView {
        id: versionFile
        path: Qt.resolvedUrl(Quickshell.shellPath("VERSION"))
        onLoaded: {
            const v = (versionFile.text() || "").trim();
            if (v.length > 0)
                root.shellVersion = v;
        }
    }
}
