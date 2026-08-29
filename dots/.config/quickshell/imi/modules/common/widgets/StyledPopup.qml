import qs
import qs.modules.common
import "../functions/bar_popup_slot.js" as BarPopupSlot
import QtQuick

// A bar popup is a declaration plus a hover state machine; it owns no surface.
// Its content is declared here, unparented and windowless, and BarPopupOverlay
// parents it into the one card it hosts on one static layer surface per screen
// when this popup claims GlobalStates.activeBarPopup.
QtObject {
    id: root
    property Item hoverTarget
    default property Item contentItem
    // Inset between the card's body and this popup's content. Denser popups keep
    // the default; content-heavy ones raise it.
    property real contentPadding: Appearance.spacing.space100
    // The section entrance's rise, one token for every popup. A below-the-fold
    // section opts into the overlay's gated cascade by declaring
    // `property real appear: 1` and folding it into its opacity, a scale
    // (bar_popup_unroll.js entranceScale, which derives its excursion from
    // this rise over the section's own width) and a Translate of
    // entranceOffset(appear, root.entranceRise). The HERO section never opts
    // in - the card opens at its height so it is legible on frame one. See
    // BarPopupOverlay's wave for the gate, and
    // tests/test_bar_popup_section_entrance.py for the register.
    readonly property real entranceRise: Appearance.spacing.space250
    // Interactive popups can remain open after the pointer leaves the bar.
    // Passive users retain the original hover-only behavior.
    property bool pinnedOpen: false

    // Set while this popup is animating its OWN size - a card that changes
    // depth in place, rather than one being swapped for another.
    //
    // The card normally eases its width and height to whatever it is showing.
    // If the content is easing too, the card's Behavior is chasing a value that
    // is still moving: it trails the whole way, and since the content is
    // centred in the card, the parts that overhang get clipped - a header
    // vanishing off the top for the length of the transition. While this is
    // set the card takes the content's size directly, so the single animation
    // is the content's own and the card is exactly as big as what it holds on
    // every frame.
    property bool contentDrivesSize: false
    readonly property bool targetHovered: hoverTarget?.containsMouse ?? false
    property bool popupHovered: false
    property bool hoverHeld: false
    readonly property bool popupVisible: pinnedOpen || hoverHeld

    // Written by the overlay that is showing this popup, for consumers that need
    // to know whether this popup currently holds the card.
    property var surfaceWindow: null

    // Raised by the overlay's focus grab when a click lands outside the card.
    // A pinned popup handles this by clearing whatever flag pins it.
    //
    // A signal rather than the overlay writing `pinnedOpen = false`: SysTray
    // *binds* pinnedOpen to its own state, and assigning to it would break the
    // binding rather than close the popup.
    signal dismissRequested()

    // Raised by the overlay immediately *before* it unparents this popup's
    // content from the card. Anything holding a reference to the window the
    // content is currently in - a menu anchored to it, say - has to let go here:
    // once the reparent starts, Qt tears the item's window association down and
    // re-evaluates every binding that read it, with the item half destroyed.
    signal aboutToRelease()

    // Windows that belong to this popup but are not the card: a tray item's
    // context menu is a real window of its own, opened from content sitting on
    // the shared card. The overlay's focus grab has to count them as inside, or
    // opening one reads as a click outside the card and dismisses the popup that
    // owns it.
    property var extraGrabWindows: []

    onPopupVisibleChanged: {
        // A click-toggled popup's widget never reports hover (a RippleButton has
        // no containsMouse; the plugin adapters set hoverEnabled: false), so
        // becoming visible is the only moment it can claim the card.
        if (popupVisible) claimSlot();
    }
    Component.onCompleted: if (popupVisible) claimSlot()

    // A bar widget can be dropped from the layout while its card is up (the
    // tray empties, a plugin is disabled), and that destroys this popup and its
    // content out from under the overlay. Vacate the slot so the card exits
    // instead of stranding at its last size with a live input mask.
    Component.onDestruction: GlobalStates.releaseBarPopup(root)

    function updateHoverHold() {
        if (targetHovered || popupHovered) {
            hoverCloseTimer.stop();
            hoverHeld = true;
        } else if (hoverHeld) {
            hoverCloseTimer.restart();
        }
    }

    property Timer hoverCloseTimer: Timer {
        interval: 180
        onTriggered: root.hoverHeld = false
    }

    // Ask for the shared card. Whether the answer is yes is not this object's
    // business: the rules live with the slot, in GlobalStates.claimBarPopup.
    //
    // This used to arbitrate here - read the slot, compare occupants, gate on
    // Edit Mode and write itself in - which made a widget in the shared folder
    // the referee for a global resource shared by ten of its own instances,
    // three of them in bundled plugins.
    function claimSlot() {
        GlobalStates.claimBarPopup(root);
    }

    // Asked by the arbiter when another popup takes the card: drop the hover
    // grace if that is all that is keeping this one up. The CONDITION stays
    // here because it is about this popup's own pointer state and nothing
    // else - the arbiter knows who is holding the card, not where the pointer
    // is.
    function releaseHoverHold() {
        if (BarPopupSlot.shouldDropHoverHold({
            hoverHeld: root.hoverHeld,
            targetHovered: root.targetHovered,
            popupHovered: root.popupHovered,
        })) {
            root.hoverCloseTimer.stop();
            root.hoverHeld = false;
        }
    }

    onTargetHoveredChanged: {
        // Claim the moment this popup's widget is hovered, so any neighbour that
        // was still open collapses before it can paint over us.
        if (targetHovered) claimSlot();
        updateHoverHold();
    }
    onPopupHoveredChanged: updateHoverHold()

}
