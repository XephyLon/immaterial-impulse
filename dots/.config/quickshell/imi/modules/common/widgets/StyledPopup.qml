import qs
import qs.modules.common
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
    Component.onDestruction: {
        if (GlobalStates.activeBarPopup === root) GlobalStates.activeBarPopup = null;
    }

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

    // Claim the shared slot, which is also a claim on the shared card.
    // A pinned popup holds it: pinning is a deliberate click, often with a focus
    // grab over it, while a hover is an accident of where the pointer passed, so
    // travelling across the bar must not take the tray overflow or the Docker
    // panel out from under the pointer. The accepted cost is that while a popup
    // is pinned, hovering another bar widget produces nothing at all.
    //
    // The refusal lives here rather than in the overlay because the slot is the
    // shared resource: refusing to honour a claim would leave
    // GlobalStates.activeBarPopup pointing at a popup the card is not showing.
    function claimSlot() {
        // Edit Mode makes the bar's widgets inert, and a popup opening over an
        // inert bar is the widget answering the pointer after all - through a
        // claim path the mode's input eater cannot reach. Refused here because
        // this is the one gate all three claim paths (hover, popupVisible,
        // completion) already share.
        if (GlobalStates.editMode) return;
        const occupant = GlobalStates.activeBarPopup;
        if (occupant && occupant !== root && occupant.pinnedOpen && !root.pinnedOpen) return;
        GlobalStates.activeBarPopup = root;
    }

    onTargetHoveredChanged: {
        // Claim the moment this popup's widget is hovered, so any neighbour that
        // was still open collapses before it can paint over us.
        if (targetHovered) claimSlot();
        updateHoverHold();
    }
    onPopupHoveredChanged: updateHoverHold()

    // A different bar popup just took over. If we're only lingering on the
    // hover-hold grace period (pointer no longer on our widget or our card),
    // drop it now so the morph starts on the frame the pointer lands on the new
    // widget rather than 180ms later.
    property Connections slotWatcher: Connections {
        target: GlobalStates
        function onActiveBarPopupChanged() {
            if (GlobalStates.activeBarPopup !== root && root.hoverHeld
                    && !root.targetHovered && !root.popupHovered) {
                root.hoverCloseTimer.stop();
                root.hoverHeld = false;
            }
        }
    }

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
}
