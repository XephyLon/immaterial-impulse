.pragma library

// Where every shared element of the weather widget sits, per span.
//
// The shared three (spec 2026-08-11 §3b): temperature, condition, and the
// weather-glyph container - the element whose persistence the design was
// specified around. Numbers measured off the three inline layouts this
// replaces. Rects are in scaled pixels; null means the span does not have the
// element (a fade, never a morph).

function _rect(x, y, w, h) { return { x: x, y: y, width: w, height: h }; }

// 3x2 is the only span with two rows, and it is split into two bands: the
// current conditions keep the top, the day-by-day forecast owns the bottom.
// TOP_BAND is where that seam falls, and every 3x2 number below is placed
// against it rather than against the card, so moving the seam moves the whole
// layout coherently.
var TOP_BAND = 124;
var SIDE_MARGIN = 20;
// The gap between two day cards. Deliberately tighter than the widget grid's
// own 12px gutter: these are cells of one object, not neighbouring widgets.
var FORECAST_GAP = 10;

// Temperature: the big number. Size rides the span.
function temperatureRect(span, width, height, scale) {
    if (span === "1x1") return { x: 16 * scale, y: 10 * scale, size: 44 * scale };
    if (span === "2x1") return { x: 20 * scale, y: 8 * scale, size: 44 * scale };
    if (span === "3x2") return { x: 20 * scale, y: 22 * scale, size: 56 * scale };
    return { x: 20 * scale, y: 16 * scale, size: 48 * scale };
}

// Condition: under the temperature at the small spans, the second column's
// headline at 3x1 and 3x2.
function conditionRect(span, width, height, scale) {
    if (span === "1x1") return { x: 16 * scale, y: 64 * scale, w: 58 * scale };
    if (span === "2x1") return { x: 20 * scale, y: 62 * scale, w: 140 * scale };
    if (span === "3x2") return { x: 148 * scale, y: 34 * scale, w: 150 * scale };
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
    if (span === "3x2") return {
        // Centred in the TOP band, not in the card: the bottom of a 3x2 card
        // belongs to the forecast, and a glyph centred on the whole card
        // would sit across it.
        x: width - (16 + 84) * scale, y: (TOP_BAND * scale - 84 * scale) / 2,
        width: 84 * scale, height: 84 * scale,
        rotation: 0, icon: 48 * scale, shape: "ghostish"
    };
    return {
        x: width - (16 + 72) * scale, y: (height - 72 * scale) / 2,
        width: 72 * scale, height: 72 * scale,
        rotation: 0, icon: 42 * scale, shape: "ghostish"
    };
}

// ---- elements that exist at some spans and not others --------------------
//
// These are fades, so they get a rect where they have a home and null where
// they do not. They still need slots rather than literals in the tree,
// because the ones that live at BOTH wide spans have to travel between them.

// "High X° · Low Y°". At 3x2 this is the fallback for an absent forecast -
// the strip says it better when there is one - so it still needs a rect there.
function highLowRect(span, width, height, scale) {
    if (span === "3x1") return { x: 20 * scale, y: 74 * scale };
    if (span === "3x2") return { x: 20 * scale, y: 90 * scale };
    return null;
}

// The humidity and wind pills, under the condition in the second column.
function pillsRect(span, width, height, scale) {
    if (span === "3x1") return { x: 148 * scale, y: 60 * scale };
    if (span === "3x2") return { x: 148 * scale, y: 76 * scale };
    return null;
}

// The hairline between the temperature column and the condition column.
function columnDividerRect(span, width, height, scale) {
    if (span === "3x1") return { x: 132 * scale, y: 16 * scale, height: 76 * scale };
    if (span === "3x2") return { x: 132 * scale, y: 20 * scale, height: 84 * scale };
    return null;
}

// ---- the sun's day, across the card's background -------------------------
//
// The arc is a background layer rather than one of the shared three, but it
// obeys the same rule as everything else in this file: a rect where it has a
// home, null where it does not.
//
// `horizonY` is where the curve crosses from day into night, and `apexRise`
// is how far above it the midday sine reaches. Both are measured from the
// card's top edge.
//
// **1x1 is the null.** The curve always draws one whole day plus a night
// margin at each end across whatever width it is given, so at 132px the
// daylight stretch is 92px wide while the apex still rises 45px: a 2:1 arc,
// steep enough that what shows either side of the 44px temperature reads as a
// diagonal streak through the card rather than as a day. Making it fit is not
// the answer either - flattening it to a readable ~4:1 puts the whole curve
// in the 28px strip below the condition line, where the leaf glyph swallows
// the sunset half and the marker lands on the text. The 1x1 card is fully
// occupied; the arc has nowhere to be, which is what null means here.
function sunArcRect(span, width, height, scale) {
    if (span === "1x1") return null;
    if (span === "3x2") {
        // No separate horizon is drawn at 3x2: the curve's zero-crossing lands
        // on the hairline the card already draws between its two bands, so the
        // divider and the horizon are one line doing both jobs. Derived from
        // that rect rather than restated, so moving the seam moves the horizon.
        var seam = bandDividerRect(span, width, height, scale).y;
        return { horizonY: seam, apexRise: seam * 0.62 };
    }
    return { horizonY: height * 0.74, apexRise: height * 0.42 };
}

// ---- the second row ------------------------------------------------------

// The hairline between the two bands. 3x2 only - there is no seam to draw on
// a card with one row.
function bandDividerRect(span, width, height, scale) {
    if (span !== "3x2") return null;
    return _rect(SIDE_MARGIN * scale, (TOP_BAND - 4) * scale,
                 width - 2 * SIDE_MARGIN * scale, 1);
}

// Where the row of day cards sits. Null at every other span: the strip has no
// home there, and a null rect is a fade rather than somewhere to travel to.
function forecastStripRect(span, width, height, scale) {
    if (span !== "3x2") return null;
    return _rect(SIDE_MARGIN * scale, (TOP_BAND + 16) * scale,
                 width - 2 * SIDE_MARGIN * scale, 68 * scale);
}

// One day card, in the strip's own coordinates.
//
// The count is an argument rather than a constant because the providers
// disagree about it and #111 deliberately declined to pad: wttr.in answers
// with three days, OpenWeatherMap with four, and a failed forecast request
// with none. The cards divide whatever room the strip has, so every one of
// those reads as a deliberate row rather than as a row with a hole in it.
function forecastCardRect(index, count, stripWidth, stripHeight, scale) {
    if (!(count > 0) || index < 0 || index >= count) return null;
    var gap = FORECAST_GAP * scale;
    var cardWidth = (stripWidth - gap * (count - 1)) / count;
    return _rect(index * (cardWidth + gap), 0, cardWidth, stripHeight);
}
