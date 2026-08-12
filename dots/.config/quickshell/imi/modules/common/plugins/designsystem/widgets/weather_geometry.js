.pragma library

// Where every shared element of the weather widget sits, per span.
//
// The shared three (spec 2026-08-11 §3b): temperature, condition, and the
// weather-glyph container - the element whose persistence the design was
// specified around. Numbers measured off the three inline layouts this
// replaces. Rects are in scaled pixels; null means the span does not have the
// element (a fade, never a morph).

function _rect(x, y, w, h) { return { x: x, y: y, width: w, height: h }; }

// Temperature: the big number. Size rides the span.
function temperatureRect(span, width, height, scale) {
    if (span === "1x1") return { x: 16 * scale, y: 10 * scale, size: 44 * scale };
    if (span === "2x1") return { x: 20 * scale, y: 8 * scale, size: 44 * scale };
    return { x: 20 * scale, y: 16 * scale, size: 48 * scale };
}

// Condition: under the temperature at the small spans, the second column's
// headline at 3x1.
function conditionRect(span, width, height, scale) {
    if (span === "1x1") return { x: 16 * scale, y: 64 * scale, w: 58 * scale };
    if (span === "2x1") return { x: 20 * scale, y: 62 * scale, w: 140 * scale };
    return { x: 148 * scale, y: 28 * scale, w: 150 * scale };
}

// The glyph container - three shapes, one element.
//  3x1: the Ghostish, floating right of the row.
//  2x1: the full-height right panel (flush; the card's clip rounds it).
//  1x1: the slanted leaf hanging off the corner (the card's clip cuts it).
function glyphRect(span, width, height, scale) {
    if (span === "1x1") return {
        x: width - 44 * scale, y: height - 44 * scale,
        width: 50 * scale, height: 50 * scale,
        rotation: -22, icon: 28 * scale, shape: "leaf"
    };
    if (span === "2x1") return {
        x: width - 76 * scale, y: 0,
        width: 76 * scale, height: height,
        rotation: 0, icon: 36 * scale, shape: "panel"
    };
    return {
        x: width - (16 + 72) * scale, y: (height - 72 * scale) / 2,
        width: 72 * scale, height: 72 * scale,
        rotation: 0, icon: 42 * scale, shape: "ghostish"
    };
}
