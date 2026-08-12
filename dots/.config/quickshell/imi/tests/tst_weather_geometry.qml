import QtTest
import "../modules/common/plugins/designsystem/widgets/weather_geometry.js" as Geometry
import "../modules/common/plugins/designsystem/widgets/weather_shapes.js" as WeatherShapes

// The weather widget's shared-element geometry and the glyph container's
// shape space. Spans at scale 1: 1x1 = 132x108, 2x1 = 276x108, 3x1 = 420x108.
TestCase {
    name: "WeatherGeometryTest"

    function test_the_glyph_exists_at_every_span_with_its_own_shape() {
        const g3 = Geometry.glyphRect("3x1", 420, 108, 1);
        const g2 = Geometry.glyphRect("2x1", 276, 108, 1);
        const g1 = Geometry.glyphRect("1x1", 132, 108, 1);
        compare(g3.shape, "ghostish");
        compare(g2.shape, "panel");
        compare(g1.shape, "leaf");
        verify(g3.width === 72 && g3.height === 72, "floating square at 3x1");
        verify(g2.height === 108, "flush full-height panel at 2x1");
        compare(g1.rotation, -22, "the slanted leaf");
    }

    function test_the_leaf_hangs_off_the_card_corner() {
        // x + width > span width: the overflow is what the card's clip cuts,
        // the case the spec called out as the clip half of the design.
        const g1 = Geometry.glyphRect("1x1", 132, 108, 1);
        verify(g1.x + g1.width > 132, "overflows right");
        verify(g1.y + g1.height > 108, "overflows bottom");
    }

    function test_the_panel_is_flush_with_the_card_edge() {
        const g2 = Geometry.glyphRect("2x1", 276, 108, 1);
        compare(g2.x + g2.width, 276, "right edge on the card edge");
        compare(g2.y, 0);
    }

    function test_temperature_and_condition_exist_at_every_span() {
        for (const span of ["3x1", "2x1", "1x1"]) {
            verify(Geometry.temperatureRect(span, 420, 108, 1) !== null, span);
            verify(Geometry.conditionRect(span, 420, 108, 1) !== null, span);
        }
    }

    function test_scale_multiplies_the_glyph() {
        const at1 = Geometry.glyphRect("3x1", 420, 108, 1);
        const at2 = Geometry.glyphRect("3x1", 840, 216, 2);
        compare(at2.width, at1.width * 2);
        compare(at2.icon, at1.icon * 2);
    }

    // ---- the shape space ----

    function test_every_shape_pair_morphs_and_stays_bounded() {
        for (const pair of [["ghostish", "panel"], ["panel", "leaf"], ["ghostish", "leaf"]]) {
            for (const t of [0, 0.5, 1]) {
                const shape = WeatherShapes.containerAt(pair[0], pair[1], t);
                verify(shape.cubics.length > 0, pair + " at " + t);
                verify(shape.maxX - shape.minX > 0.3, "has width");
                verify(shape.maxX - shape.minX < 2, "not exploded");
            }
        }
    }

    function test_the_panel_shape_carries_its_aspect() {
        const panel = WeatherShapes.containerAt("panel", "panel", 1);
        const aspect = (panel.maxX - panel.minX) / (panel.maxY - panel.minY);
        fuzzyCompare(aspect, 76 / 108, 0.02,
                     "built AT aspect so the corners stay circular");
    }

    function test_mid_morph_is_strictly_between_the_endpoints() {
        const from = WeatherShapes.containerAt("ghostish", "ghostish", 1);
        const to = WeatherShapes.containerAt("panel", "panel", 1);
        const mid = WeatherShapes.containerAt("ghostish", "panel", 0.5);
        const w = s => s.maxX - s.minX;
        verify((w(mid) - w(from)) * (w(mid) - w(to)) < 0,
               "the morph travels, it does not snap");
    }
}
