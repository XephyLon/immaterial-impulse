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

    readonly property var fullGlobals: ({
        fps: 30, scaling: "fill", silent: true,
        volume: 100, audioProcessing: true,
        disableMouse: false, disableParallax: false, disableParticles: false
    })

    function test_engine_flag_keys_resolve_with_fallback() {
        // The reference app's ENGINE_OVERRIDE_FIELDS set, whole: volume,
        // audio processing and the three feature switches ride the same
        // per-key fallback as fps/scaling/silent.
        var r = WeOverrides.resolve({}, "12345", fullGlobals)
        compare(r.volume, 100)
        compare(r.audioProcessing, true)
        compare(r.disableMouse, false)
        compare(r.disableParallax, false)
        compare(r.disableParticles, false)

        var overrides = { "12345": { volume: 40, disableParticles: true, audioProcessing: false } }
        r = WeOverrides.resolve(overrides, "12345", fullGlobals)
        compare(r.volume, 40)
        compare(r.audioProcessing, false)
        compare(r.disableParticles, true)
        // Untouched keys still follow the globals.
        compare(r.disableMouse, false)
        compare(r.fps, 30)
    }

    function test_volume_zero_override_survives_falsy_check() {
        var r = WeOverrides.resolve({ "12345": { volume: 0 } }, "12345", fullGlobals)
        compare(r.volume, 0)
    }

    function test_project_properties_resolve_per_wallpaper() {
        // Custom properties (project.json general.properties) are inherently
        // per-wallpaper - there is no global to fall back to, so an absent
        // record resolves to an empty map, never undefined.
        var r = WeOverrides.resolve({}, "12345", fullGlobals)
        compare(JSON.stringify(r.properties), "{}")

        var overrides = { "12345": { properties: { schemecolor: "0.1 0.2 0.3", rain: "1" } } }
        r = WeOverrides.resolve(overrides, "12345", fullGlobals)
        compare(r.properties.schemecolor, "0.1 0.2 0.3")
        compare(r.properties.rain, "1")
    }

    function test_set_and_clear_project_property() {
        var m = WeOverrides.setProjectProperty({}, "12345", "rain", "1")
        compare(m["12345"].properties.rain, "1")
        m = WeOverrides.setProjectProperty(m, "12345", "snow", "0")
        compare(m["12345"].properties.rain, "1")
        compare(m["12345"].properties.snow, "0")
        // null clears one property...
        m = WeOverrides.setProjectProperty(m, "12345", "rain", null)
        verify(!("rain" in m["12345"].properties))
        // ...and clearing the last one removes the map, and with it an
        // otherwise-empty record.
        m = WeOverrides.setProjectProperty(m, "12345", "snow", null)
        verify(!("12345" in m))
    }

    function test_properties_do_not_count_as_engine_override() {
        // The "Custom settings" switch is about the ENGINE flags; a wallpaper
        // whose only record is tweaked properties must not read as having
        // flag overrides, or flipping the switch off would eat the user's
        // property edits.
        var m = WeOverrides.setProjectProperty({}, "12345", "rain", "1")
        verify(!WeOverrides.hasOverride(m, "12345"))
        verify(WeOverrides.hasProperties(m, "12345"))
    }

    function test_clear_engine_overrides_keeps_properties() {
        var m = WeOverrides.setOverride({}, "12345", "fps", 60)
        m = WeOverrides.setProjectProperty(m, "12345", "rain", "1")
        m = WeOverrides.clearEngineOverrides(m, "12345")
        verify(!WeOverrides.hasOverride(m, "12345"))
        compare(m["12345"].properties.rain, "1")
    }

    function test_focus_is_per_wallpaper_and_defaults_to_centre() {
        // Like properties: no global side. Absent, it resolves to centre
        // (0.5, 0.5) - never undefined, which would NaN the crop.
        var r = WeOverrides.resolve({}, "12345", fullGlobals)
        compare(r.focus.x, 0.5)
        compare(r.focus.y, 0.5)

        var overrides = { "12345": { focus: { x: 0.2, y: 0.8 } } }
        r = WeOverrides.resolve(overrides, "12345", fullGlobals)
        compare(r.focus.x, 0.2)
        compare(r.focus.y, 0.8)
    }

    function test_focus_zero_survives_falsy_check() {
        var r = WeOverrides.resolve({ "12345": { focus: { x: 0, y: 0 } } }, "12345", fullGlobals)
        compare(r.focus.x, 0)
        compare(r.focus.y, 0)
    }

    function test_set_focus_stores_and_clamps() {
        var m = WeOverrides.setFocus({}, "12345", 0.3, 0.7)
        compare(m["12345"].focus.x, 0.3)
        compare(m["12345"].focus.y, 0.7)
        // Out of range is clamped, not stored raw.
        m = WeOverrides.setFocus(m, "12345", -1, 5)
        compare(m["12345"].focus.x, 0)
        compare(m["12345"].focus.y, 1)
        // Back to dead centre removes the focus record entirely (and an
        // otherwise-empty project with it) - centre is the default, so a
        // stored 0.5/0.5 is churn.
        m = WeOverrides.setFocus(m, "12345", 0.5, 0.5)
        verify(!("12345" in m))
    }

    function test_focus_does_not_count_as_engine_override() {
        // Cropping is per-wallpaper like properties, not an engine flag - the
        // Custom settings switch must not eat it.
        var m = WeOverrides.setFocus({}, "12345", 0.2, 0.5)
        verify(!WeOverrides.hasOverride(m, "12345"))
    }

    function test_clear_engine_overrides_keeps_focus() {
        var m = WeOverrides.setOverride({}, "12345", "fps", 60)
        m = WeOverrides.setFocus(m, "12345", 0.2, 0.5)
        m = WeOverrides.clearEngineOverrides(m, "12345")
        verify(!WeOverrides.hasOverride(m, "12345"))
        compare(m["12345"].focus.x, 0.2)
    }

    function test_sanitize_keeps_focus_within_range() {
        var m = WeOverrides.sanitize({
            "1": { focus: { x: 0.3, y: 0.9 } },
            "2": { focus: { x: 5, y: -2 } },
            "3": { focus: { x: "garbage", y: 0.9 } },
            "4": { focus: "not an object" }
        })
        compare(m["1"].focus.x, 0.3)
        compare(m["1"].focus.y, 0.9)
        // Out of range clamps; a non-number axis falls to centre.
        compare(m["2"].focus.x, 1)
        compare(m["2"].focus.y, 0)
        compare(m["3"].focus.x, 0.5)
        compare(m["3"].focus.y, 0.9)
        // A dead-centre focus is not a stored record.
        verify(!("4" in m))
    }

    function test_sanitize_keeps_string_properties_only() {
        var m = WeOverrides.sanitize({
            "12345": {
                volume: 55,
                properties: { ok: "1", nested: { bad: true }, num: 3 }
            }
        })
        compare(m["12345"].volume, 55)
        compare(m["12345"].properties.ok, "1")
        // Non-string property values re-serialize (numbers) or drop (objects):
        // everything WE gets is a string on its command line.
        compare(m["12345"].properties.num, "3")
        verify(!("nested" in m["12345"].properties))
    }
}
