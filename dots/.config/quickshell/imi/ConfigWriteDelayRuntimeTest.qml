import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.imi.settings

/**
 * How long `Config.readWriteDelay` stays 0, driven against the real settings
 * window.
 *
 * What this exists to refuse, in the shape it was found:
 * `SettingsContent.qml` set `Config.readWriteDelay = 0` from its own
 * `Component.onCompleted` and never restored it. `Config` is a singleton and
 * the settings host is built at `Config.ready` - not when its window opens -
 * so from startup onward EVERY config write anywhere in the shell was flushed
 * on the next turn instead of being debounced, for the rest of the session, on
 * every machine, whether or not Settings was ever opened. The first check
 * below is that sentence: the real `Settings` scope is built and the delay is
 * still the default.
 *
 * The rest are the lifetime questions a saved-and-restored value gets wrong
 * and a resolution does not: opened and closed repeatedly, two claimants at
 * once, and a claim whose declaring object is destroyed under it - which is
 * what a hot reload does to a surface holding one, and the case where "restore
 * the previous value" has nobody left to run the restore.
 *
 * The claim is read through `Config.readWriteDelay` rather than through the
 * claim count, because the delay is what the two timers in `Config.qml`
 * actually use: a count that moves while the resolution is broken would agree
 * with itself.
 *
 * Brings its own weston and its own session bus through
 * tests/test_config_write_delay_runtime.py, which is what runs it.
 *
 *   qs -p ConfigWriteDelayRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[ConfigWriteDelay] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[ConfigWriteDelay] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    readonly property int debounced: Config.defaultReadWriteDelay
    readonly property int immediate: 0

    // The real thing, not a re-declaration of its wiring: this is the scope
    // the panel family loads, carrying its own window and its own claim.
    Settings {}

    // A second claimant, so "two things want it at once" is driven rather than
    // reasoned about. Toggled by the steps below.
    property bool secondWanted: false
    ConfigWriteDelayRef {
        active: harness.secondWanted
    }

    // A claim whose declaring object goes away under it. `Loader.active =
    // false` destroys the object, which is what a hot reload does to a surface
    // holding a claim - and the case a saved previous value cannot recover
    // from, because whoever would restore it has been destroyed too.
    Loader {
        id: doomedClaim
        active: false
        sourceComponent: ConfigWriteDelayRef {
            active: true
        }
    }

    property int elapsed: 0
    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            if (!Config.ready) {
                if (harness.elapsed >= 20000) {
                    harness.check("Config became ready", false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            steps.running = true;
        }
    }

    property var stepList: [
        () => {
            harness.check(`the settings host is built and the shell's writes are still`
                          + ` debounced, got ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.debounced);
            GlobalStates.settingsOpen = true;
        },

        () => {
            harness.check(`the open window flushes immediately, got ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.immediate);
            GlobalStates.settingsOpen = false;
        },

        () => {
            harness.check(`closing it restores the debounce, got ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.debounced);
            GlobalStates.settingsOpen = true;
        },

        () => {
            harness.check(`...and a second open claims it again rather than having spent`
                          + ` the claim, got ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.immediate);
            harness.secondWanted = true;
        },

        () => {
            harness.check(`two claimants at once is still one answer, got ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.immediate);
            GlobalStates.settingsOpen = false;
        },

        () => {
            harness.check(`the window closing under the other claimant does not take the`
                          + ` faster flush with it, got ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.immediate);
            harness.secondWanted = false;
        },

        () => {
            harness.check(`...and the last claimant releasing restores the debounce, got`
                          + ` ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.debounced);
            doomedClaim.active = true;
        },

        () => {
            harness.check(`a claim declared inside a Loader is held, got ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.immediate);
            doomedClaim.active = false;
        },

        () => {
            harness.check(`destroying the object that made a claim releases it, got`
                          + ` ${Config.readWriteDelay}ms`,
                          Config.readWriteDelay === harness.debounced);
            harness.check(`...and the claim count is back to nothing rather than merely`
                          + ` resolving to the default, got ${Config.immediateWriteClaims}`,
                          Config.immediateWriteClaims === 0);
        },

        () => harness.finish()
    ]

    property int stepIndex: 0
    Timer {
        id: steps
        interval: 300
        repeat: true
        onTriggered: {
            if (harness.stepIndex >= harness.stepList.length)
                return;
            harness.stepList[harness.stepIndex++]();
        }
    }
}
