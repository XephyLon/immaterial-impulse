import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool detach: false
    property bool pin: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical

    function toggleDetach() {
        root.detach = !root.detach;
    }

    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else root.pin = !root.pin;
    }

    Component.onCompleted: {
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        sidebarLoader.item.contentParent.children = [root.sidebarContent];
    }

    onDetachChanged: {
        if (root.detach) {
            GlobalFocusGrab.removeDismissable(sidebarLoader.item) // Remove sidebar from the focus grab system
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            detachedSidebarLoader.item.contentParent.children = [sidebarContent];
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarLoader.item.contentParent.children = [sidebarContent];
        }
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: panelWindow

            // The surface stays mapped; the panel is what slides. See
            // SidebarRight.qml and EdgeSlide.qml - the window following the
            // open flag was a 61ms stall of the whole shell per open.
            readonly property EdgeSlide slide: EdgeSlide {
                open: GlobalStates.sidebarLeftOpen
                travel: panelWindow.implicitWidth
                direction: -1
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
                    if (GlobalStates.sidebarLeftOpen)
                        GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
            Connections {
                target: GlobalStates
                function onSidebarLeftOpenChanged() {
                    if (GlobalStates.sidebarLeftOpen) {
                        focusGrabAfterCommit.framesLeft = 2;
                        // The window used to be rebuilt per open, and the tabs'
                        // own creation-time focus grabs picked the focus item.
                        // A persistent window is created once, at boot, without
                        // keyboard focus - so an open has to say where keys go
                        // or the window activates with NO focus item and every
                        // key is dropped at the content item. (The right
                        // sidebar's loader does this with a `focus:` binding on
                        // the open flag.)
                        root.sidebarContent?.focusActiveItem();
                    } else {
                        focusGrabAfterCommit.framesLeft = 0;
                        GlobalFocusGrab.removeDismissable(panelWindow);
                    }
                }
            }

            property bool extend: false
            property real sidebarWidth: panelWindow.extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.pin ? sidebarWidth : 0
            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            // ...and on a surface that is mapped all the time, an unconditional
            // OnDemand is a panel that holds the keyboard while showing nothing.
            WlrLayershell.keyboardFocus: GlobalStates.sidebarLeftOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
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

            // Gated on the flag: a mapped surface with an unconditional mask
            // takes every click on the left edge of the screen, panel or not.
            mask: Region {
                item: GlobalStates.sidebarLeftOpen ? sidebarLeftBackground : null
            }

            // Blur only the panel body. The drop shadow is drawn in the
            // surface's elevation margin, outside this region, so the
            // compositor's blur can't frost it (#82). Pairs with rules.lua
            // turning the whole-surface layerrule blur off for this namespace.
            // Follows the body as it slides, withdrawn once it is off screen.
            WindowBlurRegion {
                targetWindow: panelWindow
                regionItem: panelWindow.slide.shown ? sidebarLeftBackground : null
                regionRadius: sidebarLeftBackground.radius
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    panelWindow.hide();
                }
            }

            // Content
            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
                visible: sidebarLeftBackground.visible
            }
            Rectangle {
                id: sidebarLeftBackground
                visible: panelWindow.slide.shown
                anchors.top: parent.top
                anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                color: Appearance.colors.colLayer0
                border.width: Appearance.borderWidth.standard
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                // An `x`, not a transform: the blur region and the shadow both
                // follow the item's geometry, and a transform moves neither.
                x: Appearance.sizes.hyprlandGapsOut + panelWindow.slide.offset
                // The slide's curtain (see EdgeSlide.reveal): entrances run
                // under it, so a member still parked is dimness, not a hole.
                opacity: panelWindow.slide.reveal

                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O) {
                            panelWindow.extend = !panelWindow.extend;
                        } else if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        } else if (event.key === Qt.Key_P) {
                            root.togglePin();
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            onVisibleChanged: {
                if (!visible) GlobalStates.sidebarLeftOpen = false;
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color: Appearance.colors.colLayer0

                Keys.onPressed: (event) => {
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.detach = !root.detach;
        }
    }

}