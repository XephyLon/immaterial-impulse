import QtTest
import "../modules/common/plugins/bundled/nandoroid-media/media_layouts.js" as MediaLayouts

// The media widget's span table. It used to map spans to layout FILES - the
// destroy the one tree replaced - so these tests now pin the surviving half:
// the spans as cell counts, and the 3x2 fallback for an unresolved span.
TestCase {
    name: "MediaLayoutsTest"

    function test_each_offered_span_resolves_to_its_cell_counts() {
        compare(MediaLayouts.spanFor("3x2").cols, 3);
        compare(MediaLayouts.spanFor("3x2").rows, 2);
        compare(MediaLayouts.spanFor("2x2").cols, 2);
        compare(MediaLayouts.spanFor("2x2").rows, 2);
        compare(MediaLayouts.spanFor("2x1").cols, 2);
        compare(MediaLayouts.spanFor("2x1").rows, 1);
    }

    function test_an_unresolved_span_falls_back_to_the_3x2() {
        // Empty until the host answers, and forever for a bare probe.
        for (const unresolved of ["", undefined, null, "9x9", "nonsense"]) {
            compare(MediaLayouts.spanFor(unresolved).cols, 3,
                    "fallback for " + unresolved);
            compare(MediaLayouts.spanFor(unresolved).rows, 2);
        }
    }

    function test_the_table_offers_exactly_the_manifest_spans() {
        compare(MediaLayouts.SPANS.length, 3,
                "a span added here needs geometry in media_geometry.js too");
    }
}
