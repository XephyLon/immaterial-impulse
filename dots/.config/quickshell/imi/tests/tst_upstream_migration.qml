import QtQuick
import QtTest
import qs.modules.common

// The shell's config.json is read through a JsonAdapter, which silently drops
// every key it has no property for. A user arriving from end-4/dots-hyprland or
// pctrade/end4-pC therefore loses any setting this fork renamed - no error, no
// warning, the value is just gone and replaced by a default.
//
// `planUpstreamKeyMigration` is deliberately pure: it takes the *raw* parsed
// config (the legacy keys, which `Config.options` cannot see) and returns the
// writes to make, without making them. That keeps the mapping testable against
// fabricated upstream configs rather than only against source text.
//
// The full old-key -> new-key table lives in docs/UPSTREAM_MIGRATION.md.
TestCase {
    name: "UpstreamKeyMigrationTest"

    function plan(legacy) {
        return Config.planUpstreamKeyMigration(legacy);
    }

    function test_nothing_to_migrate_yields_an_empty_plan() {
        compare(Object.keys(plan(null)).length, 0);
        compare(Object.keys(plan(undefined)).length, 0);
        compare(Object.keys(plan("not an object")).length, 0);
        compare(Object.keys(plan({})).length, 0);
    }

    // panelFamily is a *value*, not a key, so the adapter carries it across
    // intact - and then nothing matches it. "ii" is aliased at read time in
    // shell.qml, but "waffle" (end-4's second family) has no counterpart here
    // at all: that family was not ported, so the loader activates nothing and
    // the user gets a completely blank desktop with no error anywhere.
    function test_legacy_panel_families_become_imi() {
        compare(plan({ panelFamily: "ii" })["panelFamily"], "imi");
        compare(plan({ panelFamily: "waffle" })["panelFamily"], "imi");
    }

    function test_our_own_panel_family_is_left_alone() {
        verify(!("panelFamily" in plan({ panelFamily: "imi" })));
    }

    // An unknown family is not ours to guess at. Rewriting it to "imi" would
    // also capture a hand-set future/third-party value, so leave it and let
    // shell.qml's loader decide.
    function test_unknown_panel_family_is_not_rewritten() {
        verify(!("panelFamily" in plan({ panelFamily: "something-else" })));
    }

    // bar.floatStyleShadow -> bar.shadow. Upstream only ever drew the shadow
    // for the Float corner style (cornerStyle === 1); ours draws it for every
    // style that paints a background. Carrying the raw boolean across would
    // switch on a shadow the user has never seen, so the *observed* state is
    // what migrates, not the stored flag.
    function test_float_corner_shadow_survives_the_rename() {
        compare(plan({ bar: { floatStyleShadow: true, cornerStyle: 1 } })["bar.shadow"], true);
    }

    function test_shadow_the_user_never_saw_is_not_switched_on() {
        // floatStyleShadow defaults to true upstream, so almost every arriving
        // config has it set while showing no shadow at all - every corner style
        // except Float ignored it.
        compare(plan({ bar: { floatStyleShadow: true, cornerStyle: 0 } })["bar.shadow"], false);
        compare(plan({ bar: { floatStyleShadow: true, cornerStyle: 3 } })["bar.shadow"], false);
    }

    function test_shadow_switched_off_upstream_stays_off() {
        compare(plan({ bar: { floatStyleShadow: false, cornerStyle: 1 } })["bar.shadow"], false);
    }

    // The migration must never touch bar.shadow for a config that was already
    // written by this fork, or it silently reverts a setting the user changed
    // here. Absence of the legacy key is the only safe signal.
    function test_config_without_the_legacy_key_is_left_alone() {
        verify(!("bar.shadow" in plan({ bar: { cornerStyle: 1, shadow: true } })));
        verify(!("bar.shadow" in plan({ bar: {} })));
    }

    function test_non_boolean_legacy_shadow_is_ignored() {
        verify(!("bar.shadow" in plan({ bar: { floatStyleShadow: "yes", cornerStyle: 1 } })));
    }

    // These are removals, not renames. Inventing a destination for them would
    // write a wrong value into someone's config; see docs/UPSTREAM_MIGRATION.md
    // for why each one has nowhere to go.
    function test_removed_keys_get_no_invented_destination() {
        const p = plan({
            waffles: { bar: { bottom: true }, actionCenter: { toggles: ["network"] } },
            notifications: { monitor: { enable: true, name: "eDP-1" }, timeout: 7000 }
        });
        for (const key in p)
            verify(key.indexOf("waffle") === -1 && key.indexOf("monitor") === -1,
                   `removed key was given a destination: ${key}`);
    }

    // Ordering: compute, then write, then mark. A run that cannot even read the
    // file must not record a migration that never happened - the next launch is
    // the only chance the user gets.
    function test_unparseable_config_does_not_mark_itself_done() {
        Config.options.migratedUpstreamSchema = false;
        Config.migrateUpstreamKeys("{ this is not json");
        compare(Config.options.migratedUpstreamSchema, false);
    }

    // A config we successfully inspected is done even when it needed nothing,
    // so the parse does not repeat on every launch forever.
    function test_inspected_config_is_marked_done() {
        Config.options.migratedUpstreamSchema = false;
        Config.migrateUpstreamKeys('{"panelFamily": "imi"}');
        compare(Config.options.migratedUpstreamSchema, true);
    }

    function test_marker_stops_a_second_run() {
        Config.options.migratedUpstreamSchema = true;
        const before = Config.options.panelFamily;
        Config.migrateUpstreamKeys('{"panelFamily": "waffle"}');
        compare(Config.options.panelFamily, before);
    }
}
