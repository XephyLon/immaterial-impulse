import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * Clight cooperation, against real Clight/Brightness/Hyprsunset singletons in
 * a real Quickshell process.
 *
 * Driven once per case by tests/test_clight_integration_runtime.py, which
 * puts fake `busctl`/`brightnessctl`/`ddcutil`/`clight` executables (plus the
 * night-light trio `hyprsunset`/`hyprctl`/`pidof`) at the front of PATH and
 * reads the recorded invocations back afterwards. The fake busctl keeps a
 * little backlight state of its own: GetAll reports it, IncBl/DecBl move it,
 * so the full loop - shell command, daemon state, next poll - is real.
 *
 * What it pins:
 * - present: a brightness change reaches the daemon (IncBl) and never the
 *   direct writers; the daemon's view converges on the target; a daemon-made
 *   temperature change is announced exactly once (never for the first
 *   report); daemon conf (auto-calibration, day/night temps) reaches the
 *   shell; night light restore behaves exactly as without Clight.
 * - absent (not installed, or installed with the daemon down): stock
 *   behaviour, brightnessctl writes and not a single org.clight call.
 *
 *   CLIGHT_EXPECT_INSTALLED=true CLIGHT_EXPECT_AVAILABLE=true ... \
 *     qs -p ClightIntegrationRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int elapsed: 0
    property int temperatureSignals: 0

    readonly property bool expectInstalled: (Quickshell.env("CLIGHT_EXPECT_INSTALLED") ?? "false") === "true"
    readonly property bool expectAvailable: (Quickshell.env("CLIGHT_EXPECT_AVAILABLE") ?? "false") === "true"

    function check(label, ok) {
        console.log(`[ClightIntegration] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[ClightIntegration] failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Connections {
        target: Clight
        function onTemperatureChangedByDaemon() {
            harness.temperatureSignals++;
        }
    }

    Component.onCompleted: {
        // The suite cannot wait out the production 5s cadence.
        Clight.pollInterval = 300;
        // Exactly as shell.qml does it.
        Hyprsunset.load();
    }

    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            const monitor = Brightness.monitors[0] ?? null;
            const clightSettled = harness.expectAvailable ? Clight.ready : true;
            if (!Persistent.ready || !Config.ready || !(monitor?.ready ?? false) || !clightSettled) {
                if (harness.elapsed >= 30000) {
                    harness.check("Config, Persistent, the monitor and Clight become ready", false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            // Give the absent case time to prove detection stays negative.
            act.running = true;
        }
    }

    Timer {
        id: act
        interval: 1000
        onTriggered: {
            harness.check(`Clight.installed is ${harness.expectInstalled}, got ${Clight.installed}`,
                          Clight.installed === harness.expectInstalled);
            harness.check(`Clight.available is ${harness.expectAvailable}, got ${Clight.available}`,
                          Clight.available === harness.expectAvailable);
            if (harness.expectAvailable) {
                harness.check("deferral is active", Clight.managesBacklight === true);
                harness.check(`daemon day temperature reached the shell, got ${Clight.dayTemperature}`,
                              Clight.dayTemperature === 6500);
                harness.check(`daemon night temperature reached the shell, got ${Clight.nightTemperature}`,
                              Clight.nightTemperature === 4000);
                harness.check("auto calibration reads on", Clight.autoCalibration === true);
                harness.check("ambient sensor is visible", Clight.sensorAvailable === true);
            }
            Brightness.monitors[0].setBrightness(0.8);
            settle.running = true;
        }
    }

    Timer {
        id: settle
        // The brightness Behavior animates for 200ms and the fake daemon is
        // polled every 300ms; leave room for several polls after both.
        interval: 2500
        onTriggered: {
            const monitor = Brightness.monitors[0];
            harness.check(`monitor brightness holds 0.8, got ${monitor.brightness}`,
                          Math.abs(monitor.brightness - 0.8) < 0.05);
            if (harness.expectAvailable) {
                harness.check(`daemon backlight converged on 0.8, got ${Clight.backlight}`,
                              Math.abs(Clight.backlight - 0.8) < 0.05);
                harness.check(`daemon temperature change announced exactly once, got ${harness.temperatureSignals}`,
                              harness.temperatureSignals === 1);
                harness.check(`daemon temperature reached the shell, got ${Clight.temperature}`,
                              Clight.temperature === 3500);
                Clight.setAutoCalibration(false);
                Clight.setDayTemperature(6000);
            }
            settleCommands.running = true;
        }
    }

    Timer {
        id: settleCommands
        interval: 800
        onTriggered: harness.finish()
    }
}
