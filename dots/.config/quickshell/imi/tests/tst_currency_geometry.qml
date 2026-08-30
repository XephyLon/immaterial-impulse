import QtTest
import "../modules/common/plugins/designsystem/widgets/currency_geometry.js" as Geometry
import "../modules/common/plugins/designsystem/widgets/currency_shapes.js" as CurrencyShapes

// The currency widget's shared-element geometry and container shape space.
// Spans at scale 1: 1x1 = 132x108, 2x1 = 276x108.
TestCase {
    name: "CurrencyGeometryTest"

    function test_the_container_exists_at_both_spans_with_its_own_shape() {
        const c1 = Geometry.containerRect("1x1", 132, 108, 1);
        const c2 = Geometry.containerRect("2x1", 276, 108, 1);
        compare(c1.shape, "bun");
        compare(c2.shape, "panel");
        compare(c1.width, 34, "the badge");
        compare(c2.height, 108, "the flush full-height panel");
        compare(c2.x + c2.width, 276, "flush with the card edge");
    }

    function test_the_first_two_quotes_survive_and_the_rest_exit() {
        for (let i = 0; i < 4; i++) {
            const at2 = Geometry.quoteCellRect(i, "2x1", 276, 108, 1);
            verify(at2 !== null, "all four live in the panel");
            verify(at2.stacked, "stacked cells in the panel");
        }
        verify(Geometry.quoteCellRect(0, "1x1", 132, 108, 1) !== null);
        verify(Geometry.quoteCellRect(1, "1x1", 132, 108, 1) !== null);
        compare(Geometry.quoteCellRect(2, "1x1", 132, 108, 1), null,
                "null is a fade, never a morph");
        compare(Geometry.quoteCellRect(3, "1x1", 132, 108, 1), null);
        verify(!Geometry.quoteCellRect(0, "1x1", 132, 108, 1).stacked,
               "rows, not stacks, at 1x1");
    }

    function test_the_panel_cells_sit_inside_the_panel() {
        const panel = Geometry.containerRect("2x1", 276, 108, 1);
        for (let i = 0; i < 4; i++) {
            const cell = Geometry.quoteCellRect(i, "2x1", 276, 108, 1);
            verify(cell.x >= panel.x, "cell " + i + " inside the panel");
            verify(cell.x + cell.width <= panel.x + panel.width + 0.1);
        }
    }

    function test_the_word_to_is_its_own_element() {
        // The code used to read "to USD" at 1x1 and "USD" at 2x1 as one
        // element, so its text swapped mid-morph - a content snap.
        verify(Geometry.basePrefixRect("1x1", 132, 108, 1) !== null);
        compare(Geometry.basePrefixRect("2x1", 276, 108, 1), null,
                "no home at 2x1, so it fades");
        const prefix = Geometry.basePrefixRect("1x1", 132, 108, 1);
        const base = Geometry.baseLabelRect("1x1", 132, 108, 1);
        compare(prefix.y, base.y, "one line at 1x1");
        compare(prefix.size, base.size);
    }

    function test_the_base_label_grows_between_spans() {
        const at1 = Geometry.baseLabelRect("1x1", 132, 108, 1);
        const at2 = Geometry.baseLabelRect("2x1", 276, 108, 1);
        verify(at2.size > at1.size * 3, "tiny caption to giant code");
    }

    function test_every_shape_pair_morphs_with_mid_between_endpoints() {
        const from = CurrencyShapes.containerAt("bun", "bun", 1);
        const to = CurrencyShapes.containerAt("panel", "panel", 1);
        const mid = CurrencyShapes.containerAt("bun", "panel", 0.5);
        const w = s => s.maxX - s.minX;
        verify((w(mid) - w(from)) * (w(mid) - w(to)) < 0,
               "the morph travels, it does not snap");
    }

    function test_the_3x1_hero_block_owns_the_left_and_the_quotes_the_rest() {
        const hero = Geometry.baseLabelRect("3x1", 420, 108, 1);
        const divider = Geometry.dividerRect(0, "3x1", 420, 108, 1);
        verify(hero.x < divider.x, "the code lives left of the first divider");
        const chart = Geometry.chartRect("3x1", 420, 108, 1);
        verify(chart.x + chart.width <= divider.x + 0.01, "so does the chart");
        for (let i = 0; i < 4; i++) {
            const cell = Geometry.quoteCellRect(i, "3x1", 420, 108, 1);
            verify(cell !== null, "all four quotes live at 3x1");
            verify(cell.detailed, "with their movement column");
            verify(cell.x > divider.x, "right of the hero block");
            verify(cell.x + cell.width <= 420 - 13.9, "inside the card");
        }
        // The same reading order as the 2x1 panel: quotes 1-2 across the
        // top row, 3-4 across the bottom - a resize must not reshuffle
        // which quote sits where.
        const cell0 = Geometry.quoteCellRect(0, "3x1", 420, 108, 1);
        const cell1 = Geometry.quoteCellRect(1, "3x1", 420, 108, 1);
        const cell2 = Geometry.quoteCellRect(2, "3x1", 420, 108, 1);
        const divider1 = Geometry.dividerRect(1, "3x1", 420, 108, 1);
        verify(cell0.x + cell0.width <= divider1.x + 0.01,
               "quote 1 stops at the second divider");
        verify(cell1.x >= divider1.x, "quote 2 starts past it, beside quote 1");
        compare(cell0.y, cell1.y, "1 and 2 share the top row");
        compare(cell2.x, cell0.x, "quote 3 sits under quote 1");
        verify(cell2.y > cell0.y, "on the bottom row");
        const at2x1 = i => Geometry.quoteCellRect(i, "2x1", 276, 108, 1);
        verify((at2x1(1).x > at2x1(0).x) === (cell1.x > cell0.x),
               "both spans read the quotes in the same order");
    }

    function test_the_3x1_extras_exist_only_there() {
        for (const span of ["1x1", "2x1"]) {
            compare(Geometry.flagRect(span, 276, 108, 1), null);
            compare(Geometry.chartRect(span, 276, 108, 1), null);
            compare(Geometry.dividerRect(0, span, 276, 108, 1), null);
            compare(Geometry.updatedRect(span, 276, 108, 1), null);
        }
        verify(Geometry.flagRect("3x1", 420, 108, 1) !== null);
        verify(Geometry.updatedRect("3x1", 420, 108, 1) !== null);
    }

    function test_the_container_takes_the_chip_home_at_3x1() {
        const chip = Geometry.containerRect("3x1", 420, 108, 1);
        compare(chip.shape, "bun", "the badge shape returns, small, under the code");
        verify(chip.width < 60, "a chip, not a panel");
        verify(chip.y > 60, "at the hero block's foot");
    }

    function test_the_3x2_grows_the_3x1_without_moving_its_hero() {
        // The hero corner holds still on a 3x1 <-> 3x2 resize: same label,
        // same code, same flag, same chip - only the card under them grows.
        for (const fn of ["ratesLabelRect", "baseLabelRect", "flagRect"]) {
            const a = Geometry[fn]("3x1", 420, 108, 1);
            const b = Geometry[fn]("3x2", 420, 228, 1);
            compare(b.x, a.x, fn);
            compare(b.y, a.y, fn);
        }
        const chip1 = Geometry.containerRect("3x1", 420, 108, 1);
        const chip2 = Geometry.containerRect("3x2", 420, 228, 1);
        compare(chip2.x, chip1.x);
        compare(chip2.y, chip1.y, "the chip stays at the hero block's foot");
        compare(chip2.shape, "bun");
    }

    function test_the_3x2_cells_keep_the_reading_order_and_gain_trends() {
        for (let i = 0; i < 4; i++) {
            const cell = Geometry.quoteCellRect(i, "3x2", 420, 228, 1);
            verify(cell !== null && cell.trend, "cell " + i + " carries its trend chart");
        }
        const cell0 = Geometry.quoteCellRect(0, "3x2", 420, 228, 1);
        const cell1 = Geometry.quoteCellRect(1, "3x2", 420, 228, 1);
        const cell2 = Geometry.quoteCellRect(2, "3x2", 420, 228, 1);
        compare(cell0.y, cell1.y, "1 and 2 share the top row");
        compare(cell2.x, cell0.x, "3 sits under 1 - the 3x1's order, grown");
        verify(cell0.height > 80, "room for the numbers AND the chart");
        const at3x1 = Geometry.quoteCellRect(0, "3x1", 420, 108, 1);
        verify(at3x1.trend === undefined, "no trend charts in the single row");
    }

    function test_the_3x2_name_block_lives_under_the_hero() {
        const name = Geometry.nameRect("3x2", 420, 228, 1);
        const chart = Geometry.chart30Rect("3x2", 420, 228, 1);
        const caption = Geometry.caption30Rect("3x2", 420, 228, 1);
        const divider = Geometry.dividerRect(0, "3x2", 420, 228, 1);
        verify(name.y > 108, "below the hero block's storey");
        verify(name.y < chart.y && chart.y < caption.y, "name, chart, caption");
        for (const slot of [name, chart, caption])
            verify(slot.x + slot.width <= divider.x + 0.01, "left of the divider");
        compare(Geometry.nameRect("3x1", 420, 108, 1), null, "3x2 only");
        compare(Geometry.chart30Rect("2x1", 276, 108, 1), null);
    }

    function test_the_panel_shape_carries_its_aspect() {
        const panel = CurrencyShapes.containerAt("panel", "panel", 1);
        const aspect = (panel.maxX - panel.minX) / (panel.maxY - panel.minY);
        fuzzyCompare(aspect, 140 / 108, 0.02);
    }
}
