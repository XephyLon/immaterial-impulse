import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Drives MaterialThemeLoader against a real generated colors.json rewritten
 * the way matugen rewrites it (truncate, then write) and watches
 * Appearance.m3colors follow: how soon the first change lands, whether the
 * roles travel (an intermediate value between old and new) instead of
 * snapping, and that the final value is the new palette.
 *
 * The loader used to apply on a fixed 20 ms timer that read text() before
 * the async reload had finished (stale palette, "sometimes takes a while")
 * and with animated=false (no transition). Launched by
 * tests/test_theme_reload_runtime.py with a throwaway XDG_STATE_HOME.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    readonly property string themePath: Directories.generatedMaterialThemePath
    readonly property color oldPrimary: "#202020"
    readonly property color newPrimary: "#e0e0e0"
    property int firstChangeMs: -1
    property bool sawIntermediate: false
    property int settledMs: -1
    property int sampleMs: 0
    // Keep the singleton alive - nothing else in this harness references it.
    readonly property var loader: MaterialThemeLoader

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[ThemeReload] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[ThemeReload] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    // 1. Wait for the seeded palette to land (startup apply).
    Timer {
        id: waitForStart
        interval: 50; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (Appearance.m3colors.m3primary !== harness.oldPrimary) {
                if (harness.elapsed >= 15000) {
                    harness.check(`startup palette applied (primary ${Appearance.m3colors.m3primary})`, false);
                    harness.finish();
                }
                return;
            }
            waitForStart.running = false;
            rewrite.running = true;
        }
    }
    // 2. Rewrite like matugen: truncate, then write.
    Process {
        id: rewrite
        command: ["bash", "-c", `: > "$1"; printf '%s' '{"primary":"#e0e0e0","background":"#f0f0f0"}' > "$1"`, "rewrite", harness.themePath]
        onExited: sample.running = true
    }
    // 3. Sample the role every 20 ms.
    Timer {
        id: sample
        interval: 20; repeat: true
        onTriggered: {
            harness.sampleMs += interval;
            const p = Appearance.m3colors.m3primary;
            if (harness.firstChangeMs < 0 && p !== harness.oldPrimary) harness.firstChangeMs = harness.sampleMs;
            if (p !== harness.oldPrimary && p !== harness.newPrimary) harness.sawIntermediate = true;
            if (harness.settledMs < 0 && p === harness.newPrimary) harness.settledMs = harness.sampleMs;
            const done = harness.settledMs >= 0 && harness.sampleMs >= harness.settledMs + 200;
            if (!done && harness.sampleMs < 4000) return;
            sample.running = false;
            harness.check(`first change within 500 ms (${harness.firstChangeMs} ms)`, harness.firstChangeMs >= 0 && harness.firstChangeMs <= 500);
            harness.check("the role travels through an intermediate value (animated)", harness.sawIntermediate);
            harness.check(`settles on the new palette (${harness.settledMs} ms)`, harness.settledMs >= 0 && harness.settledMs <= 3000);
            harness.finish();
        }
    }
}
