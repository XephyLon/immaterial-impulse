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

    // One surface PER SCREEN, and the open picks which one shows - the
    // overview's shape (Overview.qml), for the bug it was fixed for.
    //
    // A persistent surface has to say which screen it lives on: a PanelWindow
    // with no `screen:` asks the compositor to choose (Quickshell passes a
    // null output), and Hyprland answers with the monitor that has focus AT
    // CREATION. While the window was rebuilt per open that was "the focused
    // monitor, every time" - the behaviour a multi-monitor user relies on and
    // that nobody had ever written down. Kept mapped for the life of the
    // shell (EdgeSlide.qml, and the 61ms per-open stall it removed), it
    // became "whichever monitor had focus at boot, forever" - #297, reported
    // for the overview and then again for both sidebars.
    //
    // So the family is one window per output, and `targetScreen` - the
    // focused monitor's name, read once at the open edge and held for the
    // open - decides which of them opens. Latched, not live: focus moving
    // mid-open must not teleport the panel.
    property string targetScreen: ""
    property PanelWindow activeWindow: null

    function latchTarget() {
        root.targetScreen = WM.focusedMonitor?.name ?? "";
    }

    // The focused monitor's window, latched now. Called at EVERY open edge:
    // asking "already open?" first and handing back the window that is
    // showing is right for a toggle pressed while the panel is up, and wrong
    // here - at the open edge the flag has just flipped, so that question is
    // always yes once any open has happened, and every open after the first
    // reuses the first screen's window (#297 reopened).
    function windowForFocusedMonitor() {
        root.latchTarget();
        const windows = sidebarWindows.instances;
        return windows.find(w => w.modelData.name === root.targetScreen) ?? windows[0] ?? null;
    }

    // Which window `keepRightSidebarLoaded` preloads into before the first
    // open. Without it that setting would preload nothing at all - no window
    // is the target until an open has latched one - and the first open would
    // pay the content build the option exists to pay in advance.
    Component.onCompleted: {
        root.activeWindow = root.windowForFocusedMonitor();
    }

    // One dispatcher for the whole family, at the scope: per-window handlers
    // would each read the latch, and nothing orders a Connections in one
    // window against the latch being written in another. Here the latch is
    // written, THEN the one target is opened.
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                root.activeWindow = root.windowForFocusedMonitor();
                root.activeWindow?.open();
            } else {
                root.activeWindow?.close();
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            GlobalStates.sidebarRightOpen = false;
        }
    }

    Variants {
        id: sidebarWindows
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property ShellScreen modelData
            screen: modelData
            readonly property bool isTarget: root.activeWindow === panelWindow

            // The gesture, per window. Written only by open()/close(), which
            // only the scope's dispatcher calls - so exactly one window ever
            // slides, and no sibling can start an entrance on the frame the
            // flag flips while the latch has not moved yet.
            property bool panelOpen: false

            // The surface stays mapped for the life of the shell; the PANEL is
            // what opens and closes, and EdgeSlide draws that. `visible` used to
            // follow the open flag, which destroyed and rebuilt this window on
            // every gesture - see EdgeSlide.qml for what that cost, measured.
            // (No `visible:` here at all: the default is true, and a persistent
            // Top-layer surface is buried under a fullscreen window by Hyprland
            // the same way the bar's is.)
            readonly property EdgeSlide slide: EdgeSlide {
                open: panelWindow.panelOpen
                travel: entranceWrapper.width
                direction: 1
            }

            // A mapped surface with no mask takes every click on its rectangle,
            // and this one is a strip down the whole right edge of the screen.
            // Gated on being the TARGET as well as on the flag: with one
            // surface per screen, every sibling would otherwise take input on
            // the same open.
            mask: Region {
                item: (GlobalStates.sidebarRightOpen && panelWindow.isTarget) ? entranceWrapper : null
            }

            function hide() {
                GlobalStates.sidebarRightOpen = false;
            }

            function open() {
                panelWindow.panelOpen = true;
                focusGrabAfterCommit.framesLeft = 2;
            }

            function close() {
                panelWindow.panelOpen = false;
                focusGrabAfterCommit.framesLeft = 0;
                GlobalFocusGrab.removeDismissable(panelWindow);
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
                    if (panelWindow.panelOpen)
                        GlobalFocusGrab.addDismissable(panelWindow);
                }
            }

            exclusiveZone: 0
            implicitWidth: root.sidebarWidth
            WlrLayershell.namespace: "quickshell:sidebarRight"
            // The target predicate again: N surfaces turning OnDemand on one
            // open leaves the compositor to pick which of them gets the
            // keyboard.
            WlrLayershell.keyboardFocus: (GlobalStates.sidebarRightOpen && panelWindow.isTarget) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
                    if (!root.centerOnly) return 0;
                    switch (Config.options.bar.cornerStyle) {
                    case 0: return -Appearance.sizes.barHeight;
                    case 1: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                    case 4: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
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
                    width: root.sidebarWidth
                    clip: true
                    // On `shown`, not on the open flag: the flag drops on frame
                    // one of the exit, and the exit is 400ms of this item moving.
                    visible: panelWindow.slide.shown

                    property real cachedParentWidth: root.sidebarWidth
                    readonly property real restX: cachedParentWidth - width
                    x: restX + panelWindow.slide.offset
                    // The slide's curtain (see EdgeSlide.reveal): entrances run
                    // under it, so a member still parked is dimness, not a hole.
                    opacity: panelWindow.slide.reveal

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
                        // The keep-loaded half reads the target too: one content
                        // tree preloaded, on the screen the next open will land
                        // on, rather than one per monitor.
                        active: panelWindow.slide.shown
                            || (Config?.options.sidebar.keepRightSidebarLoaded && panelWindow.isTarget)
                        anchors {
                            fill: parent
                            margins: Appearance.sizes.hyprlandGapsOut
                            leftMargin: Appearance.sizes.elevationMargin
                        }
                        width: root.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                        height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

                        focus: GlobalStates.sidebarRightOpen && panelWindow.isTarget
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                panelWindow.hide();
                            }
                        }

                        sourceComponent: SidebarRightContent {}
                    }
                }
            }
        }
    }

    // At the scope, never inside the family: an IpcHandler is registered by
    // its `target` and a GlobalShortcut by its `name`, both process-wide, so
    // a second instance is a startup failure rather than a duplicate. These
    // lived inside the window while there was exactly one of it.
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

        // Which screen's window the last open landed on - what
        // tests/run_persistent_surface_focus_probe.sh reads after moving focus between
        // two outputs. Empty until the first open.
        function activeScreen(): string {
            return root.activeWindow?.modelData.name ?? "";
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
