import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * What the shell believes about night light, against a real `Hyprsunset`
 * singleton in a real Quickshell process.
 *
 * hyprsunset cannot be asked whether the blue-light filter is applied. On
 * 0.4.0, `hyprctl hyprsunset --help` lists exactly three requests -
 * `temperature`, `gamma`, `identity` - and the daemon's socket answers
 * "invalid command" to everything else. The bare `temperature` request reports
 * the last temperature the daemon was *told*, which `identity` never resets:
 * a daemon launched `--identity` (neutral screen) reports 6000, and a daemon
 * sitting at identity after `temperature 5000` reports 5000. So the query
 * cannot separate "off" from "on", and the shell has to own the state itself
 * and re-apply it - which is what this harness pins.
 *
 * Driven once per case by tests/test_nightlight_state_runtime.py, which seeds a
 * throwaway XDG_STATE_HOME with a known `night.temperatureActive`, puts fake
 * `hyprsunset`/`hyprctl`/`pidof` executables at the front of PATH, and reads
 * the recorded invocations back afterwards. The `pidof` fake is not optional
 * scenery: `startHyprsunset` short-circuits on `pidof hyprsunset ||`, so
 * without it a test run on a machine with a live daemon silently never
 * exercises the launch path at all.
 *
 *   NIGHTLIGHT_EXPECT_ACTIVE=true XDG_CONFIG_HOME=... XDG_STATE_HOME=... \
 *     qs -p NightLightStateRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    // The state seeded into states.json, i.e. what the shell must come back up
    // believing and must have re-applied to the daemon.
    readonly property bool expectActive: (Quickshell.env("NIGHTLIGHT_EXPECT_ACTIVE") ?? "false") === "true"

    // Optional second act: flip the toggle the way the sidebar switch does and
    // check the new state is written straight back to disk, since that file is
    // the only thing the next launch has to go on.
    readonly property string toggleTo: Quickshell.env("NIGHTLIGHT_TOGGLE") ?? ""

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[NightLightState] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[NightLightState] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Component.onCompleted: {
        console.log(`[NightLightState] state file: ${Persistent.filePath}`);
        // Exactly as shell.qml does it, which is the interesting part: this runs
        // long before Persistent's FileView has finished loading.
        Hyprsunset.load();
    }

    Timer {
        id: waitForState
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForState.interval;
            if (!Persistent.ready || !Config.ready) {
                if (harness.elapsed >= 30000) {
                    harness.check("Persistent and Config become ready", false);
                    harness.finish();
                }
                return;
            }
            waitForState.running = false;
            // execDetached is fire-and-forget, so give the fake binaries a
            // moment to land their lines in the log before anything is read.
            settle.running = true;
        }
    }

    Timer {
        id: settle
        interval: 1500
        onTriggered: {
            harness.check(`temperatureActive is ${harness.expectActive}, got ${Hyprsunset.temperatureActive}`,
                          Hyprsunset.temperatureActive === harness.expectActive);
            harness.check(`the persisted state survived the restore (${harness.expectActive})`,
                          Persistent.states.night.temperatureActive === harness.expectActive);

            if (harness.toggleTo === "") {
                harness.finish();
                return;
            }

            const target = harness.toggleTo === "on";
            Hyprsunset.toggleTemperature(target);
            harness.check(`toggling to ${harness.toggleTo} sets temperatureActive`,
                          Hyprsunset.temperatureActive === target);
            harness.check(`toggling to ${harness.toggleTo} is written back to states.json`,
                          Persistent.states.night.temperatureActive === target);
            // Persistent debounces its writes; let the file catch up.
            settleToggle.running = true;
        }
    }

    Timer {
        id: settleToggle
        interval: 1000
        onTriggered: harness.finish()
    }
}
