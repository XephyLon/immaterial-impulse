import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * "Work mode on" banner: a small top-centre pill on the focused screen that
 * slides in for the engine's flash window (Modes.flash, three seconds) and
 * takes no focus. Built only while something is showing or sliding out.
 */
Scope {
    id: root

    readonly property bool isOpen: GlobalStates.modeFlashActive && GlobalStates.modeFlashPayload !== null
    property bool exiting: false

    LazyLoader {
        active: root.isOpen || root.exiting

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: Quickshell.screens.length > 0
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

            WlrLayershell.namespace: "quickshell:modeFlashPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: true
            }

            // Below a top bar, else a margin from the edge.
            readonly property int topMarginValue: (!Config.options.bar.vertical && !Config.options.bar.bottom)
                ? Appearance.sizes.barHeight + Appearance.spacing.space150
                : Appearance.spacing.space300

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight + topMarginValue

            mask: Region {
                item: popupContent.staticMaskTarget
            }

            WindowBlurRegion {
                targetWindow: popupWindow
                regionItem: popupContent.background
                regionRadius: popupContent.background.radius
            }

            ModeFlashPopupContent {
                id: popupContent
                isOpen: root.isOpen
                payload: GlobalStates.modeFlashPayload
                topMarginValue: popupWindow.topMarginValue
                onIsExitAnimRunningChanged: root.exiting = isExitAnimRunning
            }
        }
    }
}
