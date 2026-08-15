import QtQuick
import QtTest
import "../modules/imi/recordingRegion/recording_region.js" as RecordingRegion

// Behavioural tests for the recording-region toolbar's geometry.
//
// The load-bearing one is `test_toolbar_never_overlaps_the_region`: a region
// recording captures whatever the compositor draws inside the rectangle, so a
// toolbar that overlaps it is recorded into every frame of the clip. The rest
// pin how the region string is read, since it comes back from a persisted
// state file and is not necessarily what this shell wrote.
TestCase {
    name: "RecordingRegionTest"

    readonly property var screen: ({ x: 0, y: 0, width: 1920, height: 1080 })
    readonly property var toolbar: ({ width: 200, height: 40 })

    // --- Reading the geometry the recorder was started with ---

    function test_region_string_is_the_slurp_format() {
        var region = RecordingRegion.parseRegion("100,200 640x480");
        compare(region.x, 100);
        compare(region.y, 200);
        compare(region.width, 640);
        compare(region.height, 480);
    }

    function test_a_region_that_is_not_one_reads_as_null() {
        compare(RecordingRegion.parseRegion(""), null);
        compare(RecordingRegion.parseRegion(null), null);
        compare(RecordingRegion.parseRegion("garbage"), null);
        compare(RecordingRegion.parseRegion("100,200 640x"), null);
        // Zero-sized is not a region: it would place the toolbar at a point.
        compare(RecordingRegion.parseRegion("100,200 0x480"), null);
        compare(RecordingRegion.parseRegion("100,200 640x0"), null);
    }

    // --- Placement ---

    function test_toolbar_sits_below_the_region_when_there_is_room() {
        var region = { x: 400, y: 300, width: 600, height: 400 };
        var spot = RecordingRegion.placeToolbar(region, screen, toolbar, 8);
        compare(spot.side, "below");
        compare(spot.y, 708);              // 300 + 400 + 8
        compare(spot.x, 600);              // centred: 400 + (600 - 200) / 2
    }

    function test_toolbar_goes_above_when_the_region_reaches_the_bottom() {
        var region = { x: 400, y: 300, width: 600, height: 770 };  // ends at 1070
        var spot = RecordingRegion.placeToolbar(region, screen, toolbar, 8);
        compare(spot.side, "above");
        compare(spot.y, 252);              // 300 - 8 - 40
    }

    function test_no_toolbar_at_all_when_neither_side_fits() {
        // A full-height region leaves nowhere outside it. The answer is no
        // toolbar - the bar's recording indicator still stops the capture.
        var region = { x: 0, y: 0, width: 1920, height: 1080 };
        compare(RecordingRegion.placeToolbar(region, screen, toolbar, 8), null);
    }

    function test_toolbar_never_overlaps_the_region() {
        // Every region that gets a toolbar, at a spread of sizes and positions:
        // the toolbar's rect and the region's rect must not intersect.
        var sizes = [40, 200, 700, 1000];
        var positions = [0, 5, 250, 700, 1000];
        for (var s = 0; s < sizes.length; s++) {
            for (var p = 0; p < positions.length; p++) {
                var region = { x: positions[p], y: positions[p], width: sizes[s], height: sizes[s] };
                if (region.x + region.width > screen.width) continue;
                if (region.y + region.height > screen.height) continue;
                var spot = RecordingRegion.placeToolbar(region, screen, toolbar, 8);
                if (spot === null) continue;
                var overlaps = spot.x < region.x + region.width
                    && spot.x + toolbar.width > region.x
                    && spot.y < region.y + region.height
                    && spot.y + toolbar.height > region.y;
                verify(!overlaps,
                    `toolbar at ${spot.x},${spot.y} overlaps region ${region.x},${region.y} ${region.width}x${region.height}`);
            }
        }
    }

    function test_toolbar_is_clamped_into_the_screen() {
        // Hard against the left edge: centring would put it off-screen.
        var left = RecordingRegion.placeToolbar({ x: 0, y: 100, width: 60, height: 60 }, screen, toolbar, 8);
        compare(left.x, 8);
        // Hard against the right edge.
        var right = RecordingRegion.placeToolbar({ x: 1860, y: 100, width: 60, height: 60 }, screen, toolbar, 8);
        compare(right.x, 1712);            // 1920 - 200 - 8
    }

    function test_placement_respects_a_screen_that_is_not_at_the_origin() {
        // A second monitor to the right: the clamp is against THAT screen.
        var secondary = { x: 1920, y: 0, width: 1920, height: 1080 };
        var spot = RecordingRegion.placeToolbar({ x: 1920, y: 100, width: 60, height: 60 }, secondary, toolbar, 8);
        compare(spot.x, 1928);             // 1920 + 8, not 8
    }

    function test_missing_inputs_place_nothing() {
        compare(RecordingRegion.placeToolbar(null, screen, toolbar, 8), null);
        compare(RecordingRegion.placeToolbar({ x: 0, y: 0, width: 10, height: 10 }, null, toolbar, 8), null);
    }
}
