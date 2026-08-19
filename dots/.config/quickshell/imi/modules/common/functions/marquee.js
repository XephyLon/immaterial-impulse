.pragma library

// A label that does not fit its box, and what it costs to read the rest of it.
//
// Every long label in this shell elides, which is honest about the truncation
// and useless about the content: two networks called "BT-Hub6-KJXQ-guest" and
// "BT-Hub6-KJXQ-5GHz" are the same three words and an ellipsis, and nothing on
// screen will ever tell them apart. A marquee is the answer where the string
// is an IDENTITY the user did not write and cannot look up elsewhere.
//
// The arithmetic lives here, apart from the widget, for the reason
// placeholderFit.js does: what a marquee decides - whether the text overflows
// at all, how far it has to travel, how long that should take and where the
// bottom of that scale is - is answerable without a compositor, and the
// rendered result is not. `qmltestrunner` cannot lay out a StyledText against
// this tree's fonts (see tst_placeholder_fit.qml's own note), so a decision
// left inside the QML is a decision no check can reach.
//
// A .pragma library has no engine context, so nothing in here may touch Qt,
// Appearance or Config - every input arrives as an argument, and the one
// output that is a DURATION is a base, scaled by the caller through
// `Appearance.animation.scale()`.

// How long one pixel of overflow takes to travel, in BASE milliseconds. About
// 36 px/s at the default multiplier, which is a reading pace rather than a
// ticker-tape one; taken from the surveyed implementation
// (docs/p3drovfx-animation-research-2026-08-16.md §3.11) rather than picked.
var MS_PER_PIXEL = 28;

// The shortest a traverse may be, whatever the distance. Without it a label
// overflowing by six pixels twitches: the eye is drawn to a movement that
// resolves before it can be looked at, which is worse than the truncation.
var MIN_TRAVEL_MS = 3500;

// The hold at each end of the traverse. It is NOT a motion tier and is
// deliberately not scaled by anything - see `dwell()`.
var DWELL_MS = 1200;

// The hold at each end when the user has asked for reduced motion. At the
// motion floor the traverse itself has no duration at all, so the dwell is the
// whole cycle: at 1200ms the label would swap ends roughly once a second for
// as long as it is on screen, which is a flicker rather than a marquee. This
// is what stops the accessibility state producing the most aggressive motion
// in the shell.
var REDUCED_DWELL_MS = 3000;

// Sub-pixel slack on the overflow test. A text's implicit width and its box's
// width are laid out by different passes and routinely disagree by a fraction
// of a pixel on a settled layout; without slack that reads as a permanent
// overflow and a label that fits scrolls by half a pixel forever.
var OVERFLOW_SLACK = 1;

function _finite(value) {
    var number = Number(value);
    return isFinite(number) ? number : 0;
}

// Does the text need a marquee at all?
//
// A box with no width yet has not been laid out - it is not "infinitely
// overflowing". Reading it that way starts every marquee in the shell at its
// full travel on the frame its surface is built, before the layout that will
// usually make it unnecessary has run.
function overflows(contentWidth, boxWidth) {
    var box = _finite(boxWidth);
    if (box <= 0)
        return false;
    return _finite(contentWidth) > box + OVERFLOW_SLACK;
}

// How far the text has to travel to bring its far end into the box. The
// overflow, never the whole string: the marquee is a ping-pong over what is
// hidden, not a wrap-around, so the first character is on screen at rest and
// the label reads normally until it moves.
function travelDistance(contentWidth, boxWidth) {
    if (!overflows(contentWidth, boxWidth))
        return 0;
    return _finite(contentWidth) - _finite(boxWidth);
}

// How long that travel should take, in BASE milliseconds.
//
// Distance-proportional rather than a catalogued tier, because the thing being
// held constant is the speed the text passes the eye - a tier would run a
// three-word overrun and a whole sentence at the same clock, so one of the two
// is unreadable. The floor is the same argument at the other end.
//
// The caller scales this through `Appearance.animation.scale()`: it is motion,
// so the shell's speed slider retimes it like everything else, and the
// reduce-motion floor collapses it to zero - which is a snap between the two
// ends rather than a scroll, and the reason `dwell()` takes reduceMotion.
function travelDuration(contentWidth, boxWidth) {
    var distance = travelDistance(contentWidth, boxWidth);
    if (distance <= 0)
        return 0;
    return Math.max(MIN_TRAVEL_MS, Math.round(distance * MS_PER_PIXEL));
}

// The hold at each end, in real milliseconds - not a base, because nothing
// scales it.
//
// The multiplier does not, because a dwell is reading time rather than motion:
// a user who set the shell to 0.5x asked for slower animation, not for half as
// long to read a device name. Reduce motion does not either, and this is the
// half that matters - at the motion floor every catalogued duration is 0, so a
// scaled dwell would leave a label snapping between its two ends every frame.
function dwell(reduceMotion) {
    return reduceMotion ? REDUCED_DWELL_MS : DWELL_MS;
}
