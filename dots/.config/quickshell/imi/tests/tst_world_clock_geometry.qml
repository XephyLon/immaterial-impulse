import QtTest
import "../modules/common/plugins/bundled/world-clock/world_clock_geometry.js" as Geometry

// The world clock's shared-element geometry: the four city tiles, which are
// the only thing the two spans have in common, and what each of them carries.
//
// Spans at scale 1: 2x2 = 276x228, 3x1 = 420x108.
TestCase {
    name: "WorldClockGeometryTest"

    readonly property real offsetWidth: 34   // a plausible "UTC+10"

    function widthOf(span) { return span === "3x1" ? 420 : 276; }
    function heightOf(span) { return span === "3x1" ? 108 : 228; }

    function tile(index, span) {
        return Geometry.cityTileRect(index, span, widthOf(span), heightOf(span), 1);
    }
    function name(span, index) {
        const box = tile(index, span);
        return Geometry.tileNameRect(span, box.width, box.height, 1, offsetWidth);
    }

    function test_all_four_cities_have_a_tile_at_both_spans() {
        for (const span of ["2x2", "3x1"])
            for (let i = 0; i < Geometry.TILES; i++)
                verify(tile(i, span) !== null, span + " tile " + i);
        compare(tile(-1, "2x2"), null);
        compare(tile(Geometry.TILES, "3x1"), null);
    }

    function test_the_chip_grid_is_two_by_two_inside_the_card_inset() {
        const first = tile(0, "2x2");
        const second = tile(1, "2x2");
        const third = tile(2, "2x2");
        compare(first.x, 12);
        compare(first.y, third.y - first.height - 6, "one row gap apart");
        compare(second.x, first.x + first.width + 6, "one column gap apart");
        compare(tile(3, "2x2").x + tile(3, "2x2").width, 276 - 12,
                "flush with the card inset");
        compare(tile(3, "2x2").y + tile(3, "2x2").height, 228 - 12);
        compare(first.width, second.width);
        compare(first.height, third.height);
    }

    function test_the_dial_row_is_four_across_on_its_own_tighter_inset() {
        const tiles = [0, 1, 2, 3].map(i => tile(i, "3x1"));
        compare(tiles[0].x, 8, "not the card inset - the dials are full-bleed tiles");
        compare(tiles[3].x + tiles[3].width, 420 - 8);
        compare(tiles[0].y, 8);
        compare(tiles[0].height, 108 - 16);
        for (let i = 1; i < 4; i++) {
            compare(tiles[i].width, tiles[0].width, "equal tiles");
            compare(tiles[i].x, tiles[i - 1].x + tiles[i - 1].width + 8);
        }
    }

    function test_a_chip_becomes_a_dial_rather_than_being_replaced_by_one() {
        for (let i = 0; i < Geometry.TILES; i++) {
            const chip = tile(i, "2x2");
            const dial = tile(i, "3x1");
            verify(dial.height > chip.height, "tile " + i + " grows tall");
            verify(dial.radius > chip.radius,
                   "tile " + i + " opens its corners on the way");
        }
    }

    function test_the_city_name_is_the_one_thing_both_spans_say() {
        for (let i = 0; i < Geometry.TILES; i++) {
            verify(name("2x2", i) !== null, "chip " + i);
            verify(name("3x1", i) !== null, "dial " + i);
        }
        const chip = name("2x2", 0);
        const dial = name("3x1", 0);
        verify(!chip.centred, "top-left of the chip, beside its offset");
        verify(dial.centred, "centred under the dial");
        verify(dial.y > chip.y, "and travels to the bottom of the tile");
    }

    function test_the_name_stops_where_the_offset_beside_it_starts() {
        const box = tile(0, "2x2");
        const label = Geometry.tileNameRect("2x2", box.width, box.height, 1, offsetWidth);
        const offset = Geometry.tileOffsetRect("2x2", box.width, box.height, 1, offsetWidth);
        compare(offset.x + offset.width, box.width - 12, "on the chip's own padding");
        verify(label.x + label.width <= offset.x, "the two never overlap");
        compare(label.y, offset.y, "one row");
    }

    function test_what_only_a_chip_can_say_has_no_home_on_a_dial() {
        const box = tile(0, "3x1");
        compare(Geometry.tileOffsetRect("3x1", box.width, box.height, 1, offsetWidth), null);
        compare(Geometry.tileTimeRect("3x1", box.width, box.height, 1), null);
        compare(Geometry.tileIconRect("3x1", box.width, box.height, 1), null);
    }

    function test_the_chip_rows_stay_inside_the_chip() {
        const box = tile(0, "2x2");
        const time = Geometry.tileTimeRect("2x2", box.width, box.height, 1);
        const icon = Geometry.tileIconRect("2x2", box.width, box.height, 1);
        const label = Geometry.tileNameRect("2x2", box.width, box.height, 1, offsetWidth);
        compare(time.x, label.x, "the name and the time share a left edge");
        verify(time.y > label.y + label.height - 0.01, "and the time is the row below");
        verify(time.y + time.height <= box.height, "inside the chip");
        compare(icon.x + icon.width, box.width - 12, "on the chip's own padding");
    }

    function test_the_dial_reserves_the_band_the_name_lands_in() {
        const box = tile(0, "3x1");
        const dial = Geometry.dialRect("3x1", box.width, box.height, 1);
        const label = Geometry.tileNameRect("3x1", box.width, box.height, 1, offsetWidth);
        compare(dial.width, box.width);
        verify(dial.height < box.height, "the label band is not part of the dial");
        // AndroidClock insets its own drawing inside the box it is given, so
        // the face ends a `contentInset` above the box's bottom - which is
        // where the name band begins.
        verify(label.y >= dial.height - Geometry.DIAL_INSET,
               "the name sits under the face, not across it");
        verify(label.y + label.height <= box.height, "inside the tile");
    }

    function test_the_hands_grow_out_of_the_chip_rather_than_landing_on_it() {
        // A null at 2x2 would fade the dial in at its 3x1 size over a tile
        // that has not finished growing. Its 2x2 home is the chip's own box.
        const chip = tile(0, "2x2");
        const onChip = Geometry.dialRect("2x2", chip.width, chip.height, 1);
        compare(onChip.width, chip.width);
        compare(onChip.height, chip.height);
        verify(!Geometry.dialShown("2x2"), "shown at 3x1 only");
        verify(Geometry.dialShown("3x1"));
    }
}
