import QtQuick
import Quickshell
import qs.modules.common

/**
 * Reads the shell's real motion catalogue back against a real config.json.
 *
 * The pure arithmetic is pinned by tests/tst_motion_policy.qml. What that
 * cannot see is the WIRING: whether every tier in Appearance.qml actually goes
 * through the policy, whether the interaction model's press and release go
 * through it too, and whether the stored config reaches any of it. A
 * multiplier that scales eight tiers and misses the ninth reads perfectly in
 * the source and leaves one class of motion frozen at its old speed.
 *
 * Every expected number arrives from the driver as a literal. Computing them
 * in here from the same module the shell uses would make the harness agree
 * with itself - the tautology AGENT.md records against the weather forecast
 * test, which compared a function to the expression that function ran.
 *
 * Launched once per case by tests/test_motion_multiplier_runtime.py, which
 * seeds a throwaway XDG_CONFIG_HOME. Never point it at a real config
 * directory - Config writes config.json.
 *
 *   MOTION_EXPECT_MOVE=500 ... XDG_CONFIG_HOME=$(mktemp -d) qs -p MotionMultiplierRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    function expected(name) {
        return Number(Quickshell.env(name));
    }

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[Motion] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function checkValue(label, actual, want) {
        harness.check(`${label} is ${want}, got ${actual}`, actual === want);
    }

    function finish() {
        console.log(`[Motion] checks: ${harness.checksRun} failures: ${harness.failures}`);
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

            const motion = Appearance.animation;
            // A spatial tier whose base comes from animationCurves...
            harness.checkValue("elementMove.duration",
                               motion.elementMove.duration, harness.expected("MOTION_EXPECT_MOVE"));
            // ...an effects tier whose base is a literal in Appearance.qml,
            // because the two are written differently and a scaling applied to
            // only one of the two spellings is the realistic mistake.
            harness.checkValue("elementMoveFaster.duration",
                               motion.elementMoveFaster.duration, harness.expected("MOTION_EXPECT_FASTER"));
            // The interaction model is a separate object from the tier
            // catalogue and fires on every hover and press in the shell.
            harness.checkValue("interaction press tier",
                               Appearance.interaction.tiers.press.duration,
                               harness.expected("MOTION_EXPECT_PRESS"));
            // A velocity is the reciprocal axis.
            harness.checkValue("elementMove.velocity",
                               motion.elementMove.velocity, harness.expected("MOTION_EXPECT_VELOCITY"));
            // And the stagger step, scaled the way a cascade scales it.
            harness.checkValue("scaled stagger step",
                               motion.scale(motion.staggerStep),
                               harness.expected("MOTION_EXPECT_STAGGER"));

            // The two stagger helpers are only ever called from a QML binding
            // in a widget the unit suite cannot build, so nothing else here
            // ever resolves them against a real engine - and a typed QML
            // function that does not resolve is a binding error at the call
            // site, not a compile failure, so DesignSystemCompile.qml would
            // pass on it too. Their answers are constants, independent of the
            // multiplier, so they need no expectation from the driver.
            harness.check("staggerRanks skips a hidden member",
                          motion.staggerRanks([true, false, true]).join(",") === "0,-1,1");
            harness.check("staggerDelay clamps a long ladder",
                          motion.staggerDelay(99, 10, 5) === motion.staggerDelay(5, 10, 5));
            harness.finish();
        }
    }
}
