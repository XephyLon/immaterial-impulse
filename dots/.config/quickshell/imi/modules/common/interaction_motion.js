.pragma library

// The motion vocabulary every interactive element shares, as data.
//
// The point of expressing it here rather than as inline animations in each
// control is that the SELECTION is then testable: which state a set of input
// flags resolves to, what that state targets, and which transition carries the
// element there. How it looks is not reachable from a test; which curve and
// duration were chosen is.
//
// The states are ordered by precedence, not by how they are usually entered: a
// disabled control that still reports `hovered` is disabled.

var REST = "rest";
var HOVERED = "hovered";
var PRESSED = "pressed";
var DISABLED = "disabled";

function stateOf(flags) {
    if (flags && flags.enabled === false) return DISABLED;
    if (flags && flags.down) return PRESSED;
    if (flags && flags.hovered) return HOVERED;
    return REST;
}

// What the state asks the element to look like, as multipliers on whatever
// the element's own rest geometry is. `tokens` comes from Appearance so the
// numbers stay tunable in one place.
//
// Hover LIFTS (scale up, tint), press SETTLES (scale down, corners tighten).
// `press` is that same settle as a plain 0..1, for adopters whose geometry is
// not a multiple of anything - a control lerps its own pressed values with it
// rather than working backwards from `radiusScale`. `hover` is the same for
// the lift, and a pressed control is still hovered by it: a wash that fades
// out as the press lands would read as the control letting go.
// Disabled is opacity only - it must not move, because motion reads as
// affordance and there is none.
function targetsFor(state, tokens) {
    switch (state) {
    case PRESSED:
        return { scale: tokens.pressScale, radiusScale: tokens.pressRadiusScale,
                 hover: 1, press: 1, opacity: 1 };
    case HOVERED:
        return { scale: tokens.hoverScale, radiusScale: 1,
                 hover: 1, press: 0, opacity: 1 };
    case DISABLED:
        return { scale: 1, radiusScale: 1, hover: 0, press: 0,
                 opacity: tokens.disabledOpacity };
    default:
        return { scale: 1, radiusScale: 1, hover: 0, press: 0, opacity: 1 };
    }
}

// Which transition carries the element from one state to the next.
//
// Three rules make five animations read as one system:
//   - a press is acknowledged IMMEDIATELY, so it takes the fastest tier;
//   - the return is allowed to be slower than the arrival, and overshoots;
//   - a release animates even when the pointer has already left, so
//     pressed -> rest is a RELEASE, never a hover-out. Getting that wrong
//     leaves a control visibly stuck after a drag off its own edge.
//
// Anything to or from disabled has no motion at all: a control that animates
// as it greys out is claiming an interaction it will not honour.
function transitionFor(fromState, toState, tiers) {
    if (fromState === toState) return tiers.hold;
    if (fromState === DISABLED || toState === DISABLED) return tiers.instant;
    if (toState === PRESSED) return tiers.press;
    if (fromState === PRESSED) return tiers.release;
    if (toState === HOVERED) return tiers.hoverIn;
    return tiers.hoverOut;
}

// A transition is a curve, a duration, and nothing else - the element decides
// what it applies them to.
function isMotionless(transition) {
    return transition.duration === 0;
}
