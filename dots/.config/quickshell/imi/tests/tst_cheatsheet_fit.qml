import QtTest
import "../modules/common/functions/cheatsheetFit.js" as Fit

// The cheatsheet window is fixed-size and as tall as its tallest page, so the
// pages have to fit the screen themselves. These are the three screens the
// clipping was measured on, in a nested Hyprland with this machine's config
// (bar reserving 45 at the top, dock 65 at the bottom, gaps of 5).
TestCase {
    name: "CheatsheetFitTest"

    readonly property var reserved: [0, 45, 0, 65]
    readonly property int gap: 5
    // Padding 20 on both sides, the 56px toolbar, its 4px top margin and the
    // column's 10px gap - what Cheatsheet.qml puts around a page.
    readonly property int chrome: 20 * 2 + 56 + 4 + 10
    // The Elements page's natural size: 18 columns of 70px tiles with 6px gaps
    // across, 9 rows plus a 20px gap down.
    readonly property int elementsWidth: 18 * 70 + 17 * 6
    readonly property int elementsHeight: 9 * 70 + 8 * 6 + 20

    function test_the_usable_height_subtracts_both_reserved_edges_and_a_gap_each_side() {
        compare(Fit.usableHeight(1080, reserved, gap), 1080 - 45 - 65 - 10);
        compare(Fit.usableHeight(864, reserved, gap), 864 - 45 - 65 - 10);
        compare(Fit.usableHeight(720, reserved, gap), 720 - 45 - 65 - 10);
    }

    function test_the_usable_width_reads_the_horizontal_pair() {
        compare(Fit.usableWidth(1920, [30, 45, 10, 65], gap), 1920 - 30 - 10 - 10);
    }

    function test_an_unknown_reserved_area_costs_only_the_gaps() {
        // HyprlandData has not answered yet, or the monitor is not in its
        // list: the window is not told about a reserve it cannot see.
        compare(Fit.usableHeight(1080, undefined, gap), 1070);
        compare(Fit.usableHeight(1080, null, gap), 1070);
        compare(Fit.usableHeight(1080, [], gap), 1070);
        compare(Fit.usableHeight(1080, [0, "x", 0, null], gap), 1070);
    }

    function test_the_page_budget_is_what_the_chrome_leaves_and_never_negative() {
        compare(Fit.pageBudget(970, chrome), 970 - chrome);
        compare(Fit.pageBudget(50, chrome), 0);
    }

    function test_a_1080p_screen_at_scale_one_leaves_the_elements_page_alone() {
        const budget = Fit.pageBudget(Fit.usableHeight(1080, reserved, gap), chrome);
        compare(Fit.fitScale(elementsWidth, elementsHeight, 1900, budget), 1);
    }

    function test_the_two_fractional_scales_shrink_the_elements_page_into_the_budget() {
        // 1080p at 1.25x and at 1.5x, the two measured clippings.
        for (const logicalHeight of [864, 720]) {
            const budget = Fit.pageBudget(Fit.usableHeight(logicalHeight, reserved, gap), chrome);
            const scale = Fit.fitScale(elementsWidth, elementsHeight, 1900, budget);
            verify(scale < 1, `${logicalHeight}px screen: scale ${scale} should shrink`);
            verify(scale > 0, `${logicalHeight}px screen: scale ${scale} collapsed`);
            fuzzyCompare(elementsHeight * scale, budget, 0.001);
        }
    }

    function test_the_width_binds_too_when_it_is_the_tighter_axis() {
        // A 1280px-wide screen with height to spare: 18 columns of tiles are
        // 1362 across, so the width is what shrinks the page.
        const scale = Fit.fitScale(elementsWidth, elementsHeight, 1200, 5000);
        fuzzyCompare(elementsWidth * scale, 1200, 0.001);
    }

    function test_an_unbounded_or_unmeasured_axis_does_not_scale() {
        compare(Fit.fitScale(elementsWidth, elementsHeight, 0, 0), 1);
        compare(Fit.fitScale(elementsWidth, elementsHeight, -1, -1), 1);
        compare(Fit.fitScale(0, 0, 500, 500), 1);
        compare(Fit.fitScale(NaN, NaN, 500, 500), 1);
    }

    function test_the_scale_never_grows_a_page_that_already_fits() {
        compare(Fit.fitScale(100, 100, 5000, 5000), 1);
    }

    function test_the_aspect_box_takes_a_share_and_holds_the_ratio() {
        // A wide budget binds on the height: 85% of 800 is 680, and the width
        // follows the 16:9 from there.
        const wide = Fit.aspectBox(1830, 800, 0.85, 16 / 9);
        fuzzyCompare(wide.height, 800 * 0.85, 0.001);
        fuzzyCompare(wide.width, wide.height * 16 / 9, 0.001);
        verify(wide.width <= 1830 * 0.85 + 0.001);

        // A tall budget binds on the width instead.
        const tall = Fit.aspectBox(1000, 2000, 0.85, 16 / 9);
        fuzzyCompare(tall.width, 1000 * 0.85, 0.001);
        fuzzyCompare(tall.height, tall.width * 9 / 16, 0.001);
    }

    function test_the_aspect_box_answers_zero_until_both_budgets_are_known() {
        // The caller keeps its fallback stage while the window has not
        // learned its screen; a NaN or a zero must not leak into geometry.
        for (const box of [
            Fit.aspectBox(0, 800, 0.85, 16 / 9),
            Fit.aspectBox(1830, 0, 0.85, 16 / 9),
            Fit.aspectBox(NaN, 800, 0.85, 16 / 9),
            Fit.aspectBox(1830, 800, 0, 16 / 9),
            Fit.aspectBox(1830, 800, 0.85, 0),
        ]) {
            compare(box.width, 0);
            compare(box.height, 0);
        }
    }
}
