.pragma library

// Where every shared element of the world clock sits, per span.
//
// Two spans, both real component-grid boxes (docs/widget-grid.md), at scale 1:
//
//   2x2  276x228  the local card: place, time, date, and four city chips
//   3x1  420x108  four analog dials in a row
//
// The four cities are what the two spans have in common, so the tile is the
// element that travels: a chip in a 2x2 grid becomes a dial in a row of four,
// carrying its surface, its colour and its name with it. Everything the chip
// says in words - the offset, the digital time, the day/night glyph - has no
// home on a dial and fades, and the dial's hands have no home on a chip.
//
// Numbers measured off a render of the two `visible`-swapped subtrees this
// replaces: the chip grid's top is what is left after a header row, a 36px
// time and a date line have taken their natural heights, which is a font
// metric rather than anything anyone wrote down.

var CARD_INSET = 12;      // space150, the 2x2 card's edge padding
var CHIP_GAP = 6;         // space75, between chips in the 2x2 grid
var GRID_TOP = 117;       // measured: below the header, the time and the date
var CHIP_RADIUS = 17;     // rounding.normal
var CHIP_COLUMNS = 2;

// The 3x1 row is deliberately not on CARD_INSET: the dials are full-bleed
// tiles rather than content on a surface, and at space100 the card's 30px
// rounding minus the inset lands on the tile's own `large` radius, so the four
// nest concentrically in the corners.
var ROW_INSET = 8;        // space100
var ROW_GAP = 8;          // space100
var TILE_RADIUS = 23;     // rounding.large

// AndroidClock's own layout, restated here because the dial is now drawn
// label-less inside a box this module hands it: the component reserves a band
// at the bottom for its label and centres the dial in what is left, and the
// tile's name label - which travels in from the chip - is that band.
var DIAL_INSET = 8;          // AndroidClock.contentInset, space100
var DIAL_LABEL_FONT = 11;    // its labelPixelSize at this tile size
var DIAL_LABEL_SPACING = 6;  // space75, its labelSpacing
// What AndroidClock reserves under the dial, and where inside that band it
// actually puts the glyphs: half the spacing clear of the dial, and the rest
// of the band below. Restated rather than guessed at, because a name that
// travels in from the chip has to land exactly where the component used to
// draw its own.
var LABEL_BAND = DIAL_LABEL_FONT + DIAL_LABEL_SPACING;

// Inside a 2x2 chip.
var CHIP_PAD_X = 12;      // space150: the chip's `normal` radius is 17, and at
                          // a uniform space75 the name starts inside the curve
var CHIP_PAD_Y = 6;       // space75
var CHIP_LABEL_GAP = 4;   // space50, between the name and the offset beside it
var NAME_H = 15.5;        // a `smaller` text row
var NAME_FONT = 12;       // pixelSize.smaller
var OFFSET_FONT = 10;     // pixelSize.smallest
var TIME_ROW_Y = 21.5;
var TIME_ROW_H = 19;
var TIME_FONT = 16;       // pixelSize.normal
var ICON = 12;            // the day/night glyph, at pixelSize.smaller

var TILES = 4;

function _rect(x, y, w, h) { return { x: x, y: y, width: w, height: h }; }

// ---- the tile ------------------------------------------------------------
//
// The one element with a home at both spans, and so the one that carries the
// morph. Its radius travels too: a chip's corner is a step tighter than a
// dial's.
function cityTileRect(index, span, width, height, scale) {
    if (index < 0 || index >= TILES) return null;

    if (span === "3x1") {
        var tileW = (width - ROW_INSET * 2 * scale - ROW_GAP * (TILES - 1) * scale) / TILES;
        return {
            x: ROW_INSET * scale + index * (tileW + ROW_GAP * scale),
            y: ROW_INSET * scale,
            width: tileW, height: height - ROW_INSET * 2 * scale,
            radius: TILE_RADIUS * scale
        };
    }

    var column = index % CHIP_COLUMNS;
    var row = Math.floor(index / CHIP_COLUMNS);
    var chipW = (width - CARD_INSET * 2 * scale - CHIP_GAP * scale) / CHIP_COLUMNS;
    var chipH = (height - (GRID_TOP + CARD_INSET) * scale - CHIP_GAP * scale) / 2;
    return {
        x: CARD_INSET * scale + column * (chipW + CHIP_GAP * scale),
        y: GRID_TOP * scale + row * (chipH + CHIP_GAP * scale),
        width: chipW, height: chipH,
        radius: CHIP_RADIUS * scale
    };
}

// ---- what sits inside a tile ---------------------------------------------
//
// All of these are in the tile's own coordinates and take the tile's SETTLED
// box, never the one currently travelling: an inner rect measured off an
// animating box is a target that moves every frame, and a Behavior chasing one
// of those never converges.

// The city name, the one thing a chip and a dial both say. Top-left of the
// chip beside its offset; centred in the dial's label band.
function tileNameRect(span, tileWidth, tileHeight, scale, offsetWidth) {
    if (span === "3x1") {
        var band = (LABEL_BAND - DIAL_LABEL_SPACING / 2) * scale;
        return {
            x: DIAL_INSET * scale,
            y: tileHeight - DIAL_INSET * scale - band,
            width: tileWidth - DIAL_INSET * 2 * scale,
            height: band,
            size: DIAL_LABEL_FONT * scale, centred: true
        };
    }
    return {
        x: CHIP_PAD_X * scale, y: CHIP_PAD_Y * scale,
        width: tileWidth - CHIP_PAD_X * 2 * scale - offsetWidth - CHIP_LABEL_GAP * scale,
        height: NAME_H * scale,
        size: NAME_FONT * scale, centred: false
    };
}

// The UTC offset, right of the name. Words a dial cannot say, so 2x2 only.
function tileOffsetRect(span, tileWidth, tileHeight, scale, offsetWidth) {
    if (span !== "2x2") return null;
    return {
        x: tileWidth - CHIP_PAD_X * scale - offsetWidth,
        y: CHIP_PAD_Y * scale, width: offsetWidth, height: NAME_H * scale,
        size: OFFSET_FONT * scale
    };
}

// The digital time. The dial says this with its hands instead.
function tileTimeRect(span, tileWidth, tileHeight, scale) {
    if (span !== "2x2") return null;
    return {
        x: CHIP_PAD_X * scale, y: TIME_ROW_Y * scale,
        height: TIME_ROW_H * scale, size: TIME_FONT * scale
    };
}

// The day/night glyph, at the right end of the time row.
function tileIconRect(span, tileWidth, tileHeight, scale) {
    if (span !== "2x2") return null;
    return {
        x: tileWidth - (CHIP_PAD_X + ICON) * scale,
        y: TIME_ROW_Y * scale + (TIME_ROW_H - ICON) / 2 * scale,
        width: ICON * scale, height: ICON * scale
    };
}

// The dial. It has a rect at both spans rather than a null at 2x2, because
// what it grows out of IS the chip: fading in from the chip's own box means
// the hands arrive at the size the tile is, instead of a full-size clock
// appearing over a tile that has not finished growing yet.
//
// At 3x1 the box stops short of the name below it - AndroidClock centres its
// dial in whatever box it is given, and the band the name occupies is not part
// of it.
function dialRect(span, tileWidth, tileHeight, scale) {
    if (span === "3x1")
        return _rect(0, 0, tileWidth, tileHeight - LABEL_BAND * scale);
    return _rect(0, 0, tileWidth, tileHeight);
}

function dialShown(span) { return span === "3x1"; }
