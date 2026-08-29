.pragma library

// Who gets the bar's one popup card, as arithmetic.
//
// The bar hosts ten popups on ONE shared card, so opening any of them is a
// claim on a resource the other nine also want. That decision used to live
// inside StyledPopup - a component in modules/common/widgets, arbitrating a
// global resource between its own instances, three of which are in bundled
// plugins. It is a rule, not a rendering, and this is where the rules that can
// be tested live (see edit_mode.js, motion_policy.js, interaction_motion.js).
//
// Expressed here rather than in GlobalStates.qml for one concrete reason: the
// QML unit suite substitutes a test double for GlobalStates, so a rule written
// there would be tested through a copy of itself. A .js the real singleton
// imports has no second version to drift from.

var GRANT = "grant";       // the candidate takes the card
var REFUSE = "refuse";     // nothing changes
var ALREADY = "already";   // the candidate is already holding it

// `state` is { editMode, occupantPinned, occupantPresent, isOccupant,
//              candidatePinned }
//
// Two refusals, both older than this file and both moved here verbatim:
//
//   - Edit Mode makes the bar's widgets inert. A popup opening over an inert
//     bar is the widget answering the pointer after all, through a claim path
//     the mode's input eater cannot reach - so the mode refuses every new
//     claim for its whole length. This gate is checked FIRST, ahead of the
//     already-holding shortcut, because the mode's own opening vacates the
//     slot and a popup still hovered would otherwise re-take it.
//
//   - a PINNED occupant holds the card against a hover. Pinning is a
//     deliberate click, often with a focus grab over it; a hover is an
//     accident of where the pointer passed. Travelling across the bar must not
//     take the tray overflow or the Docker panel out from under the pointer.
//     The accepted cost: while one popup is pinned, hovering another bar
//     widget produces nothing at all. A pinned CANDIDATE outranks a pinned
//     occupant - that is a second deliberate click, and the user asking for
//     the second thing means they are done with the first.
function resolveClaim(state) {
    if (!state || state.editMode) return REFUSE;
    if (state.isOccupant) return ALREADY;
    if (state.occupantPresent && state.occupantPinned && !state.candidatePinned)
        return REFUSE;
    return GRANT;
}

// Whether a popup losing the card should drop its hover grace.
//
// Kept beside the claim because it is the other half of one handover: the
// outgoing popup collapses on the frame the pointer lands on the new widget
// rather than 180ms later, which is what stops a lingering neighbour painting
// over the popup that just opened. The condition is about the OUTGOING
// popup's own pointer state - the arbiter knows who holds the card, not where
// the pointer is.
function shouldDropHoverHold(state) {
    if (!state) return false;
    return state.hoverHeld === true
        && state.targetHovered !== true
        && state.popupHovered !== true;
}
