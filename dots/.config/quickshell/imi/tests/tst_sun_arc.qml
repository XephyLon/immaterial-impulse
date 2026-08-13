import QtTest
import "../modules/common/plugins/designsystem/widgets/sun_arc.js" as SunArc
import "../modules/common/plugins/designsystem/widgets/weather_geometry.js" as Geometry

// The sun arc's arithmetic. The curve is the easy half; the clock is not.
TestCase {
    name: "SunArcTest"

    // The card the arc is drawn on, per span, at scale 1.
    readonly property var spans: [
        { name: "1x1", width: 132, height: 108 },
        { name: "2x1", width: 276, height: 108 },
        { name: "3x1", width: 420, height: 108 },
        { name: "3x2", width: 420, height: 228 }
    ]

    function test_it_reads_both_providers_clock_formats() {
        // OpenWeatherMap's, formatted en-US with seconds before publishing.
        compare(SunArc.minutesFromClock("6:29:14 AM"), 6 * 60 + 29);
        compare(SunArc.minutesFromClock("7:54:02 PM"), 19 * 60 + 54);
        // wttr.in's, already formatted and zero-padded.
        compare(SunArc.minutesFromClock("06:29 AM"), 6 * 60 + 29);
        compare(SunArc.minutesFromClock("07:54 PM"), 19 * 60 + 54);
        // and a 24-hour clock, which neither sends today and both might.
        compare(SunArc.minutesFromClock("19:54"), 19 * 60 + 54);
    }

    function test_midnight_and_midday_do_not_swap() {
        // The hour that breaks every naive parser: 12 AM is 00:xx and 12 PM
        // is 12:xx, not the other way round.
        compare(SunArc.minutesFromClock("12:30 AM"), 30);
        compare(SunArc.minutesFromClock("12:30 PM"), 12 * 60 + 30);
    }

    function test_an_unknown_time_is_admitted_not_guessed() {
        // "0" is what both providers' parsers write when the field was
        // missing. Read as midnight it would put the dot somewhere confident
        // and wrong for the whole day.
        compare(SunArc.minutesFromClock("0"), -1);
        compare(SunArc.minutesFromClock(""), -1);
        compare(SunArc.minutesFromClock("later"), -1);
        compare(SunArc.minutesFromClock("25:00"), -1);
        compare(SunArc.minutesFromClock("13:00 PM"), -1);
        compare(SunArc.minutesFromClock("6:75 AM"), -1);
        compare(SunArc.minutesFromClock(null), -1);
        compare(SunArc.minutesFromClock(1750000000), -1, "an epoch is not a clock");
    }

    function test_progress_runs_sunrise_to_sunset() {
        const rise = "06:00 AM", set = "06:00 PM";
        compare(SunArc.dayProgress(6 * 60, rise, set), 0);
        compare(SunArc.dayProgress(12 * 60, rise, set), 0.5, "midday is halfway");
        compare(SunArc.dayProgress(18 * 60, rise, set), 1);
    }

    function test_night_parks_the_dot_at_the_nearest_horizon() {
        const rise = "06:00 AM", set = "06:00 PM";
        compare(SunArc.dayProgress(3 * 60, rise, set), 0, "before sunrise");
        compare(SunArc.dayProgress(23 * 60, rise, set), 1, "after sunset");
        verify(!SunArc.isDaylight(3 * 60, rise, set));
        verify(!SunArc.isDaylight(23 * 60, rise, set));
        verify(SunArc.isDaylight(12 * 60, rise, set));
    }

    function test_an_impossible_day_returns_null_rather_than_a_number() {
        // A sunset before its sunrise is a polar summer, a missing field or a
        // provider hiccup. All three should stop the dot being drawn, and
        // none of them should produce a plausible-looking position.
        compare(SunArc.dayProgress(12 * 60, "06:00 PM", "06:00 AM"), null);
        compare(SunArc.dayProgress(12 * 60, "0", "0"), null);
        compare(SunArc.dayProgress(12 * 60, "06:00 AM", "06:00 AM"), null);
    }

    function test_the_window_shows_night_at_both_ends() {
        const window = SunArc.windowFor(0.25);
        verify(window.uRise > 0, "the card starts before sunrise");
        verify(window.uSet < 1, "and ends after sunset");
        fuzzyCompare(window.uRise, 0.25 / 1.5, 0.0001);
        fuzzyCompare(window.uSet, 1.25 / 1.5, 0.0001);
    }

    function test_phase_is_signed_so_night_can_be_told_from_day() {
        const window = SunArc.windowFor(0.25);
        fuzzyCompare(SunArc.phaseAt(window.uRise, window), 0, 0.0001);
        fuzzyCompare(SunArc.phaseAt(window.uSet, window), 1, 0.0001);
        verify(SunArc.phaseAt(0, window) < 0, "before dawn is negative");
        verify(SunArc.phaseAt(1, window) > 1, "after dusk is past one");
    }

    function test_the_curve_dips_below_the_horizon_outside_the_day() {
        fuzzyCompare(SunArc.heightAt(0, 40), 0, 0.0001);
        fuzzyCompare(SunArc.heightAt(1, 40), 0, 0.0001);
        fuzzyCompare(SunArc.heightAt(0.5, 40), 40, 0.0001, "highest at midday");
        verify(SunArc.heightAt(-0.2, 40) < 0, "pre-dawn hangs below");
        verify(SunArc.heightAt(1.2, 40) < 0, "and so does the evening");
    }

    function test_the_night_tails_flatten_instead_of_plunging() {
        // A plain continued sine leaves the frame at its steepest, which
        // reads as a fragment of a bigger curve rather than as a day.
        const plain = phase => Math.sin(phase * Math.PI) * 40;
        for (const phase of [-0.15, -0.3, 1.15, 1.3]) {
            const flattened = SunArc.heightAt(phase, 40, 0.35);
            verify(Math.abs(flattened) < Math.abs(plain(phase)),
                   `phase ${phase} is shallower than the raw sine`);
            verify(flattened < 0, `phase ${phase} is still below the horizon`);
        }
        // ...and the flattening grows with distance, so the tail levels off
        // rather than being uniformly scaled down.
        const near = Math.abs(SunArc.heightAt(-0.1, 40, 0.35));
        const mid = Math.abs(SunArc.heightAt(-0.25, 40, 0.35));
        const far = Math.abs(SunArc.heightAt(-0.4, 40, 0.35));
        verify(mid - near > far - mid, "the slope eases off as it goes out");
    }

    function test_the_join_at_the_horizon_has_no_corner() {
        // Day and night are the same curve: sampled either side of sunrise,
        // the step between samples stays small and same-signed.
        const step = 0.002;
        const before = SunArc.heightAt(-step, 40, 0.35);
        const at = SunArc.heightAt(0, 40, 0.35);
        const after = SunArc.heightAt(step, 40, 0.35);
        verify(Math.abs(at - before) < 1, "no jump into the night");
        verify(Math.abs(after - at) < 1, "no jump into the day");
        verify(before < at && at < after, "and it keeps going the same way");
    }

    // ---- the curve as card coordinates --------------------------------

    function test_the_curve_meets_the_horizon_at_both_horizons() {
        // y grows downward, so "on the horizon" is literally horizonY.
        const window = SunArc.windowFor(0.22);
        fuzzyCompare(SunArc.curveY(window.uRise, window, 80, 45, 0.35), 80, 0.0001);
        fuzzyCompare(SunArc.curveY(window.uSet, window, 80, 45, 0.35), 80, 0.0001);
    }

    function test_the_curve_hangs_below_the_horizon_at_the_cards_edges() {
        const window = SunArc.windowFor(0.22);
        verify(SunArc.curveY(0, window, 80, 45, 0.35) > 80, "dawn side dips");
        verify(SunArc.curveY(1, window, 80, 45, 0.35) > 80, "dusk side dips");
    }

    function test_the_marker_rides_the_line_the_canvas_strokes() {
        // The marker and the curve read the same expression, so the sun at
        // midday is ON the apex rather than near it - the failure this pins
        // is two spellings of one line drifting a few pixels apart, which
        // reads as a rounding artefact and never warns.
        const window = SunArc.windowFor(0.22);
        const rise = "06:00 AM", set = "06:00 PM";
        const u = SunArc.sunU(12 * 60, rise, set, window);
        fuzzyCompare(SunArc.curveY(u, window, 80, 45, 0.35), 80 - 45, 0.0001);
        // ...and at the quarter points, against ARITHMETIC rather than
        // against the expression curveY runs. The previous version computed
        // `80 - heightAt(phaseAt(u))` and compared it to curveY, which is
        // literally that function's body - so any error inside heightAt or
        // phaseAt appeared identically on both sides. Distorting the daylight
        // curve by 30% left this file fully green.
        //
        // Daylight is 06:00-18:00, so 09:00 and 15:00 are phase 0.25 and 0.75
        // (sin = √½) and 12:00 is the apex: 80 - 45·sin(φπ).
        const quarters = [[9 * 60, 48.1802], [12 * 60, 35.0], [15 * 60, 48.1802]];
        for (const [minutes, expected] of quarters) {
            const at = SunArc.sunU(minutes, rise, set, window);
            fuzzyCompare(SunArc.curveY(at, window, 80, 45, 0.35), expected, 0.001,
                         `curve at ${minutes / 60}:00`);
        }
    }

    function test_the_arc_reads_as_an_arc_at_every_span_it_lives_at() {
        // The bug this pins: at 1x1 the curve drew a whole day plus a night
        // margin at each end across 132px while still rising 45px, so what
        // showed either side of the temperature was a diagonal streak. What
        // separates a day from a streak is the ASPECT - how wide the daylight
        // stretch is against how far the curve rises in it - and three to one
        // is where the two visibly part company on this card.
        const window = SunArc.windowFor(SunArc.NIGHT_MARGIN);
        const dayFraction = window.uSet - window.uRise;
        const readable = 3;
        for (const span of spans) {
            const arc = Geometry.sunArcRect(span.name, span.width, span.height, 1);
            if (arc === null) continue;
            const aspect = (span.width * dayFraction) / arc.apexRise;
            verify(aspect >= readable,
                   `${span.name} carries the arc at ${aspect.toFixed(2)}:1`);
        }
        // ...and 1x1 is the span that cannot, which is the whole reason it has
        // no home: it would keep the shape it stands at while fading, and the
        // three one-row spans share that shape.
        const stands = Geometry.sunArcRect("2x1", 276, 108, 1);
        const at1x1 = (132 * dayFraction) / stands.apexRise;
        verify(at1x1 < readable, `1x1 would only manage ${at1x1.toFixed(2)}:1`);
    }

    function test_the_sun_sits_where_the_clock_says() {
        const window = SunArc.windowFor(0.25);
        const rise = "06:00 AM", set = "06:00 PM";
        fuzzyCompare(SunArc.sunU(12 * 60, rise, set, window),
                     (window.uRise + window.uSet) / 2, 0.0001);
        fuzzyCompare(SunArc.sunU(6 * 60, rise, set, window), window.uRise, 0.0001);
        // Deep night parks it at the card's edge rather than off the card.
        compare(SunArc.sunU(0, rise, set, window), 0);
        compare(SunArc.sunU(23 * 60 + 59, rise, set, window), 1);
        compare(SunArc.sunU(12 * 60, "0", "0", window), null);
    }
}
