import QtQuick
import QtTest
import "../modules/common/plugins/designsystem/widgets/visualizer_bands.js" as Bands

// Folding cava's 32 bands onto a cookie's 12 lobes, and the per-lobe envelope
// that keeps the outline from boiling at cava's frame rate.
TestCase {
    id: root
    name: "VisualizerBandsTest"

    // The shape the service actually hands over: a QML list, not a JS array.
    property list<real> sequenceBands: [1000, 0, 1000, 0]

    function ramp(count) {
        const values = [];
        for (let i = 0; i < count; i++)
            values.push(i * (1000 / (count - 1)));
        return values;
    }

    // --- 32 bands to 12 lobes ----------------------------------------------

    function test_thirty_two_bands_fold_to_twelve_lobes() {
        const levels = Bands.toLobes(ramp(32), 12, 1000);
        compare(levels.length, 12);
        for (let i = 0; i < levels.length; i++)
            verify(levels[i] >= 0 && levels[i] <= 1);
    }

    function test_bass_stays_at_lobe_zero_and_treble_at_the_last() {
        const levels = Bands.toLobes(ramp(32), 12, 1000);
        for (let i = 1; i < levels.length; i++)
            verify(levels[i] > levels[i - 1]);
        verify(levels[0] < 0.1);
        verify(levels[11] > 0.9);
    }

    function test_each_lobe_averages_its_own_contiguous_group() {
        const values = [];
        for (let i = 0; i < 32; i++)
            values.push(i * 10);
        const levels = Bands.toLobes(values, 12, 1000);
        // Groups are [floor(i*32/12), floor((i+1)*32/12)): 0-1, 2-4, 5-7, ...
        fuzzyCompare(levels[0], ((0 + 10) / 2) / 1000, 1e-12);
        fuzzyCompare(levels[1], ((20 + 30 + 40) / 3) / 1000, 1e-12);
        fuzzyCompare(levels[11], ((290 + 300 + 310) / 3) / 1000, 1e-12);
    }

    function test_a_flat_spectrum_gives_every_lobe_the_same_level() {
        const values = [];
        for (let i = 0; i < 32; i++)
            values.push(400);
        const levels = Bands.toLobes(values, 12, 1000);
        for (let i = 0; i < 12; i++)
            fuzzyCompare(levels[i], 0.4, 1e-12);
    }

    function test_a_band_belongs_to_exactly_one_lobe() {
        // One loud band must move one lobe, not two - the group boundaries have
        // to meet without overlapping or leaving a gap.
        for (let loud = 0; loud < 32; loud++) {
            const values = [];
            for (let i = 0; i < 32; i++)
                values.push(i === loud ? 1000 : 0);
            const levels = Bands.toLobes(values, 12, 1000);
            let moved = 0;
            for (let i = 0; i < 12; i++)
                if (levels[i] > 0)
                    moved++;
            compare(moved, 1);
        }
    }

    // --- what arrives before cava has said anything ------------------------

    function test_no_values_at_all_rests_every_lobe() {
        const levels = Bands.toLobes([], 12, 1000);
        compare(levels.length, 12);
        for (let i = 0; i < 12; i++)
            compare(levels[i], 0);
    }

    function test_undefined_values_rest_every_lobe() {
        const levels = Bands.toLobes(undefined, 12, 1000);
        compare(levels.length, 12);
        for (let i = 0; i < 12; i++)
            compare(levels[i], 0);
    }

    function test_fewer_bands_than_lobes_still_fills_every_lobe() {
        const levels = Bands.toLobes([1000, 800, 600, 400, 200], 12, 1000);
        compare(levels.length, 12);
        for (let i = 0; i < 12; i++)
            verify(isFinite(levels[i]));
        fuzzyCompare(levels[0], 1, 1e-12);
        fuzzyCompare(levels[11], 0.2, 1e-12);
        // A lobe left without a group would rest at zero while the rest played.
        for (let i = 0; i < 12; i++)
            verify(levels[i] > 0);
    }

    function test_no_lobes_asks_for_nothing() {
        compare(Bands.toLobes(ramp(32), 0, 1000).length, 0);
    }

    function test_a_sequence_of_bands_is_read_like_an_array() {
        const levels = Bands.toLobes(root.sequenceBands, 4, 1000);
        compare(levels.length, 4);
        fuzzyCompare(levels[0], 1, 1e-12);
        fuzzyCompare(levels[1], 0, 1e-12);
        fuzzyCompare(levels[2], 1, 1e-12);
    }

    // --- range -------------------------------------------------------------

    function test_levels_stay_inside_zero_to_one() {
        const levels = Bands.toLobes([4000, -500, 1000, 0], 4, 1000);
        compare(levels[0], 1);
        compare(levels[1], 0);
        compare(levels[2], 1);
        compare(levels[3], 0);
    }

    // --- the envelope ------------------------------------------------------

    function test_attack_is_faster_than_decay() {
        const rise = Bands.envelope(0, 1, 0.55, 0.12);
        const fall = 1 - Bands.envelope(1, 0, 0.55, 0.12);
        verify(rise > fall);
    }

    function test_a_lobe_converges_on_its_target_without_overshooting() {
        let level = 0;
        for (let i = 0; i < 200; i++) {
            level = Bands.envelope(level, 0.7, 0.55, 0.12);
            verify(level <= 0.7);
        }
        fuzzyCompare(level, 0.7, 1e-6);
    }

    function test_a_lobe_falls_back_to_rest_when_the_music_stops() {
        let level = 1;
        for (let i = 0; i < 500; i++)
            level = Bands.envelope(level, 0, 0.55, 0.12);
        fuzzyCompare(level, 0, 1e-6);
    }
}
