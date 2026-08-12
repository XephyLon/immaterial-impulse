import QtTest
import "../modules/common/plugins/resize-tension.js" as Tension

// The elastic resize's arithmetic: breakaway with carry, the bow's force
// curve, corner radii under load, and the bulged outline. Everything here is
// what the grip binds at runtime, scored against arithmetic rather than eyes -
// the on-screen half (does it *feel* heavy) is the design brief's demo, which
// these constants were tuned in.
TestCase {
    name: "ResizeTensionTest"

    // ---- breakaway ----

    function test_a_pull_short_of_the_threshold_gives_nothing() {
        const give = Tension.giveAxis(59, 60);
        compare(give.steps, 0);
        compare(give.remainder, 59, "the tension stays live, it is not eaten");
    }

    function test_crossing_the_threshold_gives_one_span_and_carries_the_rest() {
        const give = Tension.giveAxis(75, 60);
        compare(give.steps, 1);
        compare(give.remainder, 15, "leftover pull carries into the next span");
    }

    function test_a_long_drag_walks_several_spans_in_one_gesture() {
        const give = Tension.giveAxis(190, 60);
        compare(give.steps, 3);
        compare(give.remainder, 10);
    }

    function test_pulling_inward_gives_negative_steps() {
        const give = Tension.giveAxis(-130, 60);
        compare(give.steps, -2);
        compare(give.remainder, -10, "the remainder keeps the pull's sign");
    }

    // ---- stepping through the offered spans ----

    readonly property var offered: [
        { cols: 1, rows: 1 }, { cols: 2, rows: 1 },
        { cols: 2, rows: 2 }, { cols: 3, rows: 2 }
    ]

    function test_a_cols_step_prefers_the_same_row_count() {
        const next = Tension.stepSize(offered, { cols: 1, rows: 1 }, 1, 0);
        compare(next.cols, 2);
        compare(next.rows, 1, "1x1 grows to 2x1, not to 2x2");
    }

    function test_a_rows_step_prefers_the_same_column_count() {
        const next = Tension.stepSize(offered, { cols: 2, rows: 1 }, 0, 1);
        compare(next.cols, 2);
        compare(next.rows, 2);
    }

    function test_at_the_wall_the_current_span_is_returned() {
        const next = Tension.stepSize(offered, { cols: 3, rows: 2 }, 1, 0);
        compare(next.cols, 3, "no larger span exists - the tension rubber-bands");
        compare(next.rows, 2);
    }

    function test_shrinking_steps_downward() {
        const next = Tension.stepSize(offered, { cols: 2, rows: 2 }, 0, -1);
        compare(next.cols, 2);
        compare(next.rows, 1);
    }

    function test_an_empty_offer_list_changes_nothing() {
        const current = { cols: 2, rows: 1 };
        compare(Tension.stepSize([], current, 1, 0), current);
    }

    // ---- the bow ----

    function test_no_pull_no_bow() {
        compare(Tension.bow(0, 60, 14, 1.15), 0);
    }

    function test_full_tension_reaches_the_full_bow() {
        fuzzyCompare(Tension.bow(60, 60, 14, 1.15), 14, 0.001);
    }

    function test_the_ease_resists_first_and_gives_later() {
        // ease > 1: at half pull the bow is LESS than half the reach - the
        // material resists until force has been built.
        const half = Tension.bow(30, 60, 14, 1.15);
        verify(half < 7, "at half pull the bow is under half the reach, got " + half);
        verify(half > 0);
    }

    function test_the_bow_keeps_the_pulls_sign() {
        fuzzyCompare(Tension.bow(-60, 60, 14, 1.15), -14, 0.001);
    }

    function test_pull_past_the_threshold_does_not_bow_past_the_reach() {
        fuzzyCompare(Tension.bow(200, 60, 14, 1.15), 14, 0.001);
    }

    // ---- corners under load ----

    function test_at_rest_every_corner_keeps_the_cap() {
        const radii = Tension.cornerRadii(26, 0, 0, 14, 0.5);
        compare(radii.tl, 26);
        compare(radii.tr, 26);
        compare(radii.br, 26);
        compare(radii.bl, 26);
    }

    function test_under_load_the_pulled_corner_tightens_and_neighbours_open() {
        const radii = Tension.cornerRadii(26, 14, 14, 14, 0.5);
        verify(radii.br < 26, "the pulled corner tightens, got " + radii.br);
        verify(radii.tr > 26, "the corner pulled away from opens, got " + radii.tr);
        verify(radii.bl > 26);
        compare(radii.tl, 26, "the anchored corner keeps its rest radius");
    }

    function test_the_pulled_corner_never_collapses_to_a_point() {
        const radii = Tension.cornerRadii(26, 14, 14, 14, 5.0);
        verify(radii.br >= 2, "a floor keeps the corner a corner, got " + radii.br);
    }

    // ---- the outline ----

    function chainOk(outline) {
        const segs = outline.segments;
        let x = null, y = null, sx = null, sy = null;
        for (const seg of segs) {
            if (seg.op === "move") { x = seg.x; y = seg.y; sx = seg.x; sy = seg.y; continue; }
            x = seg.x; y = seg.y;
        }
        return Math.abs(x - sx) < 0.001 && Math.abs(y - sy) < 0.001;
    }

    function test_the_outline_closes_at_rest() {
        const radii = Tension.cornerRadii(26, 0, 0, 14, 0.5);
        verify(chainOk(Tension.outline(320, 112, 0, 0, radii, 0.85, 1.0)));
    }

    function test_the_outline_closes_under_full_load() {
        const radii = Tension.cornerRadii(26, 14, 14, 14, 0.5);
        verify(chainOk(Tension.outline(320, 112, 14, 14, radii, 0.85, 1.0)));
    }

    function test_the_outline_closes_when_shrinking() {
        const radii = Tension.cornerRadii(26, -14, -14, 14, 0.5);
        verify(chainOk(Tension.outline(96, 96, -14, -14, radii, 0.85, 1.0)));
    }

    function test_at_rest_the_outline_is_the_plain_rounded_rectangle() {
        const radii = Tension.cornerRadii(26, 0, 0, 14, 0.5);
        const segs = Tension.outline(320, 112, 0, 0, radii, 0.85, 1.0).segments;
        // The right edge's bulge control point sits ON the edge when bow is 0.
        compare(segs[3].cx, 320, "no bulge without tension");
        compare(segs[5].cy, 112);
    }

    function test_the_dragged_corner_leads_by_the_follow_factor() {
        const radii = Tension.cornerRadii(26, 0, 0, 14, 0.5);
        const segs = Tension.outline(320, 112, 10, 0, radii, 0.85, 1.0).segments;
        // corner x = w + bowX * follow; at follow 1.0 the corner carries the
        // whole bow, and the edge's control point carries it too.
        fuzzyCompare(segs[4].cx, 330, 0.001);
        compare(segs[3].cx, 330, "the edge control point rides the full bow");
    }
}
