.pragma library

// Where every shared element of the calendar widget sits, per span.
//
// Three spans, each a real component-grid box (docs/widget-grid.md), at scale 1:
//
//   1x1  132x108  the month banner and today's date, alone
//   2x1  276x108  the month pill, the weekday letters and the current week
//   2x2  276x228  the month title, the weekday letters and the whole month
//   3x2  420x228  today as a hero column beside the whole month on its own
//                 surface (the maintainer's reference shot: icon-in-shape,
//                 the month in small caps, the weekday, the big date - and
//                 the grid right of it, with no steppers: this span is about
//                 TODAY, like the two small ones)
//
// Numbers measured off a render of the three destroyed-and-rebuilt layouts this
// replaces rather than read out of their source: the two text-row heights (the
// banner's, the 2x2 weekday strip's) are font metrics of a laid-out column, not
// literals anyone wrote down, and the day grid's own top is a centring
// remainder. `null` means the span has no home for the element - a fade, never
// a morph.

var CARD_INSET = 12;         // space150, the card's edge padding at every span
var BANNER_H = 36.5;         // the 1x1 band: one `normal` row plus space100 above and below
var PILL_H = 28;             // the 2x1 month pill
var HEADER_H = 24;           // the 2x2 title row, which is the height of its chevrons
var BLOCK_GAP = 8;           // space100, between the title block and the calendar block
var LABEL_GAP = 4;           // space50, between the weekday letters and what they label
var GRID_INSET = 4;          // space50, between the day-grid surface and its columns
var STRIP_H_WIDE = 15;       // a `smaller` text row, as the 2x2 column lays it out
var STRIP_H_SHORT = 16;      // ...and as the 2x1 Grid's own header row does
var DAY = 28;                // the day pill, which is also the day cell's box
var ROW_PITCH = 22;          // six 28px pills in 138px: the rows deliberately overlap
var NAV = 24;                // a chevron button
var PILL_PADDING = 12;       // space150, either side of the month name inside its pill

var DAY_FONT = 12;           // pixelSize.smaller
var HERO_FONT = 54;          // today's date, alone on the 1x1 card
var MONTH_FONT_PILL = 15;    // pixelSize.small
var MONTH_FONT_TITLE = 16;   // pixelSize.normal

// ---- the 3x2 hero column (left of the grid surface) ----------------------
var CHIP = 40;               // the icon-in-shape
var CHIP_TOP = 14;
var HERO_LEFT = 16;          // the column's own inset, one step past the card's
var HERO_MONTH_TOP = 92;     // "AUGUST", small caps
var HERO_MONTH_H = 16;
var HERO_MONTH_FONT = 13;
var HERO_WEEKDAY_TOP = 110;  // "Saturday"
var HERO_WEEKDAY_H = 20;
var HERO_WEEKDAY_FONT = 16;
var HERO_DAY_TOP = 128;      // the big date
var HERO_DAY_FONT = 54;
var ROW_PITCH_3X2 = 26;      // roomier than the 2x2's 22: the surface is taller
var STRIP_TOP_3X2 = 10;      // the weekday strip, inside the surface

var ROWS = 6;
var COLUMNS = 7;
var CELLS = ROWS * COLUMNS;

function _rect(x, y, w, h) { return { x: x, y: y, width: w, height: h }; }

// The seven day columns are divided out of different widths at the two wide
// spans: at 2x1 the card's own content width, at 2x2 the day-grid surface's,
// which is itself inset inside that. Getting these two on one pitch is what the
// 2x2 strip's `dayGridInset` was for.
function columnWidth(span, width, scale) {
    if (span === "2x2")
        return (width - (CARD_INSET + GRID_INSET) * 2 * scale) / COLUMNS;
    if (span === "3x2")
        // The 3x2 surface is the 2x2's, moved: same 252 width, so the seven
        // columns keep the 2x2's pitch and the grid reads as the same grid.
        return (252 - GRID_INSET * 2) * scale / COLUMNS;
    return (width - CARD_INSET * 2 * scale) / COLUMNS;
}

function columnLeft(span, scale, width) {
    if (span === "3x2")
        return _surface3x2Left(width, scale) + GRID_INSET * scale;
    return (span === "2x2" ? CARD_INSET + GRID_INSET : CARD_INSET) * scale;
}

// The 3x2 grid surface hugs the card's right edge; the hero column owns the
// rest.
function _surface3x2Left(width, scale) {
    return width - (CARD_INSET + 252) * scale;
}

