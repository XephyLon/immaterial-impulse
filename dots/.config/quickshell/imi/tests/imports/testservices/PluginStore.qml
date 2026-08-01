pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/PluginStore.qml. compareVersions(),
// parseIndex() and statusFor() are kept byte-for-byte in sync with the real
// service (pinned by test_plugin_store_contract.py); the curl/cache Process
// wiring and the PluginManager coupling are omitted so tests stay
// deterministic and offline.
Singleton {
    id: root

    property var entries: []
    property string lastError: ""

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
}
