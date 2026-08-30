import QtTest
import "../modules/common/plugins/designsystem/services/currency_history.js" as History

// The currency widget's 24-hour memory. Times in ms; H is one hour.
TestCase {
    name: "CurrencyHistoryTest"
    readonly property real hourMs: 3600 * 1000
    readonly property real nowMs: 1000 * hourMs

    function sampleRun(hours) {
        let list = [];
        for (const h of hours)
            list = History.pushSample(list, nowMs - h * hourMs, "USD", { EUR: 1 + h * 0.01 });
        return list;
    }

    function test_a_day_of_samples_survives_and_older_ones_fall_off() {
        const list = sampleRun([30, 26, 24, 12, 6, 0]);
        compare(list.length, 4, "30h and 26h are gone; 24h is inside the slack");
    }

    function test_a_change_of_base_clears_the_ring() {
        let list = History.pushSample([], nowMs - hourMs, "USD", { EUR: 1 });
        list = History.pushSample(list, nowMs, "EGP", { EUR: 2 });
        compare(list.length, 1);
        compare(list[0].base, "EGP");
    }

    function test_a_hot_retry_replaces_the_last_sample() {
        let list = History.pushSample([], nowMs - 60000, "USD", { EUR: 1 });
        list = History.pushSample(list, nowMs, "USD", { EUR: 2 });
        compare(list.length, 1, "two samples a minute apart are one");
        compare(list[0].rates.EUR, 2, "and the newer value wins");
    }

    function test_the_delta_reads_a_day_back_and_declares_a_direction() {
        const list = sampleRun([24, 12, 0]);
        const change = History.changeOf(list, "EUR", nowMs, 1.0);
        // 24h ago EUR was 1.24; now 1.0.
        fuzzyCompare(change.pct, (1.0 - 1.24) / 1.24 * 100, 0.001);
        compare(change.direction, -1);
        const flat = History.changeOf(list, "EUR", nowMs, 1.24);
        compare(flat.direction, 0, "the dead band holds a wobble at flat");
    }

    function test_one_sample_is_no_delta_and_no_line() {
        const list = sampleRun([0]);
        compare(History.changeOf(list, "EUR", nowMs, 1.0), null,
                "a value against itself is a claim nothing measured");
        compare(History.seriesFor(list, "EUR", nowMs).length, 0);
    }

    function test_the_series_is_normalised_into_the_unit_box() {
        const list = sampleRun([24, 18, 12, 6, 0]);
        const series = History.seriesFor(list, "EUR", nowMs);
        compare(series.length, 5);
        for (const p of series) {
            verify(p.x >= 0 && p.x <= 1);
            verify(p.y >= 0 && p.y <= 1);
        }
        verify(series[0].x < series[series.length - 1].x, "time runs left to right");
        // Rates fall towards now in sampleRun, so the line rises (y grows).
        verify(series[0].y < series[series.length - 1].y);
    }

    function test_the_footer_stamp_speaks_minutes_then_hours() {
        compare(History.agoLabel(nowMs, nowMs - 30000), "just now");
        compare(History.agoLabel(nowMs, nowMs - 2 * 60000), "2m ago");
        compare(History.agoLabel(nowMs, nowMs - 3 * hourMs), "3h ago");
        compare(History.agoLabel(nowMs, 0), "");
        compare(History.agoLabel(nowMs, nowMs + 30000), "just now",
                "a refresh newer than the widget's minute-tick is not the future");
    }
}
