import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * The phone-connect stream's process lifetime, against the real
 * services/PhoneConnect.qml singleton in a real Quickshell process.
 *
 * Driven once per case by tests/test_phone_connect_monitor_runtime.py, which
 * puts a fake `busctl` at the front of PATH and reads the recorded
 * invocations back afterwards. The fake is stateful: its `monitor` verb
 * rewrites the battery charge its own `GetAll` will report NEXT, then prints
 * one signal line, so "the change reached the shell" can only be true if the
 * signal was heard and acted on.
 *
 * That is the whole oracle for the stream case, and it is why the poll
 * interval is seeded at ten minutes there: with the timer that far out,
 * nothing but the signal can deliver the new charge inside the harness's
 * lifetime. A shorter interval would let a poll pass the check for a stream
 * that never worked.
 *
 * What each case pins:
 * - stream: the monitor comes up for KDE Connect and a battery change
 *   arrives from the signal rather than from the timer.
 * - crash: a busctl that exits immediately - the shape CONTRIBUTING.md
 *   forbids answering with a `running` binding - is retried a bounded number
 *   of times and then given up on, with the poll still populating the model.
 *   The delays between spawns are asserted driver-side.
 *  - valent: no monitor at all (its signal set is unverified), model still
 *   populated by the poll.
 * - none: no daemon, so nothing streams and nothing is spawned for it.
 *
 *   PHONE_EXPECT_BACKEND=kdeconnect PHONE_EXPECT_MONITOR=running ... \
 *     qs -p PhoneConnectMonitorRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    readonly property string expectBackend: Quickshell.env("PHONE_EXPECT_BACKEND") ?? "none"
    readonly property string expectMonitor: Quickshell.env("PHONE_EXPECT_MONITOR") ?? "idle"
    readonly property int expectCharge: Number(Quickshell.env("PHONE_EXPECT_CHARGE") ?? "-1")
    readonly property int settleMs: Number(Quickshell.env("PHONE_SETTLE_MS") ?? "6000")

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[PhoneConnectMonitor] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[PhoneConnectMonitor] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Component.onCompleted: {
        // A singleton is constructed on first use, so this read is what
        // starts the presence probe at all.
        console.log(`[PhoneConnectMonitor] service constructed, installed=${PhoneConnect.installed}`);
    }

    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            if (!Config.ready || !PhoneConnect.installed) {
                if (harness.elapsed >= 30000) {
                    harness.check("Config becomes ready and busctl is detected", false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            settle.running = true;
        }
    }

    Timer {
        id: settle
        // Long enough for the crash case to exhaust its ceiling
        // (1+2+4+8+16s of backoff), set per case by the driver.
        interval: harness.settleMs
        onTriggered: {
            harness.check(`backend is ${harness.expectBackend}, got ${PhoneConnect.backend}`,
                          PhoneConnect.backend === harness.expectBackend);
            harness.check(`monitor state is ${harness.expectMonitor}, got ${PhoneConnect.monitorState}`,
                          PhoneConnect.monitorState === harness.expectMonitor);

            if (harness.expectMonitor === "failed")
                harness.check(`the ceiling was reached exactly, got ${PhoneConnect.monitorAttempts}`,
                              PhoneConnect.monitorAttempts === PhoneConnect.monitorAttemptCeiling);

            if (harness.expectBackend === "none") {
                harness.check(`no daemon leaves no devices, got ${PhoneConnect.devices.length}`,
                              PhoneConnect.devices.length === 0);
                harness.finish();
                return;
            }

            harness.check(`the model is populated, got ${PhoneConnect.devices.length} device(s)`,
                          PhoneConnect.devices.length === 1);
            const device = PhoneConnect.devices[0] ?? null;
            harness.check("the device is reachable and paired", (device?.reachable ?? false) && (device?.paired ?? false));
            harness.check(`battery charge is ${harness.expectCharge}, got ${device?.batteryCharge}`,
                          (device?.batteryCharge ?? -99) === harness.expectCharge);
            harness.finish();
        }
    }
}
