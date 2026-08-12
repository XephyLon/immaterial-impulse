.pragma library

.import "cookie_layout.js" as CookieLayout

// Where every shared element of the media widget sits, per span.
//
// This is step 3 of the expressive-morphing plan (spec 2026-08-11, §1): the
// one place a size's layout is decided. Today three layout files each place
// their own controls and a span change destroys one set to construct another;
// step 4 collapses them into one tree whose elements *bind* these rects, so
// the play button at 3x2 and the play button at 2x1 become the same object in
// two places. Nothing calls this module yet - it exists to be tested first.
//
// The numbers are measured off the current layouts, not designed fresh:
// DesktopMediaWidget.qml (3x2), LayoutCookie.qml + cookie_layout.js (2x2),
// LayoutCompact.qml (2x1). One deliberate change of anchor: the 3x2 places
// its controls in a ColumnLayout under two text lines, so their positions
// drift with font metrics. Shared elements must not move because a title got
// taller, so here they anchor to the CARD's bottom edge and the time label
// gets a fixed slot (TIME_LABEL_H) instead of flow. The step-4 review is
// where "close enough to today" is judged, on screen.
//
// Every function takes the span's box in *scaled* pixels (what the widget is
// actually given) plus the scale, and returns rects in the same space. A rect
// is { x, y, width, height }; elements a span does not have return null,
// which is the "enters and exits" half of the design - a null rect is a fade,
// never a morph.

// ---- 3x2 constants (unscaled, as authored) -------------------------------
var LARGE_MARGIN = 17;         // mainStack margins
var LARGE_BOTTOM = 22;         // its deeper bottom margin
var LARGE_SPACING = 2;         // the column's spacing
var LARGE_PREV_NEXT = 62;      // prev/next buttons, square
var LARGE_PLAY_W = 192;        // the wide play pill
var LARGE_PLAY_H = 66;
var LARGE_ROW_SPACING = 12;
var LARGE_SLIDER_W = 170;      // the wavy StyledSlider
var LARGE_SLIDER_H = 12;
// The time label's slot. In the current 3x2 this is a flowed StyledText whose
// height rides the font; the one tree gives it this fixed slot instead, which
// is the single deliberate deviation this module makes from today's layout.
var TIME_LABEL_H = 16;

// ---- 2x1 constants (unscaled, as authored) -------------------------------
var COMPACT_CONTROL = 56;      // prev/next pills
var COMPACT_PLAY = 72;         // the cookie play button
var COMPACT_SPACING = 12;      // Appearance.spacing.space150

// ---- 2x2 constants -------------------------------------------------------
var COOKIE_INSET = 12;         // cardInset = Appearance.spacing.space150
var COOKIE_ART_RATIO = 0.72;   // artClip diameter / frame size
var RING_MARGIN_2X1 = 0.14;    // how far the 2x1 seek ring floats outside play

function _rect(x, y, w, h) {
    return { x: x, y: y, width: w, height: h };
}

// The square cookie frame the 2x2 centres everything in.
function cookieFrame(width, height, scale) {
    return CookieLayout.frame(width, height, COOKIE_INSET * scale);
}

// ---- the shared elements -------------------------------------------------

