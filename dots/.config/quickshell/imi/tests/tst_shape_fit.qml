import QtTest
import "../modules/common/plugins/designsystem/widgets/shapes/shape-fit.js" as ShapeFit

// Where a normalised rounded polygon lands inside the item drawing it.
//
// This is the arithmetic that decides whether a shape can be a *card*. Under
// the square rule a 320x112 card draws a 112x112 shape floating in the middle
// of itself, which is why the stretch placement exists at all.
//
// It is scored here rather than on screen because a `Canvas` draws nothing
// under the software scene graph the suite runs on: rendering proves the file
// parses and nothing else. The placement is pure arithmetic, so it is checked
// against arithmetic.
TestCase {
    name: "ShapeFitTest"

    function test_the_square_placement_scales_by_the_short_side() {
        const placement = ShapeFit.fit(320, 112, true, false);
        compare(placement.scaleX, 112, "a square placement uses the short side");
        compare(placement.scaleY, 112, "and uses it on both axes");
    }

    function test_the_square_placement_centres_what_it_shrinks() {
        const placement = ShapeFit.fit(320, 112, true, false);
        compare(placement.offsetX, 104, "(320 - 112) / 2");
        compare(placement.offsetY, 0, "the short axis has nothing to centre");
    }

    function test_stretch_fills_the_box_on_both_axes() {
        const placement = ShapeFit.fit(320, 112, true, true);
        compare(placement.scaleX, 320);
        compare(placement.scaleY, 112);
        compare(placement.offsetX, 0, "filling leaves nothing to centre");
        compare(placement.offsetY, 0);
    }

    function test_a_square_item_is_the_same_either_way() {
        // The reason stretch is safe to add: on the shapes that already exist -
        // glyphs, buttons, clock faces - it changes nothing.
        const square = ShapeFit.fit(120, 120, true, false);
        const stretched = ShapeFit.fit(120, 120, true, true);
        compare(square.scaleX, stretched.scaleX);
        compare(square.scaleY, stretched.scaleY);
        compare(square.offsetX, stretched.offsetX);
        compare(square.offsetY, stretched.offsetY);
    }

    function test_a_pixel_polygon_is_placed_but_never_scaled() {
        const placement = ShapeFit.fit(320, 112, false, false);
        compare(placement.scaleX, 1, "already in pixels");
        compare(placement.scaleY, 1);
        compare(placement.offsetX, 104, "but still centred, as it always was");
    }

    function test_a_degenerate_size_does_not_produce_nonsense() {
        // A Canvas is laid out before it is sized, so this runs with 0 and with
        // undefined on the first frames.
        const zero = ShapeFit.fit(0, 0, true, true);
        compare(zero.scaleX, 0);
        compare(zero.scaleY, 0);
        const undef = ShapeFit.fit(undefined, undefined, true, false);
        compare(undef.scaleX, 0);
        compare(undef.offsetX, 0);
    }

    function test_mapping_puts_a_normalised_point_where_the_placement_says() {
        const placement = ShapeFit.fit(320, 112, true, true);
        compare(ShapeFit.mapX(0, placement), 0, "left edge");
        compare(ShapeFit.mapX(1, placement), 320, "right edge");
        compare(ShapeFit.mapY(0.5, placement), 56, "vertical centre");
    }

    function test_mapping_respects_the_square_placement_offset() {
        const placement = ShapeFit.fit(320, 112, true, false);
        compare(ShapeFit.mapX(0, placement), 104, "the shape starts after the gap");
        compare(ShapeFit.mapX(1, placement), 216, "and ends before the other one");
        compare(ShapeFit.mapY(1, placement), 112);
    }

    function test_the_stretched_aspect_is_the_items_aspect() {
        // The property that makes a stretched shape usable as a card outline:
        // the drawn shape has the box's aspect, not the polygon's.
        const placement = ShapeFit.fit(300, 100, true, true);
        const width = ShapeFit.mapX(1, placement) - ShapeFit.mapX(0, placement);
        const height = ShapeFit.mapY(1, placement) - ShapeFit.mapY(0, placement);
        compare(width / height, 3, "300 x 100 is 3:1");
    }
}
