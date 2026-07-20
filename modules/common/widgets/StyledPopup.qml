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
    active: everShown
    onPopupVisibleChanged: if (popupVisible) everShown = true

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

    onTargetHoveredChanged: updateHoverHold()
    onPopupHoveredChanged: updateHoverHold()

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
            readonly property real margin: Appearance.spacing.space100

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