// prev / play / next.
//
// 3x2: a centred row of prev(62) play(192x66) next(62), anchored above the
//      time slot and slider rather than flowed below the text.
// 2x2: prev and next are the clock's corner badges on the cookie frame's
//      diagonal; "play" is the artwork circle, because tapping the cookie is
//      what toggles playback there.
// 2x1: the centred pill row.
function transportRects(span, width, height, scale) {
    if (span === "3x2") {
        var rowH = LARGE_PLAY_H * scale;
        var rowW = (2 * LARGE_PREV_NEXT + LARGE_PLAY_W + 2 * LARGE_ROW_SPACING) * scale;
        var rowY = sliderRect3x2(width, height, scale).y
            - (LARGE_SPACING + TIME_LABEL_H + LARGE_SPACING) * scale - rowH;
        var rowX = (width - rowW) / 2;
        var sideY = rowY + (rowH - LARGE_PREV_NEXT * scale) / 2;
        return {
            prev: _rect(rowX, sideY, LARGE_PREV_NEXT * scale, LARGE_PREV_NEXT * scale),
            play: _rect(rowX + (LARGE_PREV_NEXT + LARGE_ROW_SPACING) * scale, rowY,
                        LARGE_PLAY_W * scale, rowH),
            next: _rect(rowX + (LARGE_PREV_NEXT + LARGE_ROW_SPACING + LARGE_PLAY_W
                        + LARGE_ROW_SPACING) * scale, sideY,
                        LARGE_PREV_NEXT * scale, LARGE_PREV_NEXT * scale)
        };
    }
    if (span === "2x2") {
        var frame = cookieFrame(width, height, scale);
        var badge = CookieLayout.badgeSize(frame.size);
        // Play IS the cookie: the button holds the artwork and the seek ring
        // inside itself (the review's design), so its rect is the whole
        // frame, and the artwork circle is the button's interior.
        return {
            prev: _rect(frame.x, frame.y, badge, badge),
            play: _rect(frame.x, frame.y, frame.size, frame.size),
            next: _rect(frame.x + frame.size - badge,
                        frame.y + frame.size - badge, badge, badge)
        };
    }
    if (span === "2x1") {
        var control = COMPACT_CONTROL * scale;
        var play = COMPACT_PLAY * scale;
        var gap = COMPACT_SPACING * scale;
        var totalW = 2 * control + play + 2 * gap;
        var x = (width - totalW) / 2;
        return {
            prev: _rect(x, (height - control) / 2, control, control),
            play: _rect(x + control + gap, (height - play) / 2, play, play),
            next: _rect(x + control + gap + play + gap, (height - control) / 2,
                        control, control)
        };
    }
    return null;
}

function sliderRect3x2(width, height, scale) {
    return _rect((width - LARGE_SLIDER_W * scale) / 2,
                 height - (LARGE_BOTTOM + LARGE_SLIDER_H) * scale,
                 LARGE_SLIDER_W * scale, LARGE_SLIDER_H * scale);
}

// Progress / seek.
//
// 3x2: the wavy slider. 2x1: the ring stroked around the play button - the
// SAME rect as play, which is the "two concentric draws of one outline"
// arrangement, and the reason the seeker morphs with the button rather than
// toward a bar somewhere else. 2x2: the cookie frame; today it draws no
// progress there, and the decided design (spec §3) gives it an inner ring on
// this rect in step 7 - the geometry reserves the slot now so the element has
// a rect at every span from the day the tree exists.
function progressRect(span, width, height, scale) {
    if (span === "3x2") return sliderRect3x2(width, height, scale);
    if (span === "2x1") {
        // INFLATED past the button: the ring is its border, and a border
        // stuck to the edge reads as part of it (the review) - the margin is
        // the ring floating just outside, spring-parallel to the contour.
        var play = transportRects(span, width, height, scale).play;
        var grow = play.width * RING_MARGIN_2X1;
        return _rect(play.x - grow, play.y - grow,
                     play.width + 2 * grow, play.height + 2 * grow);
    }
    if (span === "2x2") {
        // A perfect circle INSIDE the play button (the review's words): the
        // ring sits between the artwork (0.72) and the cookie's valleys.
        // Clear of the artwork below it AND of the lobes above it - the
        // review: the circle must not touch the button's outer edges.
        var frame = cookieFrame(width, height, scale);
        var inner = frame.size * 0.76;
        return _rect(frame.x + (frame.size - inner) / 2,
                     frame.y + (frame.size - inner) / 2, inner, inner);
    }
    return null;
}

// The time label's slot (3x2 only - it fades elsewhere).
function timeLabelRect(span, width, height, scale) {
    if (span !== "3x2") return null;
    var slider = sliderRect3x2(width, height, scale);
    return _rect(LARGE_MARGIN * scale, slider.y - (LARGE_SPACING + TIME_LABEL_H) * scale,
                 width - 2 * LARGE_MARGIN * scale, TIME_LABEL_H * scale);
}

// Artwork (2x2 only - the circle clipped inside the cookie's lobes). It
// lives INSIDE the play button, so this rect is the button's interior:
// centred, 0.72 of the frame - numerically what it always was.
function artworkRect(span, width, height, scale) {
    if (span !== "2x2") return null;
    var frame = cookieFrame(width, height, scale);
    var art = frame.size * COOKIE_ART_RATIO;
    return _rect(frame.x + (frame.size - art) / 2,
                 frame.y + (frame.size - art) / 2, art, art);
}
