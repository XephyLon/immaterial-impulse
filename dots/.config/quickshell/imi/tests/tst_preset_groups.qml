import QtTest
import "../modules/common/functions/preset_groups.js" as Groups

// The Apply popup's partition. One table, read by the popup for rows and
// resolved into the --only list presets.sh consumes. The commands group is
// the injection fence: `apps.*` are shell-executed strings, and with online
// presets planned they must never apply unasked.
TestCase {
    name: "PresetGroupsTest"

    // A trimmed real preset's shape (Bench.json, 2026-08-31).
    readonly property var preset: ({
        _presetMeta: { description: "x" },
        _pluginState: { version: 2 },
        appearance: { palette: {}, fonts: {}, clock: {}, iconTheme: "a",
                      transparency: {}, mediaWidget: {}, terminal: {} },
        apps: { terminal: "kitty -1" },
        background: {}, bar: {}, dock: {}, sidebar: {}, tray: {},
        light: {}, plugins: {}, policies: {}, sounds: {}, time: {}
    })

    function test_every_group_exists_and_commands_is_the_only_default_off() {
        const offByDefault = Groups.GROUPS.filter(g => !g.defaultOn);
        compare(offByDefault.length, 1);
        compare(offByDefault[0].id, "commands");
        verify(Groups.GROUPS.some(g => g.id === "rest"), "the implicit remainder group");
    }

    function test_every_preset_key_is_claimed_exactly_once() {
        // `rest` claims what nothing else does, so nothing can escape the
        // popup - but no key may be claimed twice either.
        for (const key in preset) {
            if (key === "_presetMeta") continue; // metadata never applies
            const owners = Groups.GROUPS.filter(g =>
                Groups.sectionsOfGroup(g.id, preset).some(s => s === key || s.indexOf(key + ":") === 0));
            verify(owners.length >= 1, key + " unclaimed");
        }
        compare(Groups.groupOf("apps"), "commands");
        compare(Groups.groupOf("policies"), "rest", "unlisted keys land in rest");
        compare(Groups.groupOf("appearance.palette"), "theming");
        compare(Groups.groupOf("appearance.clock"), "widgets");
    }

    function test_sections_for_resolves_groups_to_script_specs() {
        const all = Groups.sectionsFor(preset, Groups.GROUPS.map(g => g.id));
        verify(all.includes("apps"), "commands included when its group is chosen");
        verify(all.includes("_pluginState"), "widgets brings the plugin state");
        verify(all.includes("appearance:palette"), "partial appearance spelled with a colon");
        const noWidgets = Groups.sectionsFor(preset,
            Groups.GROUPS.map(g => g.id).filter(id => id !== "widgets"));
        verify(!noWidgets.includes("_pluginState"));
        verify(!noWidgets.includes("appearance:clock"));
        const noCommands = Groups.sectionsFor(preset,
            Groups.GROUPS.map(g => g.id).filter(id => id !== "commands"));
        verify(!noCommands.includes("apps"));
    }

    function test_counts_reflect_what_the_preset_actually_holds() {
        const counts = Groups.presentCounts(preset);
        verify(counts.wallpaper >= 1, "background is in this preset");
        verify(counts.fonts >= 2, "fonts + iconTheme + terminal");
        const empty = Groups.presentCounts({ background: {} });
        compare(empty.commands, 0, "no apps section, disabled row");
    }
}
