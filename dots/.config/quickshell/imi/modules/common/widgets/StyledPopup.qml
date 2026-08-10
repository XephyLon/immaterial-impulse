import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0
    // Inset between the popup's surface and its content. Denser popups keep the
    // default; content-heavy ones raise it.
    property real contentPadding: Appearance.spacing.space100
    // Interactive popups can remain open after the pointer leaves the bar.
    // Passive users retain the original hover-only behavior.
    property bool pinnedOpen: false
    readonly property bool targetHovered: hoverTarget?.containsMouse ?? false
    property bool popupHovered: false
    property bool hoverHeld: false
    readonly property bool popupVisible: pinnedOpen || hoverHeld
    // Stay lazy until the popup is first needed, then keep the window alive so
    // pointer transitions only flip visibility instead of destroying and
    // recreating layer-shell surfaces.
    property bool everShown: false
    // Opt in to the shared morphing card (BarPopupOverlay). The two paths
    // coexist by construction while the popups are migrated one at a time:
    // GlobalStates.activeBarPopup already coordinates across both, so a legacy
    // popup still closes when the slot changes and the overlay releases the
    // card whenever the slot holds a popup that has not opted in.
    property bool morph: false
    active: everShown && !morph
    onPopupVisibleChanged: {
        if (!popupVisible) return;
        everShown = true;
        // A click-toggled popup's widget never reports hover (a RippleButton
        // has no containsMouse; the plugin adapters set hoverEnabled: false),
        // so becoming visible is the only moment it can claim the card.
        claimSlot();
    }
    Component.onCompleted: if (popupVisible) claimSlot()

    // The overlay publishes its own PanelWindow here for whichever popup it is
    // currently showing. Consumers that need a window to hand to a focus grab
    // read `surfaceWindow` and do not care which path produced it.
    property var overlayWindow: null
    readonly property var surfaceWindow: morph ? overlayWindow : root.item

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

    // Claim the shared slot, which is now also a claim on the shared card.
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
    // hover-hold grace period (pointer no longer on our widget or our surface),
    // close now rather than overlapping the incoming popup during that window.
    Connections {
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

    component: PanelWindow {
        id: popupWindow

        // Bring contentItem reference into this scope
        property Item innerContent: root.contentItem

        visible: root.popupVisible
        color: "transparent"
        anchors.left: root.barEdge !== "right"
        anchors.right: root.barEdge === "right"
        anchors.top: root.barEdge !== "bottom"
        anchors.bottom: root.barEdge === "bottom"

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        property real centerOffsetX: Appearance.sizes.elevationMargin
        property real centerOffsetY: Appearance.sizes.elevationMargin

        function updatePosition() {
            if (!root.hoverTarget || !root.hoverTarget.QsWindow.window) return
            const base = root.hoverTarget.QsWindow.mapFromItem(
                root.hoverTarget,
                (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
            ).x
            const margin = Appearance.sizes.elevationMargin
            const maxLeft = popupWindow.screen.width - popupBackground.implicitWidth - margin - 10
            popupWindow.centerOffsetX = Math.max(margin, Math.min(base, maxLeft))

            const verticalBase = root.hoverTarget.QsWindow.mapFromItem(
                root.hoverTarget,
                0, (root.hoverTarget.height - popupBackground.implicitHeight) / 2
            ).y
            const maxTop = popupWindow.screen.height - popupBackground.implicitHeight - margin - 15
            popupWindow.centerOffsetY = Math.max(margin, Math.min(verticalBase, maxTop))
        }

        // Position is resolved imperatively on a zero-interval timer so the
        // popup's own margins never join the binding graph that produces them.
        // Recomputing on every show and on content resize keeps it correct
        // without reintroducing the create-map-destroy loop.
        Timer {
            id: positionTimer
            interval: 0
            onTriggered: popupWindow.updatePosition()
        }

        function schedulePosition() { positionTimer.restart() }

        Component.onCompleted: schedulePosition()
        onVisibleChanged: if (visible) schedulePosition()
        onScreenChanged: schedulePosition()

        Connections {
            target: root
            function onBarEdgeChanged() { popupWindow.schedulePosition() }
        }

        Connections {
            target: popupBackground
            function onImplicitWidthChanged() { popupWindow.schedulePosition() }
            function onImplicitHeightChanged() { popupWindow.schedulePosition() }
        }

        mask: Region {
            item: popupBackground
        }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        margins {
            left: {
                if (root.barEdge === "right") return 0
                if (root.barEdge === "left") return root.barThickness
                return centerOffsetX 
            }
            top: {
                if (root.barEdge === "bottom") return 0
                if (root.barEdge === "top") return root.barThickness
                return centerOffsetY
            }
            right: root.barEdge === "right" ? root.barThickness : 0
            bottom: root.barEdge === "bottom" ? root.barThickness : 0
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: root.contentPadding

            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }

            // Use local reference instead of crossing LazyLoader scope boundary
            implicitWidth: (popupWindow.innerContent?.implicitWidth ?? 0) + margin * 2
            implicitHeight: (popupWindow.innerContent?.implicitHeight ?? 0) + margin * 2

            color: Appearance.colors.colLayer1Base
            radius: Appearance.rounding.normal + 4
            border.width: Appearance.borderWidth.standard
            border.color: Appearance.colors.colLayer0Border

            HoverHandler {
                onHoveredChanged: root.popupHovered = hovered
            }

            // Reparent content here once the window is ready
            Component.onCompleted: {
                if (popupWindow.innerContent) {
                    popupWindow.innerContent.parent = popupBackground
                    popupWindow.innerContent.anchors.centerIn = popupBackground
                }
            }
            Component.onDestruction: root.popupHovered = false
        }
    }
}
