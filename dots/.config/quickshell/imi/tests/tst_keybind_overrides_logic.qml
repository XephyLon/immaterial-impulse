import QtTest
import "../modules/common/functions/keybindOverrides.js" as KO

/**
 * The keyboard-shortcuts editor's pure logic: identity normalization,
 * override application to the parsed keybind tree, rebindability gating and
 * chord-conflict detection. A regression in applyOverrides empties or
 * mis-renders the cheatsheet with no error anywhere, and a regression in
 * chordConflicts silently accepts a chord that already fires something else -
 * both invisible until a user hits them, which is why every branch is pinned
 * here without a disk or a compositor.
 */
TestCase {
    name: "KeybindOverridesLogicTest"

    function makeSections() {
        return [{
            name: "",
            keybinds: [],
            children: [{
                name: "Window",
                keybinds: [
                    { mods: ["SUPER"], key: "Q", dispatcher: "hl.dsp.window.close",
                      params: "", comment: "Window: Close", flags: {}, submap: "" },
                    { mods: ["SHIFT", "SUPER"], key: "W", dispatcher: "hl.dsp.window.pin",
                      params: "", comment: "Window: Pin", flags: {}, submap: "" },
                    { mods: [], key: "SUPER + Arrows", dispatcher: "comment",
                      params: "", comment: "Focus in direction", flags: {}, submap: "" },
                    { mods: ["SUPER"], key: "Equal", dispatcher: "function",
                      params: "", comment: "Zoom in", flags: { repeating: true }, submap: "" },
                ],
                children: []
            }]
        }];
    }

    function test_identity_sorts_mods() {
        compare(KO.identityFor(["SHIFT", "SUPER"], "W"), "SHIFT+SUPER|W");
        compare(KO.identityFor(["SUPER", "SHIFT"], "W"), "SHIFT+SUPER|W");
        compare(KO.identityFor([], "Print"), "|Print");
    }

    function test_split_identity_round_trips() {
        const s = KO.splitIdentity("SHIFT+SUPER|W");
        compare(s.mods, ["SHIFT", "SUPER"]);
        compare(s.key, "W");
        const bare = KO.splitIdentity("|Print");
        compare(bare.mods, []);
        compare(bare.key, "Print");
    }

    function test_apply_annotates_without_overrides() {
        const out = KO.applyOverrides(makeSections(), {}, "Custom");
        const binds = out[0].children[0].keybinds;
        compare(binds.length, 4);
        compare(binds[0].identity, "SUPER|Q");
        verify(binds[0].editable);
        verify(binds[0].removable);
        verify(!binds[0].overridden);
        // Synthetic comment rows are neither editable nor removable.
        verify(!binds[2].editable);
        verify(!binds[2].removable);
        // Lua-closure binds can be removed but not re-emitted on another chord.
        verify(!binds[3].editable);
        verify(binds[3].removable);
    }

    function test_rebind_replaces_chord_and_marks_override() {
        const overrides = {
            "SUPER|Q": { action: "rebind", mods: ["SUPER", "SHIFT"], key: "C",
                         dispatcher: "hl.dsp.window.close", params: "",
                         description: "Window: Close" }
        };
        const out = KO.applyOverrides(makeSections(), overrides, "Custom");
        const kb = out[0].children[0].keybinds[0];
        compare(kb.mods, ["SUPER", "SHIFT"]);
        compare(kb.key, "C");
        verify(kb.overridden);
        compare(kb.identity, "SUPER|Q");
    }

    function test_remove_drops_the_bind() {
        const out = KO.applyOverrides(makeSections(), { "SUPER|Q": { action: "remove" } }, "Custom");
        const keys = out[0].children[0].keybinds.map(kb => kb.key);
        compare(keys.indexOf("Q"), -1);
        compare(keys.length, 3);
    }

    function test_add_appends_custom_section_to_last_column() {
        const overrides = {
            "SHIFT+SUPER|F1": { action: "add", mods: ["SUPER", "SHIFT"], key: "F1",
                                command: "notify-send hi", description: "Say hi" }
        };
        const out = KO.applyOverrides(makeSections(), overrides, "Custom");
        const lastColumn = out[out.length - 1];
        const section = lastColumn.children[lastColumn.children.length - 1];
        compare(section.name, "Custom");
        compare(section.keybinds.length, 1);
        compare(section.keybinds[0].key, "F1");
        compare(section.keybinds[0].comment, "Say hi");
        verify(section.keybinds[0].added);
        verify(section.keybinds[0].removable);
    }

    function test_can_rebind_grammar() {
        verify(KO.canRebind({ dispatcher: "hl.dsp.global", params: '"quickshell:cheatsheetToggle"' }));
        verify(KO.canRebind({ dispatcher: "hl.dsp.window.fullscreen",
                              params: '{ mode = "maximized", action = "toggle" }' }));
        verify(KO.canRebind({ dispatcher: "hl.dsp.exec_cmd", params: "terminal" }));
        // Quoted parens are content, not calls.
        verify(KO.canRebind({ dispatcher: "hl.dsp.exec_cmd", params: '"echo $(date)"' }));
        verify(!KO.canRebind({ dispatcher: "function", params: "" }));
        verify(!KO.canRebind({ dispatcher: "comment", params: "" }));
        verify(!KO.canRebind({ dispatcher: "hl.dsp.exec_cmd", params: 'qsIsAlive .. " || foo"' }));
        verify(!KO.canRebind({ dispatcher: "hl.dsp.exec_cmd", params: 'terminal("x")' }));
    }

    function flatFixture() {
        return [
            { mods: ["SUPER"], key: "T", dispatcher: "hl.dsp.exec_cmd",
              params: "terminal", comment: "App: Terminal", submap: "" },
            { mods: ["SUPER"], key: "T", dispatcher: "hl.dsp.exec_cmd",
              params: "", comment: "", submap: "" },
            { mods: ["ALT", "SUPER"], key: "F1", dispatcher: "function",
              params: "", comment: "", submap: "virtual-machine" },
        ];
    }

    function test_conflicts_found_for_occupied_chord() {
        const conflicts = KO.chordConflicts(["SUPER"], "T", null, flatFixture(), [], {});
        compare(conflicts.length, 2);
        compare(conflicts[0].description, "App: Terminal");
        compare(conflicts[0].source, "default");
    }

    function test_conflicts_ignore_the_binding_being_edited() {
        // Rebinding SUPER+T's own binding to SUPER+T again is not a conflict.
        const conflicts = KO.chordConflicts(["SUPER"], "T", "SUPER|T", flatFixture(), [], {});
        compare(conflicts.length, 0);
    }

    function test_conflicts_skip_chords_freed_by_other_overrides() {
        const overrides = { "SUPER|T": { action: "remove" } };
        const conflicts = KO.chordConflicts(["SUPER"], "T", null, flatFixture(), [], overrides);
        compare(conflicts.length, 0);
    }

    function test_conflicts_report_submap_collisions() {
        const conflicts = KO.chordConflicts(["SUPER", "ALT"], "F1", null, flatFixture(), [], {});
        compare(conflicts.length, 1);
        compare(conflicts[0].submap, "virtual-machine");
    }

    function test_conflicts_include_chords_claimed_by_overrides() {
        const overrides = {
            "SUPER|Q": { action: "rebind", mods: ["SUPER"], key: "Z",
                         dispatcher: "hl.dsp.window.close", params: "",
                         description: "Window: Close" },
            "SUPER|Y": { action: "add", mods: ["SUPER"], key: "Y",
                         command: "notify-send hi", description: "Say hi" },
        };
        const rebound = KO.chordConflicts(["SUPER"], "Z", null, [], [], overrides);
        compare(rebound.length, 1);
        compare(rebound[0].source, "override");
        const added = KO.chordConflicts(["SUPER"], "Y", null, [], [], overrides);
        compare(added.length, 1);
        // The entry being edited never conflicts with itself.
        const self = KO.chordConflicts(["SUPER"], "Z", "SUPER|Q", [], [], overrides);
        compare(self.length, 0);
    }

    function test_conflicts_normalize_mod_order() {
        const conflicts = KO.chordConflicts(["ALT", "SUPER"], "F1", null, flatFixture(), [], {});
        const swapped = KO.chordConflicts(["SUPER", "ALT"], "F1", null, flatFixture(), [], {});
        compare(conflicts.length, swapped.length);
    }
}
