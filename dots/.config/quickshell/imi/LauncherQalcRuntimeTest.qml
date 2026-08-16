import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Counts the `qalc` processes a typed query actually spawns.
 *
 * The gate itself is pure logic and tests/tst_math_query.qml covers every shape
 * a query can be in - but the bug this pins was never in a predicate. It was in
 * where the spawn was fired from: `nonAppResultsTimer.restart()` lived inside
 * the `results` binding, which re-evaluates per keystroke *and* again when
 * `mathResult` lands, so the process count is a property of the binding graph
 * rather than of any function a unit test can call. Measured before the fix,
 * typing "firefox" started eight qalc processes.
 *
 * Launched once per case by tests/test_launcher_qalc_runtime.py, which puts a
 * counting stub named `qalc` first on PATH and passes the tally file in
 * QALC_COUNT_FILE. The harness types QALC_QUERY one character at a time,
 * QALC_KEYSTROKE_MS apart, with something reading `results` throughout - the
 * launcher list is what makes that binding evaluate at all, and a harness that
 * never reads it measures zero spawns however broken the code is, which is why
 * "results were observed" is one of the checks rather than an assumption.
 *
 *   QALC_QUERY=firefox QALC_COUNT_FILE=/tmp/tally QALC_EXPECT_MAX=0 \
 *     XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) \
 *     qs -p LauncherQalcRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0

    readonly property string query: Quickshell.env("QALC_QUERY") ?? "firefox"
    readonly property int keystrokeMs: parseInt(Quickshell.env("QALC_KEYSTROKE_MS") ?? "140")
    readonly property int settleMs: parseInt(Quickshell.env("QALC_SETTLE_MS") ?? "1500")
    readonly property int expectMin: parseInt(Quickshell.env("QALC_EXPECT_MIN") ?? "0")
    readonly property int expectMax: parseInt(Quickshell.env("QALC_EXPECT_MAX") ?? "0")

    property int typed: 0

    // Standing in for the launcher list. Without a live reader the `results`
    // binding is never evaluated and nothing spawns at all.
    property int observedResults: LauncherSearch.results.length
    property int peakResults: 0
    onObservedResultsChanged: harness.peakResults = Math.max(harness.peakResults, harness.observedResults)

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[LauncherQalc] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[LauncherQalc] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    function report(spawns) {
        harness.check(`the whole query reached the launcher (${LauncherSearch.query})`,
                      LauncherSearch.query === harness.query);
        harness.check(`the results binding was live (peak ${harness.peakResults} results)`,
                      harness.peakResults > 0);
        harness.check(`"${harness.query}" spawned ${spawns} qalc processes, wanted ${harness.expectMin}..${harness.expectMax}`,
                      spawns >= harness.expectMin && spawns <= harness.expectMax);
        harness.finish();
    }

    Timer {
        id: typist
        interval: harness.keystrokeMs
        repeat: true
        running: true
        onTriggered: {
            harness.typed++;
            LauncherSearch.query = harness.query.slice(0, harness.typed);
            if (harness.typed >= harness.query.length) {
                typist.running = false;
                settle.running = true;
            }
        }
    }

    Timer {
        id: settle
        interval: harness.settleMs
        onTriggered: harness.tallyPath = Quickshell.env("QALC_COUNT_FILE") ?? ""
    }

    // Held off the disk until the typing has settled. A FileView loads as soon
    // as it has a path, so declaring the real one up front reports the tally
    // from before a single character was typed - which is zero, i.e. the answer
    // the passing case wants, arrived at without running the case.
    property string tallyPath: ""

    // One line per invocation, appended by the stub the driver puts on PATH.
    FileView {
        id: tally
        path: harness.tallyPath
        onLoaded: harness.report(tally.text().split("\n").filter(line => line.length > 0).length)
        onLoadFailed: harness.report(0)
    }
}
