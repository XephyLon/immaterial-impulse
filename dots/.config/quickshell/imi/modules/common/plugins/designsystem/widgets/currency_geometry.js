.pragma library

// Where every shared element of the currency widget sits, per span.
// Spans at scale 1: 1x1 = 132x108, 2x1 = 276x108. Numbers measured off the
// two visible-branch layouts this replaces. null = the span does not have
// the element (a fade, never a morph).

function _rect(x, y, w, h) { return { x: x, y: y, width: w, height: h }; }

// The container: the Bun badge at 1x1, the right panel at 2x1.
function containerRect(span, width, height, scale) {
    if (span === "1x1") return {
        x: width - (14 + 34) * scale, y: 14 * scale,
        width: 34 * scale, height: 34 * scale, shape: "bun"
    };
    return {
        x: width - 140 * scale, y: 0,
        width: 140 * scale, height: height, shape: "panel"
    };
}

// "Rates", the small label.
function ratesLabelRect(span, width, height, scale) {
    if (span === "1x1") return { x: 14 * scale, y: 14 * scale };
    return { x: 20 * scale, y: 24 * scale };
}

// The base currency code. It reads "to USD" small at 1x1 and "USD" giant at
// 2x1, but the word "to" is its own element (see basePrefixRect) - swapping
// the text of one element would be a snap in the middle of the morph. `x` is
// the left edge of the whole group; the code itself is offset by whatever
// the fading prefix still occupies.
function baseLabelRect(span, width, height, scale) {
    if (span === "1x1") return { x: 14 * scale, y: 30 * scale, size: 10 * scale };
    return { x: 20 * scale, y: 38 * scale, size: 42 * scale };
}

// The word "to", which only exists at 1x1. It keeps its small size while it
// fades so the growing code does not drag it along.
function basePrefixRect(span, width, height, scale) {
    if (span === "1x1") return { x: 14 * scale, y: 30 * scale, size: 10 * scale };
    return null;
}

// A quote cell. All four exist at 2x1 (the panel's 2x2 grid); the first two
// survive at 1x1 as the stacked rows bottom-left, the rest return null.
// `stacked` is the cell's inner arrangement: label above value in the panel,
// label-left value-right in the 1x1 rows.
function quoteCellRect(index, span, width, height, scale) {
    if (span === "1x1") {
        if (index >= 2) return null;
        var rowH = 18 * scale;
        return {
            x: 14 * scale, y: height - (14 + (2 - index) * rowH) * scale >= 0
                ? height - 14 * scale - (2 - index) * rowH : 0,
            width: width - 28 * scale, height: rowH, stacked: false
        };
    }
    var panelX = width - 140 * scale;
    var cellW = (140 - 28 - 10) / 2 * scale;
    var cellH = (108 - 28 - 4) / 2 * scale;
    var col = index % 2, row = Math.floor(index / 2);
    return {
        x: panelX + 14 * scale + col * (cellW + 10 * scale),
        y: 14 * scale + row * (cellH + 4 * scale),
        width: cellW, height: cellH, stacked: true
    };
}
