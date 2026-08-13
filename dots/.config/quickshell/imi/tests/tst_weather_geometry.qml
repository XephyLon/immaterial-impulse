import QtTest
import "../modules/common/plugins/designsystem/widgets/weather_geometry.js" as Geometry
import "../modules/common/plugins/designsystem/widgets/weather_shapes.js" as WeatherShapes

// The weather widget's shared-element geometry and the glyph container's
// shape space. Spans at scale 1: 1x1 = 132x108, 2x1 = 276x108, 3x1 = 420x108,
// 3x2 = 420x228.
TestCase {
    name: "WeatherGeometryTest"

    // Every span the widget offers, with the box the host gives it. Driving
    // the shared-element checks off this rather than off three literals is
    // what makes adding a span fail the tests that should notice it.
    readonly property var spans: [
        { name: "1x1", width: 132, height: 108 },
        { name: "2x1", width: 276, height: 108 },
        { name: "3x1", width: 420, height: 108 },
        { name: "3x2", width: 420, height: 228 }
    ]

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

    // ---- 3x2: the second row --------------------------------------------

    function test_the_shared_three_have_a_rect_at_every_span() {
        // The architecture's first rule: a shared element never has a null
        // rect, because null is a fade and these three never fade.
        for (const span of spans) {
            verify(Geometry.temperatureRect(span.name, span.width, span.height, 1) !== null,
                   "temperature at " + span.name);
            verify(Geometry.conditionRect(span.name, span.width, span.height, 1) !== null,
                   "condition at " + span.name);
            verify(Geometry.glyphRect(span.name, span.width, span.height, 1) !== null,
                   "glyph at " + span.name);
        }
    }

    function test_the_shared_three_travel_into_the_taller_card() {
        // 3x1 -> 3x2 is the transition a user reaches by pulling the grip
        // down. Every shared element must have somewhere new to go: an
        // element whose rect is identical across the pair reads as a card
        // growing around frozen content.
        const t1 = Geometry.temperatureRect("3x1", 420, 108, 1);
        const t2 = Geometry.temperatureRect("3x2", 420, 228, 1);
        verify(t2.y > t1.y, "the temperature drops into the taller band");
        verify(t2.size > t1.size, "and grows with the room");

        const c1 = Geometry.conditionRect("3x1", 420, 108, 1);
        const c2 = Geometry.conditionRect("3x2", 420, 228, 1);
        compare(c2.x, c1.x, "the condition holds its column");
        verify(c2.y > c1.y, "and drops with the temperature");

        const g1 = Geometry.glyphRect("3x1", 420, 108, 1);
        const g2 = Geometry.glyphRect("3x2", 420, 228, 1);
        compare(g2.shape, "ghostish", "the same shape, so it travels rather than morphs");
        verify(g2.width > g1.width, "the glyph grows");
        verify(g2.icon > g1.icon, "and so does what it holds");
    }

    function test_the_glyph_stays_inside_the_top_band_at_3x2() {
        // The forecast strip owns the bottom of the card; a glyph centred on
        // the whole card would sit on top of it.
        const glyph = Geometry.glyphRect("3x2", 420, 228, 1);
        const strip = Geometry.forecastStripRect("3x2", 420, 228, 1);
        verify(glyph.y + glyph.height <= strip.y, "the glyph clears the strip");
        verify(glyph.x + glyph.width <= 420, "and stays on the card");
    }

    function test_the_forecast_strip_has_exactly_one_home() {
        // Null everywhere else, and null is a fade: the strip has nothing to
        // travel to at a span with no room for it.
        compare(Geometry.forecastStripRect("1x1", 132, 108, 1), null);
        compare(Geometry.forecastStripRect("2x1", 276, 108, 1), null);
        compare(Geometry.forecastStripRect("3x1", 420, 108, 1), null);
        verify(Geometry.forecastStripRect("3x2", 420, 228, 1) !== null);
        compare(Geometry.bandDividerRect("3x1", 420, 108, 1), null);
        verify(Geometry.bandDividerRect("3x2", 420, 228, 1) !== null);
    }

    // ---- the sun arc's background layer ---------------------------------

    function test_the_sun_arc_has_no_home_at_1x1() {
        // The one span the curve does not fit: it always draws a whole day
        // plus a night margin at each end across whatever width it is given,
        // and at 132px that is steep enough to read as a diagonal streak
        // rather than as a day. Null is a fade, which is how the tree gets rid
        // of an element with nowhere to be.
        compare(Geometry.sunArcRect("1x1", 132, 108, 1), null);
        for (const span of spans) {
            if (span.name === "1x1") continue;
            verify(Geometry.sunArcRect(span.name, span.width, span.height, 1) !== null,
                   "the arc lives at " + span.name);
        }
    }

    function test_the_arcs_horizon_is_the_band_seam_at_3x2() {
        // No separate horizon is drawn at 3x2 - the curve's zero-crossing is
        // the hairline the card already draws between its bands. Derived, so
        // moving the seam cannot leave the curve crossing somewhere else.
        const arc = Geometry.sunArcRect("3x2", 420, 228, 1);
        const seam = Geometry.bandDividerRect("3x2", 420, 228, 1);
        compare(arc.horizonY, seam.y);
    }

    function test_the_arcs_apex_clears_the_horizon_without_leaving_the_card() {
        for (const span of spans) {
            const arc = Geometry.sunArcRect(span.name, span.width, span.height, 1);
            if (arc === null) continue;
            verify(arc.apexRise > 0, "the curve rises at " + span.name);
            verify(arc.horizonY - arc.apexRise > 0,
                   "and its apex is still inside the card at " + span.name);
            verify(arc.horizonY < span.height,
                   "the horizon is inside the card at " + span.name);
        }
    }

    function test_the_arc_travels_into_the_taller_card() {
        // The same rule as the shared three: an element present on both sides
        // of a span change must have somewhere new to go, or the card grows
        // around a frozen curve.
        const one = Geometry.sunArcRect("3x1", 420, 108, 1);
        const two = Geometry.sunArcRect("3x2", 420, 228, 1);
        verify(two.horizonY > one.horizonY, "the horizon drops into the second row");
        verify(two.apexRise > one.apexRise, "and the curve rises further with it");
    }

    function test_the_one_row_spans_share_the_arcs_shape() {
        // 1x1 fades to where 2x1 stands, so the two must agree: a curve that
        // came back at a different height would be a snap wearing a fade's
        // clothes.
        const two = Geometry.sunArcRect("2x1", 276, 108, 1);
        const three = Geometry.sunArcRect("3x1", 420, 108, 1);
        compare(two.horizonY, three.horizonY);
        compare(two.apexRise, three.apexRise);
    }

    function test_scale_multiplies_the_arc() {
        const plain = Geometry.sunArcRect("3x2", 420, 228, 1);
        const scaled = Geometry.sunArcRect("3x2", 630, 342, 1.5);
        fuzzyCompare(scaled.horizonY, plain.horizonY * 1.5, 0.0001);
        fuzzyCompare(scaled.apexRise, plain.apexRise * 1.5, 0.0001);
    }

    function test_the_strip_sits_inside_the_card_with_even_margins() {
        const strip = Geometry.forecastStripRect("3x2", 420, 228, 1);
        compare(strip.x, 20, "left margin");
        compare(420 - (strip.x + strip.width), 20, "and the same on the right");
        verify(strip.y + strip.height < 228, "clear of the bottom edge");
        const divider = Geometry.bandDividerRect("3x2", 420, 228, 1);
        verify(divider.y < strip.y, "the divider sits above the strip");
        compare(divider.x, strip.x, "and shares its margins");
        compare(divider.width, strip.width);
    }

    function test_the_day_cards_fill_the_strip_at_any_count() {
        // wttr.in answers with three days and OpenWeatherMap with four, and
        // #111 deliberately pads to neither - so the row is laid out from the
        // count it is handed. A layout that assumed one of them would leave a
        // hole on the other provider.
        const strip = Geometry.forecastStripRect("3x2", 420, 228, 1);
        for (const count of [1, 2, 3, 4]) {
            const first = Geometry.forecastCardRect(0, count, strip.width, strip.height, 1);
            const last = Geometry.forecastCardRect(count - 1, count, strip.width, strip.height, 1);
            compare(first.x, 0, count + " days start flush left");
            fuzzyCompare(last.x + last.width, strip.width, 0.001,
                         count + " days end flush right");
            compare(first.width, last.width, count + " days are equal width");
            compare(first.height, strip.height, "a card is the strip's full height");
        }
    }

    function test_the_day_cards_never_overlap() {
        const strip = Geometry.forecastStripRect("3x2", 420, 228, 1);
        for (const count of [2, 3, 4]) {
            for (let i = 1; i < count; i++) {
                const previous = Geometry.forecastCardRect(i - 1, count, strip.width, strip.height, 1);
                const current = Geometry.forecastCardRect(i, count, strip.width, strip.height, 1);
                verify(current.x >= previous.x + previous.width,
                       count + " days: card " + i + " clears its neighbour");
            }
        }
    }

    function test_an_out_of_range_or_empty_day_card_is_null() {
        // An empty forecast is a real state - OpenWeatherMap fetches it in a
        // separate request that can fail on its own - and it must not divide
        // by zero on the way to being hidden.
        compare(Geometry.forecastCardRect(0, 0, 380, 68, 1), null);
        compare(Geometry.forecastCardRect(-1, 3, 380, 68, 1), null);
        compare(Geometry.forecastCardRect(3, 3, 380, 68, 1), null);
    }

    function test_the_high_low_line_moves_down_with_the_temperature() {
        // It is the 3x2 fallback for an absent forecast, so it has a rect
        // there as well as at 3x1 - and it has to follow the bigger number it
        // sits under rather than staying where the 3x1 put it.
        const at3x1 = Geometry.highLowRect("3x1", 420, 108, 1);
        const at3x2 = Geometry.highLowRect("3x2", 420, 228, 1);
        verify(at3x2.y > at3x1.y);
        compare(Geometry.highLowRect("2x1", 276, 108, 1), null);
    }

    function test_the_pills_and_the_column_divider_follow_the_band() {
        const pills1 = Geometry.pillsRect("3x1", 420, 108, 1);
        const pills2 = Geometry.pillsRect("3x2", 420, 228, 1);
        compare(pills2.x, pills1.x, "the pills hold the condition's column");
        verify(pills2.y > pills1.y, "and drop with it");
        compare(Geometry.pillsRect("1x1", 132, 108, 1), null);

        const rule1 = Geometry.columnDividerRect("3x1", 420, 108, 1);
        const rule2 = Geometry.columnDividerRect("3x2", 420, 228, 1);
        compare(rule2.x, rule1.x, "the divider holds the column boundary");
        verify(rule2.height > rule1.height, "and grows into the taller band");
        verify(rule2.y + rule2.height
               <= Geometry.bandDividerRect("3x2", 420, 228, 1).y,
               "without crossing into the forecast band");
    }

    function test_scale_multiplies_the_second_row_too() {
        const at1 = Geometry.forecastStripRect("3x2", 420, 228, 1);
        const at2 = Geometry.forecastStripRect("3x2", 840, 456, 2);
        compare(at2.x, at1.x * 2);
        compare(at2.y, at1.y * 2);
        compare(at2.height, at1.height * 2);
        const card1 = Geometry.forecastCardRect(1, 3, at1.width, at1.height, 1);
        const card2 = Geometry.forecastCardRect(1, 3, at2.width, at2.height, 2);
        compare(card2.x, card1.x * 2);
        compare(card2.width, card1.width * 2);
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