// Where the 2x2 weekday strip sits, and so where everything under it starts.
function _stripTop(scale) { return (CARD_INSET + HEADER_H + BLOCK_GAP) * scale; }

// ---- the month surface ---------------------------------------------------
//
// One element with two homes and one absence: the full-bleed accent band at
// 1x1, the pill at 2x1, and nothing at 2x2, where the month is a plain title on
// the card. It carries its corner radii because that IS the morph - a band
// whose top corners are the card's own becomes a stadium and back.
//
// `labelWidth` is the settled width of the month name inside it (measured by
// the caller against the pill's own font, never against the animating one), so
// the pill hugs "May 2026" and "September 2026" differently.
function monthSurfaceRect(span, width, height, scale, labelWidth, cardRadius) {
    if (span === "1x1") return {
        x: 0, y: 0, width: width, height: BANNER_H * scale,
        radiusTop: cardRadius, radiusBottom: 0
    };
    if (span === "2x1") return {
        x: CARD_INSET * scale, y: CARD_INSET * scale,
        width: labelWidth + PILL_PADDING * 2 * scale, height: PILL_H * scale,
        radiusTop: PILL_H / 2 * scale, radiusBottom: PILL_H / 2 * scale
    };
    return null;
}

// The month name in long form ("August 2026"), which lives at both wide spans
// and travels between them: out of the pill and up to the card's own inset,
// growing a step and changing ink. It has no home at 1x1, where the banner
// says the month in short form as its own element - swapping one label's text
// mid-morph is the content snap this architecture exists to kill.
function monthLabelRect(span, width, height, scale) {
    if (span === "1x1") return null;
    // The 3x2 says the month in the hero column (heroRect "month"), not as a
    // title over the grid.
    if (span === "3x2") return null;
    if (span === "2x1") return {
        x: (CARD_INSET + PILL_PADDING) * scale, y: CARD_INSET * scale,
        height: PILL_H * scale, size: MONTH_FONT_PILL * scale
    };
    return {
        x: CARD_INSET * scale, y: CARD_INSET * scale,
        height: HEADER_H * scale, size: MONTH_FONT_TITLE * scale
    };
}

// The 2x2 month steppers. index 0 is the previous month, 1 the next, and they
// sit at the right end of the title row in that order.
function navButtonRect(index, span, width, height, scale) {
    if (span !== "2x2") return null;
    var fromRight = (1 - index) * (NAV + LABEL_GAP) * scale;
    return {
        x: width - CARD_INSET * scale - NAV * scale - fromRight,
        y: CARD_INSET * scale, width: NAV * scale, height: NAV * scale
    };
}

// A weekday letter, over the column it labels. Present at every span but the
// 1x1; at 3x2 it moves INSIDE the grid surface, which carries its own strip
// (the reference shot), rather than sitting on the card above it.
function weekdayHeaderRect(index, span, width, height, scale) {
    if (span === "1x1") return null;
    var column = columnWidth(span, width, scale);
    if (span === "2x1") return _rect(
        columnLeft(span, scale) + index * column,
        (CARD_INSET + PILL_H + BLOCK_GAP) * scale,
        column, STRIP_H_SHORT * scale);
    if (span === "3x2") return _rect(
        columnLeft(span, scale, width) + index * column,
        (CARD_INSET + STRIP_TOP_3X2) * scale,
        column, STRIP_H_WIDE * scale);
    return _rect(columnLeft(span, scale) + index * column,
        _stripTop(scale), column, STRIP_H_WIDE * scale);
}

// The 3x2 hero column: the icon-in-shape, the month in small caps, the
// weekday, and the big date. One function keyed by part, so the widget's
// elements and the tests read the same table. Null anywhere else - every
// part fades in place.
function heroRect(part, span, width, height, scale) {
    if (span !== "3x2") return null;
    var right = _surface3x2Left(width, scale) - CARD_INSET * scale;
    if (part === "chip") return _rect(HERO_LEFT * scale, CHIP_TOP * scale,
        CHIP * scale, CHIP * scale);
    if (part === "month") return {
        x: HERO_LEFT * scale, y: HERO_MONTH_TOP * scale,
        width: right - HERO_LEFT * scale, height: HERO_MONTH_H * scale,
        size: HERO_MONTH_FONT * scale
    };
    if (part === "weekday") return {
        x: HERO_LEFT * scale, y: HERO_WEEKDAY_TOP * scale,
        width: right - HERO_LEFT * scale, height: HERO_WEEKDAY_H * scale,
        size: HERO_WEEKDAY_FONT * scale
    };
    if (part === "day") return {
        x: HERO_LEFT * scale, y: HERO_DAY_TOP * scale,
        width: right - HERO_LEFT * scale,
        height: height - (HERO_DAY_TOP + CARD_INSET) * scale,
        size: HERO_DAY_FONT * scale
    };
    return null;
}

