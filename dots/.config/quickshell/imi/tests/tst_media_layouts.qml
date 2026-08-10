import QtTest
import "../modules/common/plugins/bundled/nandoroid-media/media_layouts.js" as MediaLayouts

// The media widget's half of the grid contract: the host resolves a span and
// hands it down as a "<cols>x<rows>" string, and this maps that string onto the
// file that draws it.
//
// The rule worth pinning is the fallback. `hostGridSize` is empty until the
// host answers - and stays empty for a bare `qs -p` probe of Widget.qml - so a
// lookup that returned nothing for an unrecognised string would leave the
// widget drawing nothing at all, which on screen is indistinguishable from a
// layout that failed to compile.
TestCase {
    name: "MediaLayoutsTest"

    function test_the_default_span_draws_the_large_layout() {
        compare(MediaLayouts.layoutFor("3x2"), "LayoutLarge.qml");
        compare(MediaLayouts.spanFor("3x2").cols, 3);
        compare(MediaLayouts.spanFor("3x2").rows, 2);
    }

    function test_the_two_by_two_span_draws_the_cookie_layout() {
        compare(MediaLayouts.layoutFor("2x2"), "LayoutCookie.qml");
        compare(MediaLayouts.spanFor("2x2").cols, 2);
        compare(MediaLayouts.spanFor("2x2").rows, 2);
    }

    function test_an_unanswered_host_draws_the_default_layout() {
        compare(MediaLayouts.layoutFor(""), "LayoutLarge.qml");
        compare(MediaLayouts.layoutFor(undefined), "LayoutLarge.qml");
        compare(MediaLayouts.layoutFor(null), "LayoutLarge.qml");
    }

    function test_a_span_the_manifest_no_longer_offers_draws_the_default() {
        // The mirror of gridSizes.resolveSize refusing a stored span that is no
        // longer offered: one upgrade later, plugin-state.json still names it.
        compare(MediaLayouts.layoutFor("9x9"), "LayoutLarge.qml");
        compare(MediaLayouts.spanFor("9x9").cols, 3);
        compare(MediaLayouts.spanFor("9x9").rows, 2);
    }

    function test_the_fallback_span_and_the_fallback_layout_agree() {
        // Two lookups over one table, so a layout can never be drawn for a span
        // other than the one it was designed for.
        const unknown = MediaLayouts.spanFor("nonsense");
        compare(MediaLayouts.layoutFor(unknown.cols + "x" + unknown.rows),
            MediaLayouts.layoutFor("nonsense"));
    }

    function test_every_entry_names_a_span_that_maps_back_to_itself() {
        for (const entry of MediaLayouts.SIZES) {
            compare(entry.size, entry.cols + "x" + entry.rows,
                "entry " + entry.size + " disagrees with its own cell counts");
            compare(MediaLayouts.layoutFor(entry.size), entry.layout);
        }
    }
}
