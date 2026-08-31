import QtQuick
import QtTest
import "../services/ai/ai_usage.js" as Usage

TestCase {
    name: "AiUsageFold"

    function test_a_response_lands_in_its_day_and_alltime() {
        const d1 = Usage.withResponse(null, "2026-08-31", { input: 10, output: 20, total: 30 }, true);
        compare(d1.days["2026-08-31"].total, 30);
        compare(d1.days["2026-08-31"].requests, 1);
        compare(d1.days["2026-08-31"].ok, 1);
        compare(d1.allTime.total, 30);
        const d2 = Usage.withResponse(d1, "2026-08-31", { input: 1, output: 2, total: 3 }, false);
        compare(d2.days["2026-08-31"].total, 33);
        compare(d2.days["2026-08-31"].err, 1);
        compare(d1.days["2026-08-31"].total, 30, "copy, not mutation");
    }

    function test_unreported_usage_counts_the_request_not_the_tokens() {
        const d = Usage.withResponse(null, "2026-08-31", { input: -1, output: -1, total: -1 }, true);
        compare(d.days["2026-08-31"].total, 0);
        compare(d.days["2026-08-31"].requests, 1);
    }

    function test_totals_since_sums_the_window() {
        let d = Usage.withResponse(null, "2026-08-20", { total: 5, input: 0, output: 0 }, true);
        d = Usage.withResponse(d, "2026-08-30", { total: 7, input: 0, output: 0 }, true);
        d = Usage.withResponse(d, "2026-08-31", { total: 11, input: 0, output: 0 }, true);
        compare(Usage.totalsSince(d, "2026-08-30").total, 18);
        compare(Usage.totalsSince(d, "2026-08-31").total, 11);
        compare(Usage.totalsSince(d, "2026-01-01").total, 23);
    }

    function test_prune_drops_old_days_keeps_alltime() {
        let d = Usage.withResponse(null, "2024-01-01", { total: 5, input: 0, output: 0 }, true);
        d = Usage.withResponse(d, "2026-08-31", { total: 7, input: 0, output: 0 }, true);
        const p = Usage.pruned(d, "2026-01-01");
        verify(!p.days["2024-01-01"]);
        compare(p.days["2026-08-31"].total, 7);
        compare(p.allTime.total, 12, "allTime keeps the full story");
    }
}
