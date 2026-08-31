import QtTest
import "../modules/common/plugins/designsystem/services/currency_daily.js" as Daily

// The currency widget's month of daily closes. `nowMs` is a fixed UTC noon
// so date arithmetic cannot straddle a midnight.
TestCase {
    name: "CurrencyDailyTest"
    readonly property real dayMs: 86400000
    readonly property real nowMs: Date.UTC(2026, 7, 31, 12, 0, 0)

    function warmStore(days) {
        let store = { base: "EGP", days: {} };
        for (let back = days; back >= 1; back--) {
            const date = Daily.dateKey(nowMs - back * dayMs);
            store = Daily.foldSnapshot(store, "EGP", date,
                { USD: 50 + back * 0.1, EUR: 57 - back * 0.05 }, nowMs);
        }
        return store;
    }

    function test_wanted_dates_run_up_to_yesterday_never_today() {
        const dates = Daily.wantedDates(nowMs, 7);
        compare(dates.length, 7);
        compare(dates[6], "2026-08-30", "yesterday last");
        compare(dates[0], "2026-08-24");
        verify(!dates.includes("2026-08-31"), "today's snapshot is not published yet");
    }

    function test_missing_dates_shrink_as_the_store_warms() {
        const cold = Daily.missingDates(null, nowMs, 7, {});
        compare(cold.length, 7);
        const store = warmStore(5);
        const missing = Daily.missingDates(store, nowMs, 7, {});
        compare(missing.length, 2, "the two oldest of seven are still missing");
        const skipped = Daily.missingDates(store, nowMs, 7, { "2026-08-24": true });
        compare(skipped.length, 1, "a date recorded unavailable is not refetched");
    }

    function test_a_change_of_base_clears_the_store() {
        const store = warmStore(5);
        const next = Daily.foldSnapshot(store, "USD", "2026-08-30", { EUR: 0.9 }, nowMs);
        compare(Object.keys(next.days).length, 1);
        compare(next.base, "USD");
    }

    function test_old_dates_fall_off_on_fold() {
        let store = warmStore(3);
        store.days["2026-01-01"] = { USD: 1 };
        const next = Daily.foldSnapshot(store, "EGP", "2026-08-30",
            { USD: 50.1 }, nowMs);
        compare(next.days["2026-01-01"], undefined, "January is not on any chart");
        verify(next.days["2026-08-28"] !== undefined, "the window survives");
    }

    function test_the_trend_normalises_and_declares_a_direction() {
        const store = warmStore(7);
        // USD falls toward now in warmStore (50.7 -> 50.1).
        const trend = Daily.trendFor(store, "USD", nowMs, 7);
        compare(trend.points.length, 7);
        compare(trend.direction, -1);
        for (const p of trend.points) {
            verify(p.x >= 0 && p.x <= 1);
            verify(p.y >= 0 && p.y <= 1);
        }
        const rising = Daily.trendFor(store, "EUR", nowMs, 7);
        compare(rising.direction, 1, "EUR rises in warmStore");
    }

    function test_one_close_is_no_trend_at_all() {
        const store = warmStore(1);
        const trend = Daily.trendFor(store, "USD", nowMs, 7);
        compare(trend.points.length, 0, "the honest-quiet rule");
        compare(trend.direction, 0);
    }

    function test_gaps_are_absent_not_zero() {
        let store = warmStore(7);
        delete store.days["2026-08-27"];
        const closes = Daily.closesFor(store, "USD", nowMs, 7);
        compare(closes.length, 6, "a missing day is a shorter series");
        for (const close of closes)
            verify(close.value > 40, "never a zero point dragging the chart");
    }
    function test_movement_reads_the_last_two_closes() {
        const store = warmStore(5);
        // USD closes decline toward yesterday (50 + back * 0.1), so the
        // day-over-day step is 50.1 against 50.2.
        const change = Daily.changeFrom(store, "USD", nowMs);
        verify(change !== null);
        fuzzyCompare(change.abs, -0.1, 1e-9);
        fuzzyCompare(change.pct, -0.1 / 50.2 * 100, 1e-9);
        compare(change.direction, -1);
    }

    function test_movement_is_null_below_two_closes() {
        compare(Daily.changeFrom(null, "USD", nowMs), null);
        compare(Daily.changeFrom(warmStore(1), "USD", nowMs), null);
    }

    function test_movement_dead_band_reads_flat() {
        let store = { base: "EGP", days: {} };
        store = Daily.foldSnapshot(store, "EGP", Daily.dateKey(nowMs - 2 * dayMs),
            { USD: 50.0 }, nowMs);
        store = Daily.foldSnapshot(store, "EGP", Daily.dateKey(nowMs - 1 * dayMs),
            { USD: 50.000001 }, nowMs);
        const change = Daily.changeFrom(store, "USD", nowMs);
        verify(change !== null);
        compare(change.direction, 0, "inside the dead band the day is flat");
    }

}
