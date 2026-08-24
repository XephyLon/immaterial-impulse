import QtQuick
import Quickshell
import qs.services

/**
 * EasyEffects toggle honesty, against the real singleton and fake binaries.
 *
 * Driven by tests/test_easyeffects_state_runtime.py, which puts fake
 * `easyeffects`/`flatpak`/`pidof`/`pkill` executables at the front of PATH.
 * The fakes keep a little state of their own in $EE_STATE_DIR: launching
 * succeeds only while `launch_ok` exists (and then leaves a `running` marker
 * pidof answers from; pkill removes it), so the harness can drive both a
 * launch that fails and one that works.
 *
 * What it pins: enable() answers the click optimistically, and the verify
 * pass corrects the lie - a failed launch reads as off again within
 * verifyInterval, a real one stays on, and a kill stays off.
 *
 *   EE_STATE_DIR=... qs -p EasyEffectsStateRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int step: 0
    readonly property string stateDir: Quickshell.env("EE_STATE_DIR") ?? ""

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[EasyEffectsState] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[EasyEffectsState] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Component.onCompleted: {
        // The suite cannot wait out the production 1.5s grace.
        EasyEffects.verifyInterval = 300;
    }

    Timer {
        id: waitForDetection
        interval: 200
        repeat: true
        running: true
        property int elapsed: 0
        onTriggered: {
            elapsed += interval;
            if (!EasyEffects.available) {
                if (elapsed >= 15000) {
                    harness.check("the fake easyeffects was detected", false);
                    harness.finish();
                }
                return;
            }
            running = false;
            harness.check("the fake easyeffects was detected", true);
            harness.check("nothing is running at startup", EasyEffects.active === false);
            EasyEffects.enable();
            harness.check("enable answers the click at once", EasyEffects.active === true);
            afterFailedLaunch.start();
        }
    }

    Timer {
        // The fake launch failed (no launch_ok yet): the verify pass at 300ms
        // must take the optimistic flag back down. This is the bug - without
        // the verify, active stays true for the rest of the session.
        id: afterFailedLaunch
        interval: 900
        onTriggered: {
            harness.check("a failed launch is corrected to off", EasyEffects.active === false);
            Quickshell.execDetached(["touch", `${harness.stateDir}/launch_ok`]);
            allowLaunch.start();
        }
    }

    Timer {
        id: allowLaunch
        interval: 300
        onTriggered: {
            EasyEffects.enable();
            harness.check("the second enable is optimistic too", EasyEffects.active === true);
            afterRealLaunch.start();
        }
    }

    Timer {
        id: afterRealLaunch
        interval: 900
        onTriggered: {
            harness.check("a real launch survives the verify", EasyEffects.active === true);
            EasyEffects.disable();
            harness.check("disable answers the click at once", EasyEffects.active === false);
            afterKill.start();
        }
    }

    Timer {
        id: afterKill
        interval: 900
        onTriggered: {
            harness.check("a killed daemon stays off", EasyEffects.active === false);
            harness.finish();
        }
    }
}
