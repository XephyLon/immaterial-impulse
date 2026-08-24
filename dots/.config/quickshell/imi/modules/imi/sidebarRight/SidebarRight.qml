import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical

    PanelWindow {
        id: panelWindow

        // The surface stays mapped for the life of the shell; the PANEL is
        // what opens and closes, and EdgeSlide draws that. `visible` used to
        // follow the open flag, which destroyed and rebuilt this window on
        // every gesture - see EdgeSlide.qml for what that cost, measured.
        // (No `visible:` here at all: the default is true, and a persistent
        // Top-layer surface is buried under a fullscreen window by Hyprland
        // the same way the bar's is.)
        readonly property EdgeSlide slide: EdgeSlide {
            open: GlobalStates.sidebarRightOpen
            travel: entranceWrapper.width
            direction: 1
        }

        // A mapped surface with no mask takes every click on its rectangle,
        // and this one is a strip down the whole right edge of the screen.
        mask: Region {
            item: GlobalStates.sidebarRightOpen ? entranceWrapper : null
        }

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        // The grab is taken after the surface has RENDERED two frames with the
        // panel open, not in the tick the flag flips. On a surface that is
        // mapped all the time there is no map to carry the new
        // `keyboardFocus` to the compositor - it goes out with the next commit,
        // and a grab that reaches Hyprland before that commit is a grab on a
        // surface it still knows as keyboard-interactivity None: Hyprland
        // clears it within milliseconds, and `onDismissed` reads the clear as
        // a click outside and closes the panel it just opened. A 1ms Timer
        // lost that race on the left sidebar (grab at +10ms, cleared at +14ms)
        // and won it on the right (+32ms) - so the wait is for frames, which
        // is the thing the commit actually rides on.
        FrameAnimation {
            id: focusGrabAfterCommit
            property int framesLeft: 0
            running: framesLeft > 0
            onTriggered: {
                if (--framesLeft > 0)
                    return;
                if (GlobalStates.sidebarRightOpen)
                    GlobalFocusGrab.addDismissable(panelWindow);
            }
        }
        Connections {
            target: GlobalStates
            function onSidebarRightOpenChanged() {
                if (GlobalStates.sidebarRightOpen) {
                    focusGrabAfterCommit.framesLeft = 2;
                } else {
                    focusGrabAfterCommit.framesLeft = 0;
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        // Blur only the panel body (exposed by SidebarRightContent) — the drop
        // shadow in the elevation margin stays outside the region, so the
        // compositor's blur can't frost it (#82). Pairs with rules.lua turning
        // the whole-surface layerrule blur off for this namespace.
        //
        // The region follows the body as it slides (a Region tracks its item's
        // geometry, and the slide is an `x`, not a transform, for exactly that
        // reason), and is withdrawn once the panel is off screen - a frosted
        // rectangle with no panel over it is the overview's ghost, again.
        WindowBlurRegion {
            targetWindow: panelWindow
            regionItem: panelWindow.slide.shown ? (sidebarContentLoader.item?.backgroundItem ?? null) : null
            regionRadius: sidebarContentLoader.item?.backgroundItem?.radius ?? 0
        }

        margins {
            top: {
                if (!centerOnly) return 0;
                switch (Config.options.bar.cornerStyle) {
                case 0: return -Appearance.sizes.barHeight;
                case 1: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                case 2: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                case 3: return -Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut;
                default: return 0;
                }
            }
        }

        Item {
            anchors.fill: parent

            Item {
                id: entranceWrapper
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: sidebarWidth
                clip: true
                // On `shown`, not on the open flag: the flag drops on frame
                // one of the exit, and the exit is 400ms of this item moving.
                visible: panelWindow.slide.shown

                property real cachedParentWidth: sidebarWidth
                readonly property real restX: cachedParentWidth - width
                x: restX + panelWindow.slide.offset

                Connections {
                    target: entranceWrapper.parent
                    function onWidthChanged() {
                        if (entranceWrapper.parent.width > 0)
                            entranceWrapper.cachedParentWidth = entranceWrapper.parent.width;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                    z: -1
                }

                Loader {
                    id: sidebarContentLoader
                    active: panelWindow.slide.shown || Config?.options.sidebar.keepRightSidebarLoaded
                    anchors {
                        fill: parent
                        margins: Appearance.sizes.hyprlandGapsOut
                        leftMargin: Appearance.sizes.elevationMargin
                    }
                    width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                    height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

                    focus: GlobalStates.sidebarRightOpen
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: SidebarRightContent {}
                }
            }
        }

        IpcHandler {
            target: "sidebarRight"

            function toggle(): void {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }

            function close(): void {
                GlobalStates.sidebarRightOpen = false;
            }

            function open(): void {
                GlobalStates.sidebarRightOpen = true;
            }
        }

        GlobalShortcut {
            name: "sidebarRightToggle"
            description: "Toggles right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }
        GlobalShortcut {
            name: "sidebarRightOpen"
            description: "Opens right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = true;
            }
        }
        GlobalShortcut {
            name: "sidebarRightClose"
            description: "Closes right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = false;
            }
        }
    }
}