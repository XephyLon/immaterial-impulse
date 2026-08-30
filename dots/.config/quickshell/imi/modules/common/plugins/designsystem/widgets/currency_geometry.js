.pragma library

// Where every shared element of the currency widget sits, per span.
// Spans at scale 1: 1x1 = 132x108, 2x1 = 276x108, 3x1 = 420x108 (the
// maintainer's design: the base as a hero block on the left - Rates, the
// giant code, its flag, the payments chip, the day's chart line - and all
// four quotes in a two-column grid with their 24h movement, a divider
// between the columns, and the refresh stamp bottom-right). Numbers for the
// first two spans measured off the visible-branch layouts this replaced.
// null = the span does not have the element (a fade, never a morph).

function _rect(x, y, w, h) { return { x: x, y: y, width: w, height: h }; }

// The container: the Bun badge at 1x1, the right panel at 2x1, and the
// small payments chip under the hero code at 3x1 - one element, three
// shapes, which is the whole morphing design in one object.
function containerRect(span, width, height, scale) {
    if (span === "1x1") return {
        x: width - (14 + 34) * scale, y: 14 * scale,
        width: 34 * scale, height: 34 * scale, shape: "bun"
    };
    // The 3x2's hero corner is the 3x1's, so the chip (and everything else
    // in the block) holds still on that resize.
    if (span === "3x2") return {
        x: 16 * scale, y: 108 - (14 + 26) * scale > 0 ? (108 - 14 - 26) * scale : 68 * scale,
        width: 38 * scale, height: 26 * scale, shape: "bun"
    };
    if (span === "3x1") return {
        x: 16 * scale, y: height - (14 + 26) * scale,
        width: 38 * scale, height: 26 * scale, shape: "bun"
    };
    return {
        x: width - 140 * scale, y: 0,
        width: 140 * scale, height: height, shape: "panel"
    };
}

// "Rates", the small label.
function ratesLabelRect(span, width, height, scale) {
    if (span === "1x1") return { x: 14 * scale, y: 14 * scale };
    if (span === "3x1" || span === "3x2") return { x: 16 * scale, y: 16 * scale };
    return { x: 20 * scale, y: 24 * scale };
}

// The base currency code. It reads "to USD" small at 1x1 and "USD" giant at
// 2x1, but the word "to" is its own element (see basePrefixRect) - swapping
// the text of one element would be a snap in the middle of the morph. `x` is
// the left edge of the whole group; the code itself is offset by whatever
// the fading prefix still occupies.
function baseLabelRect(span, width, height, scale) {
    if (span === "1x1") return { x: 14 * scale, y: 30 * scale, size: 10 * scale };
    if (span === "3x1" || span === "3x2") return { x: 16 * scale, y: 30 * scale, size: 34 * scale };
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
// ---- the 3x1 hero block's own elements -----------------------------------

// The hero column's width: everything left of the first divider.
var HERO_W_3X1 = 128;

// The base currency's flag, riding the top-right of the giant code.
function flagRect(span, width, height, scale) {
    if (span !== "3x1" && span !== "3x2") return null;
    return { x: (16 + 96) * scale, y: 28 * scale, size: 16 * scale };
}

// The day's chart line, across the hero block's lower half.
function chartRect(span, width, height, scale) {
    if (span === "3x2")
        // The hero block keeps the 3x1's height, so the line stays in its
        // lower half rather than stretching down the whole card.
        return _rect(0, 48 * scale, HERO_W_3X1 * scale, 55 * scale);
    if (span !== "3x1") return null;
    return _rect(0, height * 0.45, HERO_W_3X1 * scale, height * 0.5);
}

// ---- the 3x2's own lower-left block: the base, spelled out ---------------

// "Egyptian Pound", wrapping under the hero block.
function nameRect(span, width, height, scale) {
    if (span !== "3x2") return null;
    return _rect(16 * scale, 116 * scale, (HERO_W_3X1 - 24) * scale, 40 * scale);
}

// The base's 30-day chart, and its caption.
function chart30Rect(span, width, height, scale) {
    if (span !== "3x2") return null;
    return _rect(16 * scale, 154 * scale, (HERO_W_3X1 - 28) * scale, 46 * scale);
}
function caption30Rect(span, width, height, scale) {
    if (span !== "3x2") return null;
    return _rect(16 * scale, height - 24 * scale, (HERO_W_3X1 - 28) * scale, 14 * scale);
}

// The two column dividers of the quote grid.
function dividerRect(index, span, width, height, scale) {
    if ((span !== "3x1" && span !== "3x2") || index < 0 || index > 1) return null;
    var x = index === 0 ? HERO_W_3X1 * scale
                        : (HERO_W_3X1 + (width / scale - HERO_W_3X1) / 2) * scale;
    return _rect(x, 14 * scale, 1 * scale, height - 28 * scale);
}

// The refresh stamp, bottom-right.
function updatedRect(span, width, height, scale) {
    if (span !== "3x1" && span !== "3x2") return null;
    return { x: width - 150 * scale, y: height - 22 * scale,
             width: 138 * scale, height: 14 * scale };
}

function quoteCellRect(index, span, width, height, scale) {
    if (span === "3x2") {
        // The 3x1's grid grown a second storey: same columns, same reading
        // order, and each cell gains the room for its 7-day trend chart
        // (`trend`) under the numbers.
        var gX = (HERO_W_3X1 + 14) * scale;
        var gW = width - gX - 14 * scale;
        var cW = (gW - 22 * scale) / 2;
        var col2 = index % 2, row2 = Math.floor(index / 2);
        var cH = (height - 44 * scale) / 2;
        return {
            x: gX + col2 * (cW + 22 * scale),
            y: 14 * scale + row2 * (cH + 8 * scale),
            width: cW, height: cH, stacked: true, detailed: true,
            trend: true
        };
    }
    if (span === "3x1") {
        // Two columns right of the hero block, one quote per row, each cell
        // carrying code, value, arrow and the movement column ("detailed").
        var gridX = (HERO_W_3X1 + 14) * scale;
        var gridW = width - gridX - 14 * scale;
        var colW = (gridW - 22 * scale) / 2;
        // Row-major, exactly as the 2x1 panel reads: quotes 1-2 across the
        // top, 3-4 across the bottom. Column-major shipped first and swapped
        // EUR and JPY between the spans.
        var col3 = index % 2, row3 = Math.floor(index / 2);
        var cellH3 = (height - 36 * scale) / 2;
        return {
            x: gridX + col3 * (colW + 22 * scale),
            y: 14 * scale + row3 * (cellH3 + 4 * scale),
            width: colW, height: cellH3, stacked: true, detailed: true
        };
    }
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
