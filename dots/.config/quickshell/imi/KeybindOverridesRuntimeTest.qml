import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * The keyboard-shortcuts editor's write path, against real singletons in a
 * real Quickshell process: HyprlandKeybindOverrides reads the seeded sidecar,
 * regenerates the Lua shim through the real Python generator, runs the real
 * --flat occupancy scans, and HyprlandKeybinds rewrites its tree through the
 * override map. None of this is reachable from the unit suites - the QML
 * tests never instantiate these singletons and the Python tests never run
 * them - so a broken Process command line or a mis-wired signal is invisible
 * until a user edits a shortcut.
 *
 * Driven by tests/test_keybind_overrides_runtime.py, which seeds a throwaway
 * XDG_CONFIG_HOME (keybind files + sidecar), fakes `hyprctl` on PATH, and
 * inspects the generated shim afterwards. KEYBIND_EXPECT_STATUS carries the
 * expected end state ("ok" or "foreign").
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    readonly property string expectStatus: Quickshell.env("KEYBIND_EXPECT_STATUS") ?? "ok"

    function check(name, cond, detail) {
        harness.checksRun++;
        if (cond) {
            console.log(`[KeybindOverridesRuntime] PASS ${name}`);
        } else {
            console.log(`[KeybindOverridesRuntime] FAIL ${name} ${detail ?? ""}`);
            harness.failures++;
        }
    }

    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            harness.elapsed += interval;
            const settled = HyprlandKeybindOverrides.ready
                && HyprlandKeybindOverrides.shimStatus !== "unknown"
                && HyprlandKeybindOverrides.flatDefaultBinds.length > 0;
            if (!settled && harness.elapsed < 30000)
                return;
            running = false;
            harness.finish(settled);
        }
    }

    function finish(settled) {
        check("service settled (ready + shim status + flat scan)", settled,
              `ready=${HyprlandKeybindOverrides.ready} status=${HyprlandKeybindOverrides.shimStatus} flat=${HyprlandKeybindOverrides.flatDefaultBinds.length}`);

        check(`shim status is ${harness.expectStatus}`,
              HyprlandKeybindOverrides.shimStatus === harness.expectStatus,
              `got ${HyprlandKeybindOverrides.shimStatus} (${HyprlandKeybindOverrides.lastError})`);

        // Positive control: an untouched default must be findable, otherwise
        // the "removed is gone" check below passes against an empty tree.
        const untouched = HyprlandKeybinds.findBinding("SUPER|T");
        check("untouched default is findable in the tree",
              untouched !== null && !untouched.overridden,
              JSON.stringify(untouched));

        const rebound = HyprlandKeybinds.findBinding("SUPER|Q");
        check("rebound default shows its replacement chord in the tree",
              rebound !== null && rebound.overridden
              && JSON.stringify(rebound.mods) === JSON.stringify(["SUPER", "SHIFT"])
              && rebound.key === "C",
              JSON.stringify(rebound));

        check("removed default is gone from the tree",
              HyprlandKeybinds.findBinding("SUPER|W") === null);

        const added = HyprlandKeybinds.findBinding("SHIFT+SUPER|F1");
        check("added shortcut appears in the tree",
              added !== null && added.added === true
              && added.comment === "Say hi",
              JSON.stringify(added));

        const conflicts = HyprlandKeybindOverrides.conflictsFor(["SUPER"], "T", null);
        check("occupied chord reports a conflict through the real flat scan",
              conflicts.length === 1 && conflicts[0].description === "App: Terminal",
              JSON.stringify(conflicts));

        const freed = HyprlandKeybindOverrides.conflictsFor(["SUPER"], "W", null);
        check("chord freed by the removal reports no conflict",
              freed.length === 0, JSON.stringify(freed));

        const userConflict = HyprlandKeybindOverrides.conflictsFor(["SUPER", "ALT"], "U", null);
        check("custom-file chord reports a conflict from the user scan",
              userConflict.length === 1 && userConflict[0].source === "user",
              JSON.stringify(userConflict));

        console.log(`[KeybindOverridesRuntime] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.quit();
    }
}
