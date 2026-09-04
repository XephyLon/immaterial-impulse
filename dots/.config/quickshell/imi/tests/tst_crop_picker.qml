import QtQuick
import QtTest
import "../modules/imi/wallpaperSelector/crop_picker.js" as CropPicker

// The Fill crop picker's geometry: the viewport rectangle drawn over the
// preview, and the focus a drag on it produces. Pure - nothing about the drawn
// thumbnail is reachable from qmltestrunner.
TestCase {
    name: "CropPickerTest"

    // A 32:9 wallpaper on a 16:9 screen overflows horizontally: the viewport
    // is a vertical slice you slide left-right.
    function test_overflow_axis_and_viewport_size() {
        // contentAspect 32:9 (~3.556), screenAspect 16:9 (~1.778).
        var g = CropPicker.viewport(3.556, 1.778, 320, 90, 0.5)
        verify(g.overflowsX)
        verify(!g.overflowsY)
        // The viewport covers full height and half the width (content twice
        // as wide as the screen crop).
        compare(Math.round(g.height), 90)
        compare(Math.round(g.width), 160)
        // Centred focus: the slice sits in the middle.
        compare(Math.round(g.x), 80)
        compare(Math.round(g.y), 0)
    }

    function test_focus_moves_the_viewport() {
        var left = CropPicker.viewport(3.556, 1.778, 320, 90, 0.0)
        compare(Math.round(left.x), 0)
        var right = CropPicker.viewport(3.556, 1.778, 320, 90, 1.0)
        compare(Math.round(right.x), 160)
    }

    function test_vertical_overflow() {
        // A 9:16 portrait wallpaper on a 16:9 screen overflows vertically.
        var g = CropPicker.viewport(0.5625, 1.778, 90, 160, 0.5)
        verify(!g.overflowsX)
        verify(g.overflowsY)
        compare(Math.round(g.width), 90)
        // vh = previewW / screenAspect = 90 / 1.778 = 50.6
        compare(Math.round(g.height), 51)
        compare(Math.round(g.y), 55)
    }

    function test_no_overflow_when_aspects_match() {
        var g = CropPicker.viewport(1.778, 1.778, 320, 180, 0.5)
        verify(!g.overflowsX)
        verify(!g.overflowsY)
        // The viewport is the whole preview - nothing to pan.
        compare(Math.round(g.width), 320)
        compare(Math.round(g.height), 180)
    }

    // The inverse: a pointer position on the preview becomes a focus fraction.
    function test_focus_from_pointer_clamps_and_centres_within_the_slack() {
        // 32:9 on 16:9, preview 320 wide, viewport 160 wide -> 160px of slack.
        // A pointer at the preview's left edge focuses 0; right edge focuses 1.
        compare(CropPicker.focusFromPointer(3.556, 1.778, 320, 90, 0, 45).x, 0)
        compare(CropPicker.focusFromPointer(3.556, 1.778, 320, 90, 320, 45).x, 1)
        // Middle -> 0.5.
        compare(CropPicker.focusFromPointer(3.556, 1.778, 320, 90, 160, 45).x, 0.5)
        // Out of bounds clamps.
        compare(CropPicker.focusFromPointer(3.556, 1.778, 320, 90, -50, 45).x, 0)
        // The non-overflowing axis is pinned to centre.
        compare(CropPicker.focusFromPointer(3.556, 1.778, 320, 90, 160, 45).y, 0.5)
    }

    function test_focus_from_pointer_maps_the_viewport_centre_to_the_pointer() {
        // Dragging so the viewport's CENTRE is under the pointer, then reading
        // the focus back, is a round trip: a focus produces a viewport whose
        // centre, fed back, returns the same focus.
        var f = 0.3
        var g = CropPicker.viewport(3.556, 1.778, 320, 90, f)
        var centreX = g.x + g.width / 2
        var back = CropPicker.focusFromPointer(3.556, 1.778, 320, 90, centreX, 45)
        verify(Math.abs(back.x - f) < 0.001)
    }
}
