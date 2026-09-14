import QtQuick
import QtTest
import "../modules/common/plugins/bundled/image-converter/converter_queue.js" as Q

// The image converter's batch planning, without ffmpeg or the widget.
TestCase {
    name: "ConverterQueue"
    readonly property var accepted: ["png", "jpg", "jpeg", "webp", "avif", "bmp", "gif", "tiff", "tif"]

    function test_a_drop_is_filtered_and_cleaned() {
        const p = Q.acceptedPaths(["file:///a/b.PNG", "file:///a/notes.txt", "/a/c.jpeg", "file:///a/no-ext"], accepted);
        compare(p, ["/a/b.PNG", "/a/c.jpeg"]);
    }

    function test_nothing_accepted_is_a_none_plan() {
        const p = Q.plan(["file:///x/y.txt"], "webp", accepted);
        compare(p.kind, "none");
        verify(p.message.length > 0);
    }

    function test_a_sequence_names_every_output_and_its_first_message() {
        const one = Q.plan(["file:///pics/a.jpg"], "webp", accepted);
        compare(one.kind, "sequence"); compare(one.outputs, ["/pics/a_converted.webp"]); compare(one.message, "Converting...");
        const two = Q.plan(["file:///pics/a.jpg", "file:///pics/b.tar.gz.png"], "avif", accepted);
        compare(two.outputs, ["/pics/a_converted.avif", "/pics/b.tar.gz_converted.avif"]);
        compare(two.message, "Converting 0 / 2...");
    }

    function test_pdf_merges_into_one_output_named_after_the_first() {
        const one = Q.plan(["file:///pics/a.jpg"], "pdf", accepted);
        compare(one.kind, "pdf"); compare(one.output, "/pics/a_converted.pdf"); compare(one.message, "Converting to PDF...");
        const many = Q.plan(["file:///pics/a.jpg", "file:///pics/b.png"], "pdf", accepted);
        compare(many.output, "/pics/a_merged.pdf"); compare(many.inputs.length, 2);
        compare(many.message, "Merging 2 images into PDF...");
    }

    function test_the_status_lines() {
        compare(Q.progressMessage(1, 3), "Converting 1 / 3...");
        compare(Q.doneMessage(1, "/pics/a_converted.webp"), "Saved: a_converted.webp");
        compare(Q.doneMessage(3, "/pics/c_converted.webp"), "3 files converted");
        compare(Q.failMessage("/pics/broken.png"), "Failed: broken.png");
        compare(Q.pdfDoneMessage(1, "/p/a_converted.pdf"), "Saved: a_converted.pdf");
        compare(Q.pdfDoneMessage(2, "/p/a_merged.pdf"), "2 pages → a_merged.pdf");
    }
}
