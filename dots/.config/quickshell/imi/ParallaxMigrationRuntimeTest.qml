import QtQuick
import Quickshell
import qs.modules.common

/**
 * Drives Config.qml's one-shot parallax revival against a real config.json.
 *
 * Wallpaper parallax was config-only for this shell's whole life - the knobs
 * came over from dots-hyprland but their consumer went with the ii->pC theme
 * swap - so every stored value predates the feature doing anything. Reviving
 * it against those values would ship it switched off for everyone who has ever
 * written a config, which is everyone, and no unit test sees that: the logic
 * reads correctly in isolation and only fails against an on-disk config the
 * adapter has already merged over the QML defaults.
 *
 * Launched once per case by tests/test_parallax_migration_runtime.py, which
 * seeds a throwaway XDG_CONFIG_HOME and reads config.json afterwards. Never
 * point it at a real config directory - it writes config.json.
 *
 *   PARALLAX_EXPECT=on XDG_CONFIG_HOME=$(mktemp -d) qs -p ParallaxMigrationRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    // "on"  - the switches must end up true (the migration ran)
    // "off" - they must be left alone (the marker said it already ran)
    readonly property string expected: Quickshell.env("PARALLAX_EXPECT") ?? "on"

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[Parallax] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[Parallax] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Timer {
        id: waitForConfig
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForConfig.interval;
            if (!Config.ready) {
                if (harness.elapsed >= 15000) {
                    harness.check("the config becomes ready", false);
                    harness.finish();
                }
                return;
            }
            waitForConfig.running = false;

            const parallax = Config.options.background.parallax;
            const wantOn = harness.expected === "on";
            harness.check(`enable is ${wantOn}, got ${parallax.enable}`,
                          parallax.enable === wantOn);
            harness.check(`enableWorkspace is ${wantOn}, got ${parallax.enableWorkspace}`,
                          parallax.enableWorkspace === wantOn);
            harness.check(`enableSidebar is ${wantOn}, got ${parallax.enableSidebar}`,
                          parallax.enableSidebar === wantOn);
            harness.check(`enableWidgets is ${wantOn}, got ${parallax.enableWidgets}`,
                          parallax.enableWidgets === wantOn);
            // Tuned numbers are never reset - only the switches are, because a
            // number cannot turn the effect off on its own.
            harness.check(`workspaceZoom survives, got ${parallax.workspaceZoom}`,
                          Math.abs(parallax.workspaceZoom - 1.42) < 0.001);
            harness.check("the marker is set", parallax.migratedFromDeadCode === true);

            // The config write is debounced; give it a moment before the
            // caller reads the file back.
            settle.running = true;
        }
    }

    Timer {
        id: settle
        interval: 1500
        onTriggered: harness.finish()
    }
}
