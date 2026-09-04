import QtQuick
import QtTest
import "../services/we_overrides.js" as WeOverrides

// Per-project Wallpaper Engine settings: each key falls back to the global
// config value when the project has no override of its own (the reference
// app's ENGINE_OVERRIDE_FIELDS shape). The map lives in a raw-JSON store -
// project ids are runtime strings, which a JsonAdapter cannot hold.
TestCase {
    name: "WeOverridesTest"

    readonly property var globals: ({ fps: 30, scaling: "fill", silent: true })

    function test_no_override_falls_back_to_globals() {
        var r = WeOverrides.resolve({}, "12345", globals)
        compare(r.fps, 30)
        compare(r.scaling, "fill")
        compare(r.silent, true)
    }

    function test_override_wins_per_key_not_per_project() {
        var overrides = { "12345": { fps: 60 } }
        var r = WeOverrides.resolve(overrides, "12345", globals)
        compare(r.fps, 60)
        // The keys the project does not override still follow the globals.
        compare(r.scaling, "fill")
        compare(r.silent, true)
    }

    function test_another_projects_override_does_not_leak() {
        var overrides = { "999": { fps: 60, scaling: "stretch", silent: false } }
        var r = WeOverrides.resolve(overrides, "12345", globals)
        compare(r.fps, 30)
        compare(r.scaling, "fill")
        compare(r.silent, true)
    }

    function test_silent_false_override_survives_falsy_check() {
        // false is a value, not an absence - the Number(null)-is-0 family.
        var overrides = { "12345": { silent: false } }
        var r = WeOverrides.resolve(overrides, "12345", { fps: 30, scaling: "fill", silent: true })
        compare(r.silent, false)
    }

    function test_empty_project_id_resolves_to_globals() {
        var r = WeOverrides.resolve({ "": { fps: 144 } }, "", globals)
        // No active project means nothing to override - the empty id is not a
        // key, it is the absence of one.
        compare(r.fps, 30)
    }

    function test_set_and_clear_override() {
        var m = WeOverrides.setOverride({}, "12345", "fps", 60)
        compare(m["12345"].fps, 60)
        // null clears the key (the PluginState lesson: a stored literal null
        // would answer past every later fallback)...
        m = WeOverrides.setOverride(m, "12345", "fps", null)
        // ...and a project with no keys left is removed whole, so the store
        // never accretes empty records.
        verify(!("12345" in m))
    }

    function test_sanitize_drops_garbage() {
        var m = WeOverrides.sanitize({
            "12345": { fps: 60, scaling: "fit", silent: false, unknownKey: 1 },
            "bad-entry": "not an object",
            "null-entry": null
        })
        compare(m["12345"].fps, 60)
        compare(m["12345"].scaling, "fit")
        compare(m["12345"].silent, false)
        verify(!("unknownKey" in m["12345"]))
        verify(!("bad-entry" in m))
        verify(!("null-entry" in m))
    }

    function test_sanitize_of_nothing_is_an_empty_map() {
        compare(JSON.stringify(WeOverrides.sanitize(null)), "{}")
        compare(JSON.stringify(WeOverrides.sanitize("garbage")), "{}")
    }

    function test_has_override_reports_per_project() {
        verify(!WeOverrides.hasOverride({}, "12345"))
        verify(WeOverrides.hasOverride({ "12345": { fps: 60 } }, "12345"))
        verify(!WeOverrides.hasOverride({ "999": { fps: 60 } }, "12345"))
    }
}
