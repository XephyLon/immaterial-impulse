import QtQuick
import QtTest
import testservices

// Behavioral tests for the pure logic in services/PluginStore.qml, driven
// through the logic-only double in tests/imports/testservices/PluginStore.qml
// (kept in sync by test_plugin_store_contract.py).
TestCase {
    name: "PluginStoreTest"

    // A well-formed registry entry; individual tests clone and break it.
    function goodEntry(overrides) {
        const entry = {
            id: "pomodoroTimer",
            name: "Pomodoro Timer",
            description: "A desktop pomodoro timer widget",
            author: "somebody",
            version: "1.2.0",
            apiVersion: 1,
            capabilities: ["desktop-widget"],
            permissions: ["settings_read"],
            manifestUrl: "https://raw.githubusercontent.com/somebody/imi-pomodoro/v1.2.0/manifest.json",
            tags: ["productivity"]
        };
        return Object.assign(entry, overrides ?? {});
    }

    function indexText(plugins, version) {
        return JSON.stringify({
            version: version ?? 1,
            generatedAt: "2026-07-27T00:00:00Z",
            source: "official",
            plugins: plugins
        });
    }

    function test_compare_versions_ordering() {
        compare(PluginStore.compareVersions("1.2.0", "1.1.9"), 1);
        compare(PluginStore.compareVersions("1.1.9", "1.2.0"), -1);
        // Numeric segment compare, not lexicographic: 10 > 9.
        compare(PluginStore.compareVersions("1.10.0", "1.9.0"), 1);
        compare(PluginStore.compareVersions("1.9.0", "1.10.0"), -1);
        compare(PluginStore.compareVersions("1.2.0", "1.2.0"), 0);
        // Missing segments count as 0.
        compare(PluginStore.compareVersions("1.2", "1.2.0"), 0);
        compare(PluginStore.compareVersions("1.2.0", "1.2"), 0);
        compare(PluginStore.compareVersions("1.2", "1.2.1"), -1);
        // Null/undefined degrade to "" (= 0.0.0), never throw.
        compare(PluginStore.compareVersions(null, "0.0.0"), 0);
        compare(PluginStore.compareVersions(undefined, "0.0.1"), -1);
    }

    function test_compare_versions_non_numeric_fallback() {
        // Non-numeric segments fall back to string comparison.
        compare(PluginStore.compareVersions("1.0.beta", "1.0.alpha"), 1);
        compare(PluginStore.compareVersions("1.0.alpha", "1.0.beta"), -1);
        compare(PluginStore.compareVersions("1.0.alpha", "1.0.alpha"), 0);
        // Mixed numeric/non-numeric in the same position: string compare.
        compare(PluginStore.compareVersions("1.0.alpha", "1.0.2"), 1);
    }

    function test_parse_index_valid() {
        const second = goodEntry({
            id: "weatherBar",
            name: "Weather Bar",
            version: "0.3.1",
            manifestUrl: "https://example.com/weather/manifest.json",
            featured: true
        });
        const result = PluginStore.parseIndex(indexText([goodEntry(), second]));
        compare(result.error, null);
        compare(result.entries.length, 2);
        compare(result.entries[0].id, "pomodoroTimer");
        compare(result.entries[1].id, "weatherBar");
        // Unknown fields are kept verbatim.
        compare(result.entries[1].featured, true);
    }

    function test_parse_index_garbage_text() {
        const result = PluginStore.parseIndex("this is not json {{");
        verify(result.error !== null);
        compare(result.entries.length, 0);
    }

    function test_parse_index_rejects_unknown_version() {
        const result = PluginStore.parseIndex(indexText([goodEntry()], 2));
        verify(result.error !== null);
        compare(result.entries.length, 0);
    }

    function test_parse_index_rejects_non_object_and_missing_plugins() {
        verify(PluginStore.parseIndex("[1, 2, 3]").error !== null);
        verify(PluginStore.parseIndex("42").error !== null);
        verify(PluginStore.parseIndex(JSON.stringify({ version: 1 })).error !== null);
        verify(PluginStore.parseIndex(null).error !== null);
    }

    function test_parse_index_drops_malformed_entries_keeps_good() {
        const plugins = [
            goodEntry(),
            goodEntry({ id: "noName", name: "" }),         // empty name
            goodEntry({ id: "noVersion", version: null }),  // missing version
            { id: "bare" },                                  // missing everything else
            "not even an object",
            goodEntry({ id: "survivor", name: "Survivor" })
        ];
        const result = PluginStore.parseIndex(indexText(plugins));
        compare(result.error, null);
        compare(result.entries.map(e => e.id), ["pomodoroTimer", "survivor"]);
    }

    function test_parse_index_drops_http_manifest_url() {
        const plugins = [
            goodEntry({ id: "insecure", manifestUrl: "http://example.com/manifest.json" }),
            goodEntry()
        ];
        const result = PluginStore.parseIndex(indexText(plugins));
        compare(result.error, null);
        compare(result.entries.map(e => e.id), ["pomodoroTimer"]);
    }

    function test_parse_index_coerces_missing_arrays() {
        const entry = goodEntry();
        delete entry.capabilities;
        delete entry.permissions;
        delete entry.tags;
        const result = PluginStore.parseIndex(indexText([entry]));
        compare(result.error, null);
        compare(result.entries[0].capabilities, []);
        compare(result.entries[0].permissions, []);
        compare(result.entries[0].tags, []);
    }

    function test_status_available() {
        compare(PluginStore.statusFor(goodEntry(), {}, [], 1, "0.1.0"), "available");
    }

    function test_status_installed_equal_version() {
        const installed = { pomodoroTimer: { version: "1.2.0", origin: "installed" } };
        compare(PluginStore.statusFor(goodEntry(), installed, [], 1, "0.1.0"), "installed");
        // Installed version newer than the registry's is still "installed".
        const newer = { pomodoroTimer: { version: "1.3.0", origin: "installed" } };
        compare(PluginStore.statusFor(goodEntry(), newer, [], 1, "0.1.0"), "installed");
    }

    function test_status_update_on_greater_registry_version() {
        const installed = { pomodoroTimer: { version: "1.1.9", origin: "installed" } };
        compare(PluginStore.statusFor(goodEntry(), installed, [], 1, "0.1.0"), "update");
    }

    function test_status_bundled_takes_precedence() {
        const installed = { pomodoroTimer: { version: "0.0.1", origin: "installed" } };
        compare(PluginStore.statusFor(goodEntry(), installed, ["pomodoroTimer"], 1, "0.1.0"),
            "bundled");
    }

    function test_status_incompatible_api_version() {
        const entry = goodEntry({ apiVersion: 2 });
        compare(PluginStore.statusFor(entry, {}, [], 1, "0.1.0"), "incompatible");
        // Missing apiVersion defaults to 1: compatible with shell API 1.
        const noApi = goodEntry();
        delete noApi.apiVersion;
        compare(PluginStore.statusFor(noApi, {}, [], 1, "0.1.0"), "available");
    }

    function test_status_incompatible_min_shell_version() {
        const entry = goodEntry({ minShellVersion: "9.9.9" });
        compare(PluginStore.statusFor(entry, {}, [], 1, "0.1.0"), "incompatible");
        // Shell at exactly minShellVersion is compatible.
        const exact = goodEntry({ minShellVersion: "0.1.0" });
        compare(PluginStore.statusFor(exact, {}, [], 1, "0.1.0"), "available");
    }
}
