import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * Drives an OverlayLifecycle against the real motion catalogue: alive at
 * once on open with progress starting near 0 and landing on 1 within the
 * enter tier; on close, alive holds while progress falls, closed() fires and
 * only then alive drops, within the exit tier; a close during the enter
 * still ends closed; a re-open during the leave keeps the surface; and under
 * reduce-motion the same sequence completes at once and still fires.
 * Launched by tests/test_overlay_lifecycle_runtime.py.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    property int closedCount: 0
    property int openedCount: 0
    property real firstProgressSeen: -1
    property bool aliveWhenProgressFell: false
    property bool aliveAtClosed: true
    property double t0: 0

    function now() { return Date.now(); }
    function check(label, ok) {
        harness.checksRun++;
        console.log(`[Overlay] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[Overlay] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    OverlayLifecycle {
        id: life
        onOpened: harness.openedCount++
        onClosed: { harness.closedCount++; harness.aliveAtClosed = life.alive; }
        onProgressChanged: {
            if (harness.firstProgressSeen < 0 && life.wanted) harness.firstProgressSeen = life.progress;
            if (!life.wanted && life.progress < 1 && life.progress > 0) harness.aliveWhenProgressFell = life.alive;
        }
    }

    Timer {
        id: driver
        interval: 20; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 30000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready) return;
            const enterMs = Appearance.animation.overlayEnter.duration;
            const exitMs = Appearance.animation.overlayExit.duration;
            switch (harness.step) {
            case 0:
                Config.options.appearance.motion.reduceMotion = false;
                Config.options.appearance.motion.multiplier = 1.0;
                harness.check("tiers are real durations", enterMs > 100 && exitMs > 50 && exitMs < enterMs);
                harness.t0 = harness.now();
                life.wanted = true;
                harness.check("alive at once on open", life.alive === true);
                harness.check("progress starts near 0", life.progress < 0.2);
                harness.step = 1;
                break;
            case 1:
                if (life.progress < 1) { if (harness.now() - harness.t0 > enterMs + 400) { harness.check("enter lands within its tier", false); harness.step = 2; } return; }
                harness.check("enter lands within its tier (+ a frame or two)", harness.now() - harness.t0 <= enterMs + 400);
                harness.check("opened() fired once", harness.openedCount === 1);
                harness.check("first sampled progress was the start, not the end", harness.firstProgressSeen >= 0 && harness.firstProgressSeen < 0.5);
                harness.t0 = harness.now();
                life.wanted = false;
                harness.check("alive holds when the flag drops", life.alive === true);
                harness.step = 2;
                break;
            case 2:
                if (life.alive) { if (harness.now() - harness.t0 > exitMs + 400) { harness.check("leave finishes within its tier", false); harness.step = 3; } return; }
                harness.check("leave finishes within its tier (+ a frame or two)", harness.now() - harness.t0 <= exitMs + 400);
                harness.check("progress is 0 after the leave", life.progress === 0);
                harness.check("alive stayed true while progress fell", harness.aliveWhenProgressFell === true);
                harness.check("closed() fired once, after alive dropped", harness.closedCount === 1 && harness.aliveAtClosed === false);
                // A close during the enter still ends closed.
                life.wanted = true;
                life.wanted = false;
                harness.t0 = harness.now();
                harness.step = 3;
                break;
            case 3:
                if (life.alive && harness.now() - harness.t0 < exitMs + 600) return;
                harness.check("a close during the enter still ends closed", life.alive === false && harness.closedCount === 2);
                // A re-open during the leave keeps the surface alive.
                life.wanted = true;
                harness.step = 31;
                harness.t0 = harness.now();
                break;
            case 31:
                if (life.progress < 1) return;
                life.wanted = false;
                harness.step = 32;
                break;
            case 32:
                if (life.progress >= 1) return;   // wait for the leave to start
                life.wanted = true;
                harness.step = 33;
                harness.t0 = harness.now();
                break;
            case 33:
                if (harness.now() - harness.t0 < exitMs + enterMs + 200) return;
                harness.check("a re-open during the leave keeps the surface alive", life.alive === true && life.progress === 1 && harness.closedCount === 2);
                life.wanted = false;
                harness.step = 34;
                break;
            case 34:
                if (life.alive) return;
                // Reduce motion: immediate, and closed() still fires.
                Config.options.appearance.motion.reduceMotion = true;
                harness.step = 4;
                break;
            case 4:
                if (Appearance.animation.overlayEnter.duration !== 0) return;
                life.wanted = true;
                harness.check("reduce motion: open completes at once", life.alive === true && life.progress === 1);
                life.wanted = false;
                harness.check("reduce motion: close completes at once and still fires closed()", life.alive === false && harness.closedCount === 4);
                Config.options.appearance.motion.reduceMotion = false;
                harness.finish();
                break;
            }
        }
    }
}