function _surfaceBox(width, height, scale) {
    var top = _stripTop(scale) + (STRIP_H_WIDE + LABEL_GAP) * scale;
    return _rect(CARD_INSET * scale, top,
        width - CARD_INSET * 2 * scale, height - top - CARD_INSET * scale);
}

// The surface the month grid is drawn on. 2x2 only - the 2x1 week is drawn on
// the card itself. Its radius stays concentric with the card's.
function dayGridSurfaceRect(span, width, height, scale, cardRadius) {
    if (span === "3x2") {
        var rect3 = _rect(_surface3x2Left(width, scale), CARD_INSET * scale,
            252 * scale, height - CARD_INSET * 2 * scale);
        rect3.radius = cardRadius - CARD_INSET * scale;
        return rect3;
    }
    if (span !== "2x2") return null;
    var rect = _surfaceBox(width, height, scale);
    rect.radius = cardRadius - CARD_INSET * scale;
    return rect;
}

// The top of the six-row block inside the 3x2 surface: under its own strip,
// centred in what is left of the surface.
function _gridTop3x2(width, height, scale) {
    var surfaceTop = CARD_INSET * scale;
    var surfaceH = height - CARD_INSET * 2 * scale;
    var stripBottom = (STRIP_TOP_3X2 + STRIP_H_WIDE + LABEL_GAP) * scale;
    var block = (ROWS * DAY - (ROWS - 1) * (DAY - ROW_PITCH_3X2)) * scale;
    return surfaceTop + stripBottom
        + (surfaceH - stripBottom - block) / 2;
}

// The top of the six-row block inside that surface, which is centred in it.
function _gridTop(width, height, scale) {
    var surface = _surfaceBox(width, height, scale);
    var block = (ROWS * DAY - (ROWS - 1) * (DAY - ROW_PITCH)) * scale;
    return surface.y + (surface.height - block) / 2;
}

// ---- the day cells -------------------------------------------------------
//
// Forty-two of them, one per cell of the month matrix, and the whole morph is
// which of those have a home:
//
//   2x2  all of them, in six rows
//   2x1  the seven of `weekRow`, which travel up into one row
//   1x1  `todayIndex` alone, which grows into the hero date and loses its pill
//
// `pill` is the highlight's box rather than a flag, so today's marker shrinks
// to nothing on the way to the hero rather than blinking off: a fill of zero
// size is a fill that has finished leaving.
function dayCellRect(index, span, width, height, scale, weekRow, todayIndex) {
    if (index < 0 || index >= CELLS) return null;
    var row = Math.floor(index / COLUMNS);
    var column = index % COLUMNS;

    if (span === "1x1") {
        if (index !== todayIndex) return null;
        return {
            x: 0, y: BANNER_H * scale,
            width: width, height: height - BANNER_H * scale,
            size: HERO_FONT * scale, pill: 0
        };
    }

    var columnW = columnWidth(span, width, scale);
    var x = columnLeft(span, scale, width) + column * columnW + (columnW - DAY * scale) / 2;

    if (span === "2x1") {
        if (row !== weekRow) return null;
        return {
            x: x, y: (CARD_INSET + PILL_H + BLOCK_GAP + STRIP_H_SHORT + LABEL_GAP) * scale,
            width: DAY * scale, height: DAY * scale,
            size: DAY_FONT * scale, pill: DAY * scale
        };
    }

    if (span === "3x2") return {
        x: x, y: _gridTop3x2(width, height, scale) + row * ROW_PITCH_3X2 * scale,
        width: DAY * scale, height: DAY * scale,
        size: DAY_FONT * scale, pill: DAY * scale
    };

    return {
        x: x, y: _gridTop(width, height, scale) + row * ROW_PITCH * scale,
        width: DAY * scale, height: DAY * scale,
        size: DAY_FONT * scale, pill: DAY * scale
    };
}
