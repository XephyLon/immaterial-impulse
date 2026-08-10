import QtTest
import "../modules/common/plugins/designsystem/widgets/shapes/path-length.js" as PathLength

// Arc length along a run of cubic Beziers. This is what lets a progress ring be
// stroked around a shape's own outline: `setLineDash` measures in path length,
// and a cubic does not carry one.
//
// Every case here is a path whose length is known independently - a straight
// line, a square, a quarter circle - so the sampling is scored against
// arithmetic rather than against its own output.
TestCase {
    name: "PathLengthTest"

    // A cubic whose controls sit on the line between its anchors is exactly
    // that line, so its length is the distance between them at any sampling.
    function line(x0, y0, x1, y1) {
        return {
            anchor0X: x0, anchor0Y: y0,
            control0X: x0 + (x1 - x0) / 3, control0Y: y0 + (y1 - y0) / 3,
            control1X: x0 + 2 * (x1 - x0) / 3, control1Y: y0 + 2 * (y1 - y0) / 3,
            anchor1X: x1, anchor1Y: y1
        };
    }

    // The standard cubic approximation of a quarter circle of radius 1: control
    // points at k = 4/3 * (sqrt(2) - 1) along the tangents. Its length is within
    // 0.02% of pi/2, which is far tighter than anything the sampling can fake.
    function quarterCircle() {
        const k = 0.5522847498307933;
        return {
            anchor0X: 1, anchor0Y: 0,
            control0X: 1, control0Y: k,
            control1X: k, control1Y: 1,
            anchor1X: 0, anchor1Y: 1
        };
    }

    function square() {
        return [line(0, 0, 10, 0), line(10, 0, 10, 10),
            line(10, 10, 0, 10), line(0, 10, 0, 0)];
    }

    // --- lengths -----------------------------------------------------------

    function test_a_straight_cubic_measures_its_own_span() {
        fuzzyCompare(PathLength.cubicLength(line(0, 0, 30, 0)), 30, 1e-9);
        fuzzyCompare(PathLength.cubicLength(line(0, 0, 3, 4)), 5, 1e-9);
    }

    function test_a_quarter_circle_measures_a_quarter_of_a_circle() {
        fuzzyCompare(PathLength.cubicLength(quarterCircle()), Math.PI / 2, 1e-3);
    }

    function test_a_square_measures_its_perimeter_side_by_side() {
        const measured = PathLength.measureCubics(square());
        fuzzyCompare(measured.total, 40, 1e-9);
        compare(measured.lengths.length, 5,
            "one more entry than cubics: the start of each, then the total");
        for (let i = 0; i <= 4; i++)
            fuzzyCompare(measured.lengths[i], i * 10, 1e-9);
    }

    function test_sampling_converges_from_below() {
        // The polyline through the curve is a chord walk, so it can only
        // under-estimate - which is why a coarse sample is safe and a wrong
        // accumulation (measuring anchor to anchor, say) shows up as a length
        // that does not move with the sample count.
        const coarse = PathLength.cubicLength(quarterCircle(), 2);
        const fine = PathLength.cubicLength(quarterCircle(), 64);
        const settled = PathLength.cubicLength(quarterCircle(), 4096);
        verify(coarse < fine, "a coarser sample must be shorter, not equal");
        verify(fine <= settled + 1e-9, "sampling must not overshoot the curve");
        // And the default sampling is already within a thousandth of settled on
        // a quarter circle - a far longer arc than any cubic in a rounded
        // polygon - which is why the measurement is worth paying once per
        // geometry change instead of refining it per frame.
        fuzzyCompare(PathLength.cubicLength(quarterCircle()), settled, 1e-3);
    }

    function test_an_empty_path_has_no_length_and_still_has_a_start() {
        const measured = PathLength.measureCubics([]);
        compare(measured.total, 0);
        compare(measured.lengths.length, 1);
        compare(measured.lengths[0], 0);
        compare(PathLength.measureCubics(undefined).total, 0);
        compare(PathLength.cubicLength(null), 0);
    }

    // --- dashes ------------------------------------------------------------

    function test_progress_becomes_an_on_run_of_that_fraction() {
        const total = PathLength.measureCubics(square()).total;
        compare(PathLength.dashForProgress(total, 0), [0, 40]);
        compare(PathLength.dashForProgress(total, 0.5), [20, 40]);
        compare(PathLength.dashForProgress(total, 1), [40, 40]);
    }

    function test_a_position_past_the_end_is_clamped_not_trusted() {
        // Players report a position past their own reported length routinely,
        // and a dash longer than the path draws a second lap over the first.
        compare(PathLength.dashForProgress(40, 2), [40, 40]);
        compare(PathLength.dashForProgress(40, -1), [0, 40]);
        compare(PathLength.dashForProgress(40, NaN), [0, 40]);
        compare(PathLength.dashForProgress(40, undefined), [0, 40]);
    }

    function test_a_path_with_no_length_dashes_to_nothing() {
        compare(PathLength.dashForProgress(0, 0.5), [0, 0]);
        compare(PathLength.dashForProgress(NaN, 0.5), [0, 0]);
    }
}
