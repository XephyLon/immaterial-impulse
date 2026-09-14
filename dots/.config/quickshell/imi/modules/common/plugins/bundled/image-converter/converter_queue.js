.pragma library

// The image converter's batch, planned as data. The widget used to hold the
// queue, the output naming, the five status strings and the state decisions
// on its visual root, next to two Processes; this module decides, the widget
// runs. tests/tst_converter_queue.qml pins it.

// A dropped url list -> the paths the converter accepts (file:// stripped,
// extension in `accepted`, case-insensitive).
function acceptedPaths(urls, accepted) {
    var out = [];
    for (var i = 0; i < urls.length; i++) {
        var cleanPath = String(urls[i]).replace(/^file:\/\//, "");
        var ext = cleanPath.split(".").pop().toLowerCase();
        if (accepted.indexOf(ext) !== -1) out.push(cleanPath);
    }
    return out;
}

function baseName(path) { return String(path).replace(/.*\//, ""); }
function stripExtension(path) { return String(path).replace(/\.[^/.]+$/, ""); }
function outputFor(input, format) { return stripExtension(input) + "_converted." + format; }

// What to do with a drop. Returns one of
//   { kind: "none", message }                       nothing accepted
//   { kind: "pdf", inputs, output, message }        one convert(1) call
//   { kind: "sequence", inputs, outputs, message }  one ffmpeg per input
function plan(urls, format, accepted) {
    var valid = acceptedPaths(urls, accepted);
    if (valid.length === 0) return { kind: "none", message: "No supported files dropped." };
    if (format === "pdf") {
        var output = stripExtension(valid[0]) + (valid.length > 1 ? "_merged" : "_converted") + ".pdf";
        return {
            kind: "pdf", inputs: valid, output: output,
            message: valid.length === 1 ? "Converting to PDF..." : "Merging " + valid.length + " images into PDF...",
        };
    }
    var outputs = valid.map(function (p) { return outputFor(p, format); });
    return {
        kind: "sequence", inputs: valid, outputs: outputs,
        message: valid.length > 1 ? "Converting 0 / " + valid.length + "..." : "Converting...",
    };
}

// The message while a sequence runs, after `done` of `total` finished.
function progressMessage(done, total) { return "Converting " + done + " / " + total + "..."; }

// The message when a sequence finished: the one file's name, or the count.
function doneMessage(total, lastOutput) {
    return total === 1 ? "Saved: " + baseName(lastOutput) : total + " files converted";
}
function failMessage(input) { return "Failed: " + baseName(input); }

function pdfDoneMessage(pageCount, output) {
    return pageCount === 1 ? "Saved: " + baseName(output) : pageCount + " pages → " + baseName(output);
}
var PDF_FAIL_MESSAGE = "PDF failed.\nIs ImageMagick installed?";
