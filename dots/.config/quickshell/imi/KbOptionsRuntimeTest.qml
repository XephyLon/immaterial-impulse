import QtQuick
import Quickshell
import qs.modules.common

/**
 * Drives Config.qml's stale-kbOptions clear against a real config.json and a
 * real generated shellOverrides/main.lua.
 *
 * The clear shipped once behind a persisted marker and fixed nothing, and
 * nothing caught it, because there was no test at all: the logic reads
 * correctly in isolation and only fails against on-disk states a unit test
 * never constructs - a marker already burned against a config that did not
 * carry the value yet, and a config.json cleared while the generated lua the
 * compositor actually reads keeps the option forever.
 *
 * Launched once per case by tests/test_kboptions_migration_runtime.py, which
 * seeds a throwaway XDG_CONFIG_HOME and checks both files afterwards. Never
 * point it at a real config directory - it writes config.json and may rewrite
 * hypr/hyprland/shellOverrides/main.lua.
 *
 *   KBOPT_EXPECT='' XDG_CONFIG_HOME=$(mktemp -d) qs -p KbOptionsRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int elapsed: 0

    readonly property string expected: Quickshell.env("KBOPT_EXPECT") ?? ""

    function check(label, ok) {
        console.log(`[KbOptions] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[KbOptions] failures: ${harness.failures}`);
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

            const actual = Config.options.hyprland.input.kbOptions;
            harness.check(`kbOptions is ${JSON.stringify(harness.expected)}, got ${JSON.stringify(actual)}`,
                          actual === harness.expected);

            // The config write is debounced and the lua edit is a detached
            // process, so give both a moment before the caller reads the files.
            settle.running = true;
        }
    }

    Timer {
        id: settle
        interval: 1500
        onTriggered: harness.finish()
    }
}
