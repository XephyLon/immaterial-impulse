import QtTest
import "../modules/common/plugins/gridSizes.js" as GridSizes

// Resolving a placed widget's component-grid span: what a manifest offers,
// which one a stored choice resolves to, and which one a drag snaps to.
//
// The two rules worth pinning are both about refusing to guess. A `sizes` list
// whose entries disagree with the manifest's own default is a manifest bug, and
// honouring it would resize a widget the user already placed; a stored span the
// manifest no longer offers is the same situation one upgrade later.
TestCase {
    name: "GridSizesTest"

    function mediaGrid() {
        return {
            cols: 3, rows: 2,
            sizes: [{ cols: 3, rows: 2 }, { cols: 2, rows: 2 }, { cols: 2, rows: 1 }]
        };
    }

    // --- what a manifest offers -------------------------------------------

    function test_no_grid_at_all_is_content_sized() {
        // Every widget that predates the grid, and every full-bleed one.
        compare(GridSizes.offeredSizes(undefined).length, 0);
        compare(GridSizes.defaultSize(undefined), null);
        compare(GridSizes.resolveSize(undefined, "2x2"), null);
        compare(GridSizes.resizable(undefined), false);
    }

    function test_a_malformed_grid_is_content_sized_not_a_default() {
        const malformed = [null, [2, 2], "2x2", 3, { cols: 0, rows: 2 },
            { cols: 2.5, rows: 1 }, { cols: 13, rows: 1 }, { cols: "2", rows: 2 }];
        for (const grid of malformed) {
            compare(GridSizes.offeredSizes(grid).length, 0,
                "should offer nothing: " + JSON.stringify(grid));
        }
    }

    function test_a_grid_without_sizes_offers_exactly_its_own_span() {
        // notes, user-card and image-converter all look like this, and none of
        // them may grow a handle.
        const offered = GridSizes.offeredSizes({ cols: 2, rows: 2 });
        compare(offered.length, 1);
        compare(offered[0].cols, 2);
        compare(offered[0].rows, 2);
        compare(GridSizes.resizable({ cols: 2, rows: 2 }), false);
    }

    function test_todays_grid_manifests_keep_the_span_they_have() {
        // notes, user-card and image-converter are the three manifests that
        // ship a `grid`, all `{ "cols": 2, "rows": 2 }` with no `sizes`. Every
        // resolution path has to land back on 2x2 for them - including one
        // carrying a stored span, which a widget that was never resizable
        // should never have, but which a preset or a hand-edited state file
        // can still hand over.
        const grid = { cols: 2, rows: 2 };
        compare(GridSizes.formatSize(GridSizes.resolveSize(grid, undefined)), "2x2");
        compare(GridSizes.formatSize(GridSizes.resolveSize(grid, "3x2")), "2x2");
        compare(GridSizes.resizable(grid), false);
    }

    function test_each_axis_defaults_to_one_cell() {
        const offered = GridSizes.offeredSizes({ cols: 3 });
        compare(offered.length, 1);
        compare(offered[0].cols, 3);
        compare(offered[0].rows, 1);
    }

    function test_declared_sizes_are_offered_in_manifest_order() {
        const offered = GridSizes.offeredSizes(mediaGrid());
        compare(offered.length, 3);
        compare(GridSizes.formatSize(offered[0]), "3x2");
        compare(GridSizes.formatSize(offered[1]), "2x2");
        compare(GridSizes.formatSize(offered[2]), "2x1");
        compare(GridSizes.resizable(mediaGrid()), true);
    }

    function test_a_default_missing_from_sizes_rejects_the_whole_list() {
        // The manifest bug this exists for: honouring the list would move the
        // widget off the span it has always had, on upgrade, with no report.
        const grid = { cols: 3, rows: 2, sizes: [{ cols: 2, rows: 2 }, { cols: 2, rows: 1 }] };
        const offered = GridSizes.offeredSizes(grid);
        compare(offered.length, 1);
        compare(GridSizes.formatSize(offered[0]), "3x2");
        compare(GridSizes.resizable(grid), false);
    }

    function test_one_bad_entry_rejects_the_whole_list() {
        // Not "drops the bad entry and keeps the rest": the remaining two are
        // still a usable pair, so a widget would quietly start offering a set
        // of spans its author never wrote.
        const grid = { cols: 3, rows: 2,
            sizes: [{ cols: 3, rows: 2 }, { cols: 2, rows: 2 }, { cols: 0, rows: 4 }] };
        const offered = GridSizes.offeredSizes(grid);
        compare(offered.length, 1);
        compare(GridSizes.formatSize(offered[0]), "3x2");
        compare(GridSizes.resizable(grid), false);
    }

    function test_sizes_must_offer_more_than_one_span_to_count() {
        const grid = { cols: 2, rows: 2, sizes: [{ cols: 2, rows: 2 }] };
        compare(GridSizes.resizable(grid), false);
        compare(GridSizes.offeredSizes({ cols: 2, rows: 2, sizes: [] }).length, 1);
        compare(GridSizes.offeredSizes({ cols: 2, rows: 2, sizes: "2x2" }).length, 1);
    }

    function test_a_repeated_span_is_offered_once() {
        // Otherwise the resize walks through the same size twice and reads as
        // a dead step in the middle of the drag.
        const grid = { cols: 2, rows: 2, sizes: [{ cols: 2, rows: 2 }, { cols: 2, rows: 2 }, { cols: 2, rows: 1 }] };
        const offered = GridSizes.offeredSizes(grid);
        compare(offered.length, 2);
        compare(GridSizes.formatSize(offered[1]), "2x1");
    }

    // --- the stored choice -------------------------------------------------

    function test_a_stored_size_that_is_offered_wins() {
        const resolved = GridSizes.resolveSize(mediaGrid(), "2x1");
        compare(resolved.cols, 2);
        compare(resolved.rows, 1);
    }

    function test_a_stored_size_no_longer_offered_falls_back_to_the_default() {
        // The manifest changed under an installed widget.
        compare(GridSizes.formatSize(GridSizes.resolveSize(mediaGrid(), "4x4")), "3x2");
        compare(GridSizes.formatSize(GridSizes.resolveSize({ cols: 2, rows: 2 }, "3x2")), "2x2");
    }

    function test_an_unreadable_stored_value_falls_back_to_the_default() {
        const junk = [undefined, null, "", "2", "2x", "x2", "big", "2x2x2", 22, { cols: 2, rows: 1 }];
        for (const stored of junk) {
            compare(GridSizes.formatSize(GridSizes.resolveSize(mediaGrid(), stored)), "3x2",
                "should fall back: " + JSON.stringify(stored));
        }
    }

    function test_a_stored_value_round_trips_through_its_persisted_form() {
        for (const size of GridSizes.offeredSizes(mediaGrid())) {
            const text = GridSizes.formatSize(size);
            compare(GridSizes.formatSize(GridSizes.parseSize(text)), text);
        }
        compare(GridSizes.formatSize({ cols: 0, rows: 2 }), "");
    }

    // --- the drag snap -----------------------------------------------------

    // The media widget's three spans in pixels at scale 1.0, as
    // Appearance.sizes.widgetGridSpanX/Y measure them.
    function candidates() {
        return [
            { cols: 3, rows: 2, width: 420, height: 228 },
            { cols: 2, rows: 2, width: 276, height: 228 },
            { cols: 2, rows: 1, width: 276, height: 108 }
        ];
    }

    function test_the_snap_picks_the_span_the_pointer_is_nearest() {
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 420, 228)), "3x2");
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 280, 220)), "2x2");
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 270, 120)), "2x1");
    }

    function test_dragging_past_the_largest_span_stays_on_it() {
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 4000, 4000)), "3x2");
    }

    function test_dragging_below_the_smallest_span_stays_on_it() {
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 0, 0)), "2x1");
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), -500, -500)), "2x1");
    }

    function test_the_midpoint_between_two_spans_goes_to_the_earlier_one() {
        // 276 and 420 are the same height, so the boundary is exactly 348. A
        // pointer parked there must not flicker between the two.
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 348, 228)), "3x2");
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 347, 228)), "2x2");
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 349, 228)), "3x2");
    }

    function test_the_boundary_counts_both_axes() {
        // 276x228 and 276x108 differ only vertically: the boundary is 168.
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 276, 168)), "2x2");
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 276, 167)), "2x1");
        compare(GridSizes.formatSize(GridSizes.nearestSize(candidates(), 276, 169)), "2x2");
    }

    function test_the_snap_answers_nothing_rather_than_guessing() {
        compare(GridSizes.nearestSize([], 300, 200), null);
        compare(GridSizes.nearestSize(undefined, 300, 200), null);
        compare(GridSizes.nearestSize(candidates(), NaN, NaN), null);
    }

    // --- a `sizes` list that has crossed a QML model boundary ---------------

    // What a JS array looks like after a round trip through a Repeater's
    // `model`: same indices, same length, and `Array.isArray` false. Every
    // desktop widget is built from such a model (Background.qml), so this is
    // the shape the host really hands in - not the literal the harnesses
    // declare inline.
    function asVariantList(entries) {
        const like = { length: entries.length };
        for (let i = 0; i < entries.length; i++) like[i] = entries[i];
        return like;
    }

    function test_a_sizes_list_survives_the_model_round_trip() {
        const grid = { cols: 3, rows: 2, sizes: asVariantList(
            [{ cols: 3, rows: 2 }, { cols: 2, rows: 2 }, { cols: 2, rows: 1 }]) };
        verify(!Array.isArray(grid.sizes));
        compare(GridSizes.offeredSizes(grid).length, 3);
        verify(GridSizes.resizable(grid));
    }

    function test_a_sizes_value_that_is_not_a_list_is_still_rejected() {
        // The point of the relaxation is array-LIKE, not anything at all: a
        // malformed `sizes` must still fall back to the single declared span
        // rather than be read as an empty list of spans.
        compare(GridSizes.offeredSizes({ cols: 2, rows: 2, sizes: 5 }).length, 1);
        compare(GridSizes.offeredSizes({ cols: 2, rows: 2, sizes: "2x2" }).length, 1);
        compare(GridSizes.offeredSizes({ cols: 2, rows: 2, sizes: { cols: 2 } }).length, 1);
    }

    function test_the_snap_takes_a_round_tripped_candidate_list_too() {
        const list = asVariantList([
            { cols: 2, rows: 1, width: 276, height: 108 },
            { cols: 3, rows: 2, width: 420, height: 228 }]);
        compare(GridSizes.formatSize(GridSizes.nearestSize(list, 420, 228)), "3x2");
    }
}
