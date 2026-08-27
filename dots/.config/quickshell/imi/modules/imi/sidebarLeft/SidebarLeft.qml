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
    // Shell-wide, not per window: with one surface per screen a state kept on
    // the window would be a preference the user set on one monitor and lost by
    // opening the panel on another.
    property bool extend: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical

    // One surface PER SCREEN, and the open picks which one shows - the
    // overview's shape (Overview.qml), for the bug it was fixed for.
    //
    // A persistent surface has to say which screen it lives on: a PanelWindow
    // with no `screen:` asks the compositor to choose (Quickshell passes a
    // null output), and Hyprland answers with the monitor that has focus AT
    // CREATION. While the window was rebuilt per open that was "the focused
    // monitor, every time". Kept mapped for the life of the shell
    // (EdgeSlide.qml, and the 61ms per-open stall it removed), it became
    // "whichever monitor had focus at boot, forever" - #297.
    //
    // `targetScreen` is the focused monitor's name, read once at the open edge
    // and held for the open. Latched, not live: focus moving mid-open must not
    // teleport the panel.
    property string targetScreen: ""
    property PanelWindow activeWindow: null

    function latchTarget() {
        root.targetScreen = WM.focusedMonitor?.name ?? "";
    }

    // The focused monitor's window, latched now. Called at EVERY open edge:
    // asking "already open?" first and handing back the window that is showing
    // is right for a toggle pressed while the panel is up, and wrong here - at
    // the open edge the flag has just flipped, so that question is always yes
    // once any open has happened, and every open after the first reuses the
    // first screen's window (#297 reopened).
    function windowForFocusedMonitor() {
        root.latchTarget();
        const windows = sidebarWindows.instances;
        return windows.find(w => w.modelData.name === root.targetScreen) ?? windows[0] ?? null;
    }

    // The content is ONE tree that MOVES, where the overview builds one grid
    // per screen. Two reasons it is not the overview's shape here. This panel
    // is the AI chat, the translator, the media pane and the Phone tab, and
    // every one of them holds state the user is in the middle of - a draft
    // message, a scroll position, a conversation - so N copies would mean the
    // panel forgetting what it was showing whenever it opened on another
    // monitor; and the reparent already exists, because detaching the sidebar
    // into a floating window has always moved this same tree.
    //
    // It is a plain reparent rather than an assignment to `children`: the old
    // spelling replaced the whole list, which took the background's own
    // click-eating MouseArea out of the scene along with it.
    function hostContent(host) {
        if (!root.sidebarContent || !host)
            return;
        if (root.sidebarContent.parent === host)
            return;
        root.sidebarContent.parent = host;
    }

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

    // The content is built into the boot-focused monitor's window rather than
    // left parentless: an unparented tree has no scene graph, so the first open
    // would pay the build EdgeSlide's persistent surface exists to avoid. Every
    // later open re-latches and moves it only if the target changed.
    Component.onCompleted: {
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        root.activeWindow = root.windowForFocusedMonitor();
        root.hostContent(root.activeWindow?.contentParent ?? null);
    }

    onDetachChanged: {
        if (root.detach) {
            root.activeWindow?.close(); // Slide the panel out and drop its grab
            detachedSidebarLoader.active = true; // Load detached window
            root.hostContent(detachedSidebarLoader.item.contentParent);
        } else {
            detachedSidebarLoader.active = false; // Unload detached window
            root.activeWindow = root.windowForFocusedMonitor();
            root.hostContent(root.activeWindow?.contentParent ?? null);
            if (GlobalStates.sidebarLeftOpen)
                root.activeWindow?.open();
        }
    }

    // One dispatcher for the whole family, at the scope: per-window handlers
    // would each read the latch, and nothing orders a Connections in one window
    // against the latch being written in another. Here the latch is written,
    // the content is moved to the window that is about to show it, and THEN
    // that one window opens.
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (root.detach)
                return; // The floating window follows the flag on its own
            if (GlobalStates.sidebarLeftOpen) {
                root.activeWindow = root.windowForFocusedMonitor();
                root.hostContent(root.activeWindow?.contentParent ?? null);
                root.activeWindow?.open();
            } else {
                root.activeWindow?.close();
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    Variants {
        id: sidebarWindows
        model: Quickshell.screens

        PanelWindow { // Window
            id: panelWindow
            required property ShellScreen modelData
            screen: modelData
            readonly property bool isTarget: root.activeWindow === panelWindow

            // The gesture, per window. Written only by open()/close(), which
            // only the scope's dispatcher calls - so exactly one window ever
            // slides, and no sibling can start an entrance on the frame the
            // flag flips while the latch has not moved yet.
            property bool panelOpen: false

            // The surface stays mapped; the panel is what slides. See
            // SidebarRight.qml and EdgeSlide.qml - the window following the
            // open flag was a 61ms stall of the whole shell per open.
            readonly property EdgeSlide slide: EdgeSlide {
                open: panelWindow.panelOpen
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
                    if (panelWindow.panelOpen)
                        GlobalFocusGrab.addDismissable(panelWindow);
                }
            }

            function open() {
                panelWindow.panelOpen = true;
                focusGrabAfterCommit.framesLeft = 2;
                // The window used to be rebuilt per open, and the tabs' own
                // creation-time focus grabs picked the focus item. A
                // persistent window is created once, at boot, without
                // keyboard focus - so an open has to say where keys go or
                // the window activates with NO focus item and every key is
                // dropped at the content item. (The right sidebar's loader
                // does this with a `focus:` binding on the open flag.)
                root.sidebarContent?.focusActiveItem();
            }

            function close() {
                panelWindow.panelOpen = false;
                focusGrabAfterCommit.framesLeft = 0;
                GlobalFocusGrab.removeDismissable(panelWindow);
            }

            property real sidebarWidth: root.extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            // The target predicate is what keeps a pinned sidebar from
            // reserving its width on every monitor at once: an exclusive zone
            // is a protocol value on each surface, and there are N of them now.
            exclusiveZone: (root.pin && panelWindow.isTarget) ? panelWindow.sidebarWidth : 0
            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            // ...and on a surface that is mapped all the time, an unconditional
            // OnDemand is a panel that holds the keyboard while showing nothing.
            // The target predicate for the same reason the mask carries it: N
            // surfaces turning OnDemand on one open leaves the compositor to
            // pick which of them gets the keyboard.
            WlrLayershell.keyboardFocus: (GlobalStates.sidebarLeftOpen && panelWindow.isTarget) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            margins {
                top: {
                    if (!root.centerOnly) return 0;
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
            // And on the target, or every screen's edge takes them at once.
            mask: Region {
                item: (GlobalStates.sidebarLeftOpen && panelWindow.isTarget) ? sidebarLeftBackground : null
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
                    z: -1
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O) {
                            root.extend = !root.extend;
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

    // At the scope, never inside the family: an IpcHandler is registered by
    // its `target` and a GlobalShortcut by its `name`, both process-wide, so
    // a second instance is a startup failure rather than a duplicate.
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

        // Which screen's window the last open landed on - what
        // tests/run_persistent_surface_focus_probe.sh reads after moving focus between
        // two outputs. Empty until the first open.
        function activeScreen(): string {
            return root.activeWindow?.modelData.name ?? "";
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
