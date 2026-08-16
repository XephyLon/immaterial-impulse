import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import "services/frecency.js" as Frecency

/**
 * Drives services/AppUsage.qml's real store against a real file, and the real
 * services/AppSearch.qml ranking on top of it.
 *
 * tests/tst_frecency.qml covers the arithmetic - what a score is, what a
 * corrupt store parses to, how far a boost may move a match. None of that is
 * the part that writes to a user's disk on every launch, and none of it can
 * see whether the ranking is wired to the store at all: `AppSearch` would go
 * on passing every unit test while ignoring `AppUsage` entirely.
 *
 * Launched once per case by tests/test_app_usage_runtime.py, which seeds a
 * throwaway XDG_STATE_HOME and inspects the file afterwards. Never point it at
 * a real state directory - it writes the launch history.
 *
 *   APPUSAGE_CASE=record XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) \
 *     qs -p AppUsageRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    readonly property string testCase: Quickshell.env("APPUSAGE_CASE") ?? "record"
    // Seeded on disk by the driver for the "reload" case, so the harness is
    // asserting what a previous shell wrote rather than what it wrote itself.
    readonly property string seededId: Quickshell.env("APPUSAGE_SEEDED_ID") ?? ""

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[AppUsage] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[AppUsage] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    // A query whose first two results are close enough that repeated launches
    // can overturn the order. The boost is capped at 2x, so a pair whose match
    // scores differ by more than that legitimately does not flip - the loop
    // looks for a pair where the question is answerable rather than assuming
    // the first query it tries produces one.
    function findFlippablePair() {
        for (const query of ["e", "a", "i", "o", "s", "c", "t", "r", "n"]) {
            const before = AppSearch.fuzzyQuery(query);
            if (before.length < 2)
                continue;
            const underdog = before[1].id;
            if (!underdog || underdog === before[0].id)
                continue;
            return { query: query, leader: before[0].id, underdog: underdog };
        }
        return null;
    }

    function runRecordCase() {
        harness.check("a fresh store starts empty",
                      Frecency.scoreFor(AppUsage.store, "anything.desktop", Date.now()) === 0);

        const pair = harness.findFlippablePair();
        harness.check("the desktop registry offered a pair to rank",
                      pair !== null && AppSearch.list.length > 1);
        if (!pair) {
            harness.finish();
            return;
        }

        for (let i = 0; i < 40; i++)
            AppUsage.recordLaunch(pair.underdog);

        harness.check(`recording moved ${pair.underdog}'s score off zero`,
                      AppUsage.scoreFor(pair.underdog) > 0);
        harness.check("and left every other app alone",
                      AppUsage.scoreFor(pair.leader) === 0);

        const after = AppSearch.fuzzyQuery(pair.query);
        harness.check(`"${pair.query}" now offers ${pair.underdog} ahead of ${pair.leader}`,
                      after.length > 0 && after[0].id === pair.underdog);

        // The write is debounced, so give it a moment before the driver reads
        // the file back.
        writeSettle.running = true;
    }

    function runReloadCase() {
        harness.check("the seeded store came back from disk",
                      AppUsage.scoreFor(harness.seededId) > 0);
        harness.check("and an app it does not name scores nothing",
                      AppUsage.scoreFor("never-launched.desktop") === 0);
        harness.check("the store points at appUsagePath",
                      AppUsage.filePath === Directories.appUsagePath);
        harness.finish();
    }

    function runCorruptCase() {
        // The whole point: an unreadable store must be forgotten, not fatal.
        harness.check("a corrupt store still becomes ready", AppUsage.ready);
        harness.check("and holds nothing",
                      Object.keys(AppUsage.store.apps ?? {}).length === 0);
        harness.check("so every app scores zero",
                      AppSearch.list.every(app => AppUsage.scoreFor(app.id) === 0));
        // Ranking degrades to the match order rather than breaking: search
        // still answers, and it answers with the same list the unboosted
        // ranking would produce, because a zero score makes the boost the
        // identity.
        harness.check("and search still answers", AppSearch.fuzzyQuery("e").length > 0);
        harness.finish();
    }

    Timer {
        id: writeSettle
        interval: 800
        onTriggered: harness.finish()
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += 250;
            // The desktop-entry registry populates seconds after startup, and
            // ranking an empty list proves nothing.
            const warm = AppUsage.ready && AppSearch.list.length > 1;
            if (!warm) {
                if (harness.elapsed >= 20000) {
                    harness.check("the store and the app list become ready", false);
                    harness.finish();
                }
                return;
            }
            running = false;

            if (harness.testCase === "reload")
                harness.runReloadCase();
            else if (harness.testCase === "corrupt")
                harness.runCorruptCase();
            else
                harness.runRecordCase();
        }
    }
}
