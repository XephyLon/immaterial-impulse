import QtTest
import "../modules/common/functions/cavaBands.js" as CavaBands

// Reshaping the cava spectrum between the producer's band count and whatever a
// consumer draws.
//
// This exists because the two numbers were never equal: CavaService declared
// `barCount: 32` while the process emits 50 bars, and every consumer had its
// own idea of both the count and the 0..1000 range. The arithmetic that
// reconciles them is the one part of this that can be tested without a
// compositor, so it lives in a .js file and is tested here.
TestCase {
    name: "CavaBandsTest"

    function fifty(fill) {
        const out = [];
        for (let i = 0; i < 50; i++) out.push(fill);
        return out;
    }

    // --- resample ----------------------------------------------------------

    function test_matching_counts_pass_through_as_a_copy() {
        const src = [1, 2, 3];
        const out = CavaBands.resample(src, 3);
        compare(out, [1, 2, 3]);
        out[0] = 99;
        compare(src[0], 1, "the caller's array must not be aliased");
    }

    function test_an_absent_spectrum_still_fills_the_consumers_bars() {
        // cava is not running (or has not answered yet). A consumer's bar model
        // must keep its length, or a Repeater renders a ragged row.
        compare(CavaBands.resample([], 5), [0, 0, 0, 0, 0]);
        compare(CavaBands.resample(undefined, 3), [0, 0, 0]);
        compare(CavaBands.resample(null, 3), [0, 0, 0]);
    }

    function test_no_bars_asked_for_means_no_bars() {
        compare(CavaBands.resample([1, 2, 3], 0), []);
        compare(CavaBands.resample([1, 2, 3], -4), []);
    }

    function test_upsampling_interpolates_between_neighbours() {
        // 3 -> 5: the new bands land exactly halfway between their neighbours.
        compare(CavaBands.resample([0, 100, 0], 5), [0, 50, 100, 50, 0]);
    }

    function test_upsampling_keeps_both_ends() {
        const out = CavaBands.resample([10, 20, 30], 7);
        compare(out.length, 7);
        compare(out[0], 10);
        compare(out[6], 30);
    }

    function test_downsampling_averages_instead_of_dropping_a_peak() {
        // The bug this replaces: `Math.floor(i * n / target)` picks one index
        // per output band, so a peak sitting on an unpicked index vanishes.
        // Bucket 0 covers [0,1], bucket 1 covers [2,3].
        compare(CavaBands.resample([0, 1000, 0, 0], 2), [500, 0]);
    }

    function test_downsampling_the_real_shape_drops_no_source_band() {
        // The live case: the producer's 50 bands into the bar widget's 20 dots.
        // Every one of the 50 must reach exactly one dot - a nearest-index pick
        // reaches only 20 of them, and the other 30 are inaudible on screen no
        // matter how loud they are.
        for (let peak = 0; peak < 50; peak++) {
            const src = fifty(0);
            src[peak] = 1000;
            const out = CavaBands.resample(src, 20);
            compare(out.length, 20);
            let reached = 0;
            for (let i = 0; i < out.length; i++) {
                verify(!isNaN(out[i]), "band " + i + " is NaN");
                if (out[i] > 0) reached++;
            }
            compare(reached, 1, "source band " + peak + " reached " + reached + " dots");
        }
    }

    function test_downsampling_keeps_the_spectrums_shape() {
        const src = [];
        for (let i = 0; i < 50; i++) src.push(i * 20);
        const out = CavaBands.resample(src, 20);
        compare(out.length, 20);
        for (let i = 1; i < out.length; i++) {
            verify(out[i] > out[i - 1], "dot " + i + " broke the rising ramp");
        }
    }

    function test_one_band_out_is_the_whole_spectrums_average() {
        compare(CavaBands.resample([0, 100, 200, 300], 1), [150]);
    }

    function test_one_band_in_fills_every_output_band() {
        compare(CavaBands.resample([7], 4), [7, 7, 7, 7]);
    }

    function test_a_bucket_is_never_empty_just_under_the_source_count() {
        // 50 -> 49 gives every bucket one band except one, which gets two. A
        // floor()-only bucket range would divide by zero somewhere in here.
        const out = CavaBands.resample(fifty(400), 49);
        compare(out.length, 49);
        for (let i = 0; i < out.length; i++) compare(out[i], 400);
    }

    // --- normalize ---------------------------------------------------------

    function test_normalize_divides_by_the_producers_range() {
        compare(CavaBands.normalize([0, 250, 500, 1000], 1000), [0, 0.25, 0.5, 1]);
    }

    function test_normalize_clamps_an_overshoot() {
        // cava's autosens overshoots its own maximum; an unclamped level draws
        // a bar taller than the container it is measured against.
        compare(CavaBands.normalize([1400, -20], 1000), [1, 0]);
    }

    function test_normalize_without_a_range_yields_silence_not_infinity() {
        compare(CavaBands.normalize([1, 2, 3], 0), [0, 0, 0]);
        compare(CavaBands.normalize([1, 2], -1), [0, 0]);
    }

    // --- bands -------------------------------------------------------------

    function test_bands_reshapes_and_normalizes_in_one_call() {
        compare(CavaBands.bands([0, 1000, 0, 0], 2, 1000), [0.5, 0]);
    }

    function test_bands_of_a_silent_producer_are_a_full_row_of_zeros() {
        const out = CavaBands.bands([], 32, 1000);
        compare(out.length, 32);
        for (let i = 0; i < out.length; i++) compare(out[i], 0);
    }

    function test_bands_stay_inside_zero_to_one_for_the_live_shape() {
        const spectrum = [];
        for (let i = 0; i < 50; i++) spectrum.push(i * 30);
        const out = CavaBands.bands(spectrum, 20, 1000);
        compare(out.length, 20);
        for (let i = 0; i < out.length; i++) {
            verify(out[i] >= 0 && out[i] <= 1, "band " + i + " is " + out[i]);
        }
    }
}
