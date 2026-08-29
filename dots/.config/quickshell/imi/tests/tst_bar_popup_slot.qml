import QtTest
import "../modules/common/functions/bar_popup_slot.js" as Slot

// Who gets the bar's one popup card.
//
// Ten popups share one card, so every open is a claim against the other nine,
// and the rules for that used to live inside StyledPopup where nothing could
// reach them: arbitration between instances, written in the type being
// arbitrated. Moving them to a pure function is what makes them assertable at
// all - none of these cases needs a compositor, a bar or a pointer.
//
// Each case below is a behaviour someone would notice, not a branch someone
// would count.
TestCase {
    name: "BarPopupSlotTest"

    function test_an_empty_slot_is_granted() {
        compare(Slot.resolveClaim({
            editMode: false, isOccupant: false, occupantPresent: false,
            occupantPinned: false, candidatePinned: false
        }), Slot.GRANT);
    }

    function test_a_hover_takes_the_card_from_an_unpinned_neighbour() {
        // Travelling along the bar swaps the card from widget to widget; that
        // is the ordinary case and the reason the card exists.
        compare(Slot.resolveClaim({
            editMode: false, isOccupant: false, occupantPresent: true,
            occupantPinned: false, candidatePinned: false
        }), Slot.GRANT);
    }

    function test_a_pinned_popup_holds_the_card_against_a_hover() {
        // Pinning is a deliberate click, often with a focus grab over it; a
        // hover is an accident of where the pointer passed. Travelling across
        // the bar must not take the tray overflow out from under the pointer.
        compare(Slot.resolveClaim({
            editMode: false, isOccupant: false, occupantPresent: true,
            occupantPinned: true, candidatePinned: false
        }), Slot.REFUSE);
    }

    function test_a_second_deliberate_click_outranks_the_first() {
        // A pinned candidate beats a pinned occupant: the user asking for the
        // second thing is the user being done with the first.
        compare(Slot.resolveClaim({
            editMode: false, isOccupant: false, occupantPresent: true,
            occupantPinned: true, candidatePinned: true
        }), Slot.GRANT);
    }

    function test_edit_mode_refuses_every_claim() {
        // The mode makes the bar's widgets inert. A popup opening over an
        // inert bar is the widget answering the pointer after all, through a
        // path the mode's input eater cannot reach.
        compare(Slot.resolveClaim({
            editMode: true, isOccupant: false, occupantPresent: false,
            occupantPinned: false, candidatePinned: false
        }), Slot.REFUSE);
    }

    function test_edit_mode_refuses_the_popup_that_was_already_holding_it() {
        // Ahead of the already-holding shortcut deliberately: opening the mode
        // vacates the slot, and a popup still under the pointer would take it
        // straight back if being the occupant were checked first.
        compare(Slot.resolveClaim({
            editMode: true, isOccupant: true, occupantPresent: true,
            occupantPinned: false, candidatePinned: false
        }), Slot.REFUSE);
    }

    function test_holding_it_already_is_not_a_swap() {
        // A popup claims on several paths - hover, becoming visible,
        // completion - so the same popup asks repeatedly. Answering GRANT
        // there would tell the arbiter to notify an outgoing holder that is
        // the caller itself, and it would drop its own hover grace.
        compare(Slot.resolveClaim({
            editMode: false, isOccupant: true, occupantPresent: true,
            occupantPinned: false, candidatePinned: false
        }), Slot.ALREADY);
    }

    function test_nothing_is_granted_to_nothing() {
        compare(Slot.resolveClaim(null), Slot.REFUSE);
    }

    // ---- the other half of a handover ---------------------------------

    function test_a_lingering_popup_drops_its_grace() {
        // Pointer has left both the widget and the card, and only the 180ms
        // grace is holding it up. This is the case the drop exists for: the
        // neighbour collapses on the frame the pointer lands on the new
        // widget rather than painting over it for a fifth of a second.
        verify(Slot.shouldDropHoverHold({
            hoverHeld: true, targetHovered: false, popupHovered: false
        }));
    }

    function test_a_popup_under_the_pointer_keeps_its_hold() {
        verify(!Slot.shouldDropHoverHold({
            hoverHeld: true, targetHovered: true, popupHovered: false
        }));
    }

    function test_a_popup_whose_own_card_is_hovered_keeps_its_hold() {
        // Reaching INTO the card counts: the pointer has left the bar widget
        // but the user is using the popup.
        verify(!Slot.shouldDropHoverHold({
            hoverHeld: true, targetHovered: false, popupHovered: true
        }));
    }

    function test_a_popup_that_was_not_holding_has_nothing_to_drop() {
        verify(!Slot.shouldDropHoverHold({
            hoverHeld: false, targetHovered: false, popupHovered: false
        }));
    }
}
