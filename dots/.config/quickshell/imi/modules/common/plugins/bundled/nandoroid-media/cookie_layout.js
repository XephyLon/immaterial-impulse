.pragma library

// The cookie clock's geometry, extracted because the 2x2 media tile *is* that
// geometry with transport controls where the date badges are.
//
// Both numbers come off the clock's own files rather than being re-invented:
// `clock/CookieClock.qml` is a square `implicitSize: 230` with the cookie
// filling it, and `clock/dateIndicator/DateIndicator.qml` anchors two
// `dateSquareSize: 64` badges to opposite corners of that same square. The
// ratio between them is the entire relationship being copied - it is what puts
// a badge *on* the cookie's edge instead of beside it.
var CLOCK_FRAME = 230;
var CLOCK_BADGE = 64;
var BADGE_RATIO = CLOCK_BADGE / CLOCK_FRAME;

// The clock is square and the 2x2 tile is not (276x228), so the structure gets
// a square frame centred in the tile rather than being stretched to fill it.
// The badges anchor to the *frame's* corners, never the tile's: spread to the
// tile's corners they slide off the cookie's edge along a shallower diagonal
// and stop reading as attached to it, which is the one relationship this whole
// module exists to preserve.
//
// `inset` is clamped rather than trusted: a tile narrower than twice the inset
// would otherwise produce a negative size, and a negatively-sized Item is drawn
// as if it were zero while every offset computed from it is wrong.
function frame(tileWidth, tileHeight, inset) {
    var size = Math.max(0, Math.min(tileWidth, tileHeight) - inset * 2);
    return {
        size: size,
        x: (tileWidth - size) / 2,
        y: (tileHeight - size) / 2
    };
}

function badgeSize(frameSize) {
    return Math.max(0, frameSize) * BADGE_RATIO;
}

// How far a corner badge bites into the cookie's outer radius, in pixels.
//
// The badge's box sits in the frame's corner, so its centre lands on the
// frame's diagonal at `sqrt(2)/2 * (frameSize - badgeSize)` from the centre,
// while the cookie's lobes reach `frameSize / 2`. Positive means the two
// overlap - what the clock does, and what makes the badge read as fastened to
// the cookie. Zero or less means it floats clear and the tile reads as three
// unrelated objects, which is the failure this number names.
function badgeOverlap(frameSize) {
    var badge = badgeSize(frameSize);
    var centreDistance = Math.SQRT2 * (frameSize - badge) / 2;
    return frameSize / 2 + badge / 2 - centreDistance;
}
