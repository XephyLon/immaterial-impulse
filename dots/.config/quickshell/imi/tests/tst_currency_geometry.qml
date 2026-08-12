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

    function test_the_panel_shape_carries_its_aspect() {
        const panel = CurrencyShapes.containerAt("panel", "panel", 1);
        const aspect = (panel.maxX - panel.minX) / (panel.maxY - panel.minY);
        fuzzyCompare(aspect, 140 / 108, 0.02);
    }
}
