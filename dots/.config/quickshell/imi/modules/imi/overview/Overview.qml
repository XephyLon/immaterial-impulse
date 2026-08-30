import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    // The CONTENT outlives the flag by exactly one exit animation, and it is
    // the ANIMATION that says when - the same rule, and for the same reason, as
    // `modules/imi/wallpaperSelector/WallpaperSelector.qml`'s `reallyOpen`
    // records: a Behavior's animation starts a frame after the write that
    // triggers it, and an accelerating exit carries most of its distance in its
    // last frames, so a Timer at the exit tier's own duration tears the card
    // down with the transition still on screen.
    //
    // This used to be the WINDOW's lifetime, and that was the overview's last
    // per-open stall: a destroyed-and-rebuilt window blocks the shell's one
    // GUI thread the way the sidebars' did before EdgeSlide.qml (61ms
    // measured there, and this is the largest surface in the shell). The
    // surface now stays mapped for the life of the shell - `rules.lua`
    // already turns the compositor's map animation off for this namespace,
    // and there is no map left to animate - while `reallyOpen` gates what it
    // shows: the column's visibility, the grid loader, and (through
    // `openProgress`) the blur regions. A closed overview is a full-screen
    // surface with a null input mask, keyboardFocus None and nothing drawn,
    // which is exactly what the bar's surface is under a fullscreen window.
    //
    // One surface PER SCREEN, and the open picks which one shows. A persistent
    // surface has to say which screen it lives on: a PanelWindow with no
    // `screen:` asks the compositor to choose (Quickshell passes a null
    // output), and Hyprland answers with the monitor that has focus AT
    // CREATION. While the window was rebuilt per open that was "the focused
    // monitor, every time" - the behaviour a multi-monitor user relies on.
    // Created once at boot, it was "whichever monitor had focus at boot,
    // forever" (#297: the overview stuck to the primary monitor after
    // 0.30.0). So the family is one window per screen, each pinned to its
    // own output, and `targetScreen` - the focused monitor's name, read once
    // at the open edge and held for the open - decides which of them opens.
    // Latched, not live: focus moving mid-open must not teleport the card.
    property string targetScreen: ""
    property PanelWindow activeWindow: null

    function latchTarget() {
        overviewScope.targetScreen = WM.focusedMonitor?.name ?? "";
    }

    // The focused monitor's window, latched now. Called at EVERY open edge:
    // the first version of this asked "already open?" first and handed back
    // the window that was showing - but at the open edge the flag has just
    // flipped, so that question was always yes once any open had happened,
    // and every open after the first reused the first screen's window. On
    // one monitor that is invisible; on two it is #297 reopened ("still on
    // the primary"). Reproduced on a nested two-output Hyprland, where the
    // shell's WM.focusedMonitor followed every focusedmon event and the
    // latch still returned the stale window.
    function windowForFocusedMonitor() {
        overviewScope.latchTarget();
        const windows = overviewWindows.instances;
        return windows.find(w => w.modelData.name === overviewScope.targetScreen)
            ?? windows[0] ?? null;
    }

    // The window a search-prefix toggle should address. Already open: the
    // one that is showing, wherever focus has moved since (the text goes
    // where the user is looking). Closed: the focused monitor's, latched now;
    // the open edge that follows latches again and lands on the same answer.
    function targetWindow() {
        if (GlobalStates.overviewOpen && overviewScope.activeWindow)
            return overviewScope.activeWindow;
        return overviewScope.windowForFocusedMonitor();
    }

    // One dispatcher for the whole family, at the scope: per-window handlers
    // would each read the latch, and nothing orders a Connections in one
    // window against the latch being written in another. Here the latch is
    // written, THEN the one target is opened.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                overviewScope.activeWindow = overviewScope.windowForFocusedMonitor();
                overviewScope.activeWindow?.open();
            } else {
                overviewScope.dontAutoCancelSearch = false;
                overviewScope.activeWindow?.close();
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            GlobalStates.overviewOpen = false;
        }
    }

    Variants {
        id: overviewWindows
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property ShellScreen modelData
            screen: modelData
            readonly property bool isTarget: overviewScope.activeWindow === panelWindow
            property bool reallyOpen: false
            property string searchingText: ""

            WlrLayershell.namespace: "quickshell:overview"
            // Overlay only while open over a TRUE fullscreen window on this
            // monitor (#339): Hyprland composites fullscreen windows above the
            // Top layer, so the overview opened behind a game or a video.
            // Closed, and open anywhere else, it stays on Top - an overlay
            // surface covering the screen while a game runs would cost the
            // game its direct scanout, which is the cost the issue's reply
            // promised not to add. `fullscreenByMonitorName` reads hyprctl's
            // fullscreen integer, so a maximized window does not count.
            readonly property bool monitorHasFullscreen:
                HyprlandData.fullscreenByMonitorName[panelWindow.screen?.name ?? ""] ?? false
            WlrLayershell.layer: (GlobalStates.overviewOpen && panelWindow.isTarget && panelWindow.monitorHasFullscreen)
                ? WlrLayer.Overlay : WlrLayer.Top
            // Gated on being the target as well as on the flag: with one surface
            // per screen, every sibling would otherwise turn OnDemand on the same
            // open and the compositor would pick which of them gets the keyboard.
            WlrLayershell.keyboardFocus: (GlobalStates.overviewOpen && panelWindow.isTarget) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            // The proxy, not the column: the card scales during its entrance and
            // a Region maps the item through its render transform, while
            // Hyprland snapshots the input region when the focus grab lands -
            // two frames into that entrance. The selector shipped the full
            // failure (see WallpaperSelector.qml's mask note for the click-map);
            // this one had the same scaled item under its mask and the same
            // grab timing. Anchors track layout geometry and ignore render
            // transforms, so the proxy is the settled rect at every instant.
            Item {
                id: inputRegionProxy
                anchors.fill: columnLayout
            }
            mask: Region {
                item: (GlobalStates.overviewOpen && panelWindow.isTarget) ? inputRegionProxy : null
            }

            // Blur only the painted body cards. This one surface carries two of
            // them - the search widget and the overview below it - and both draw a
            // drop shadow in the elevation margin around themselves, which the
            // catch-all whole-surface blur frosted (#89, the deferred half of #82).
            // Pairs with rules.lua turning the layerrule blur off for this
            // namespace. The niri style contributes nothing (see NiriOverview.qml).
            //
            // The gate is the CARD's own progress rather than the open flag, and
            // that only started mattering when the card got a transition. A blur
            // region is a rectangle the compositor frosts whether or not anything is
            // drawn over it: gated on the flag it arrives a full entrance before the
            // card does and stays a full exit after it has gone, which is a frosted
            // ghost of the card with no card in it. It cannot be faded - the region
            // is on or off - so it switches at the half way point of the card's own
            // opacity, where the card itself is the least transparent thing it can
            // be while the switch happens. This is a choice about where to put an
            // unavoidable step, not a measurement.
            readonly property bool bodyFrosted: columnLayout.openProgress >= 0.5
            onBodyFrostedChanged: blurRegion.publishNow()

            // The composed region's INNER items swap identity at runtime - the
            // grid is rebuilt by its loader every open, and bodyFrosted flips
            // both items in and out - and BackgroundEffect's live geometry
            // tracking follows a given item, not a binding that replaces it.
            // On the persistent surface nothing else republishes any more (the
            // window never resizes and never remaps), so the first open showed
            // the frost where the HALF-BUILT grid had been when the region was
            // first pushed: a sharp unblurred band down the card's left edge,
            // user-reported. Each identity flip republishes now; the settle
            // timer inside publishNow covers the layout that follows it.
            WindowBlurRegion {
                id: blurRegion
                targetWindow: panelWindow
                region: Region {
                    Region {
                        item: panelWindow.bodyFrosted ? searchWidget.backgroundItem : null
                        radius: searchWidget.backgroundRadius
                    }
                    Region {
                        item: (panelWindow.bodyFrosted && (overviewLoader.item?.backgroundPainted ?? false)) ? overviewLoader.item.backgroundItem : null
                        radius: overviewLoader.item?.backgroundRadius ?? 0
                    }
                }
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // The grab is taken after the surface has RENDERED two frames with the
            // card open, not in the tick the flag flips - the sidebars' rule (see
            // SidebarRight.qml): on a surface that is mapped all the time the new
            // `keyboardFocus` value rides the next commit, and a grab that reaches
            // Hyprland first lands on a surface it still knows as interactivity
            // None, is cleared within milliseconds, and the clear is read as a
            // click-outside that closes the overview it just opened.
            FrameAnimation {
                id: focusGrabAfterCommit
                property int framesLeft: 0
                running: framesLeft > 0
                onTriggered: {
                    if (--framesLeft > 0)
                        return;
                    if (GlobalStates.overviewOpen)
                        GlobalFocusGrab.addDismissable(panelWindow);
                }
            }

            function open() {
                // The content is asked for before the card is asked to
                // arrive, in this order: an entrance started against an
                // unbuilt card is an entrance nothing advances.
                panelWindow.reallyOpen = true;
                if (!overviewScope.dontAutoCancelSearch) {
                    searchWidget.cancelSearch();
                }
                focusGrabAfterCommit.framesLeft = 2;
                // A persistent window is created once, at boot, without
                // keyboard focus - so an open has to say where keys go
                // (the sidebars' lesson, SidebarLeft.qml) or the window
                // activates with no focus item and every key is dropped.
                searchWidget.focusSearchInput();
                columnLayout.arrive();
            }

            function close() {
                searchWidget.disableExpandAnimation();
                focusGrabAfterCommit.framesLeft = 0;
                GlobalFocusGrab.dismiss();
                columnLayout.leave();
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight

            function setSearchingText(text) {
                searchWidget.setSearchingText(text);
                searchWidget.focusFirstItem();
            }

            Column {
                id: columnLayout
                visible: panelWindow.reallyOpen
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                }
                spacing: -Appearance.spacing.space100

                // ONE scalar drives both channels, because docs/M3_GUIDELINES.md §2
                // requires the opacity to finish on the same schedule as the scale -
                // two Behaviors at two tiers is what makes a component reach full
                // opacity while it is still growing, which reads as a hiccup.
                //
                // No translate, and that is a constraint rather than a preference.
                // The sibling fork drops this card in from above the screen edge and
                // pays for the room with a negative margin on all four sides of the
                // surface; here the column is anchored to the top of a surface that
                // stops at the bar's exclusive zone, so a rise would be drawn
                // outside the window and clipped. `transformOrigin: Item.Top`
                // already says which edge the card comes out of: it unfurls
                // downwards from its own top edge, which is where it hangs from.
                //
                // The entrance takes `elementMoveSmall` for its CURVE, not only its
                // duration. `expressiveFastSpatial` overshoots by construction (its
                // second control point is 1.67), so the card settles with a bounce
                // rather than easing flat into place - which is the half of the
                // fork's "bounce" style that survives having no room to travel.
                // The overshoot is left on the scale and clamped off the opacity: a
                // card that fades past opaque and back is a flicker, a card that
                // grows 2% past its size and settles is the bounce.
                property real openProgress: 0
                readonly property real entranceScaleFrom: 0.9

                opacity: Math.min(1, columnLayout.openProgress)
                scale: columnLayout.entranceScaleFrom
                    + (1 - columnLayout.entranceScaleFrom) * columnLayout.openProgress
                transformOrigin: Item.Top

                function arrive() {
                    exitAnim.stop();
                    enterAnim.start();
                }
                function leave() {
                    enterAnim.stop();
                    exitAnim.start();
                }

                // Started animations rather than a `Behavior`: a Behavior never
                // raises `finished` at any duration (motion_policy.js records the
                // probe), and this exit's `finished` is what owns the window.
                // `openProgress` starts at 0 as its DECLARED value and is only ever
                // written by these two - a start value written through the animated
                // property is what lint_animated_start_write.py exists for.
                NumberAnimation {
                    id: enterAnim
                    target: columnLayout
                    property: "openProgress"
                    to: 1
                    duration: Appearance.animation.elementMoveSmall.duration
                    easing.type: Appearance.animation.elementMoveSmall.type
                    easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                }

                NumberAnimation {
                    id: exitAnim
                    target: columnLayout
                    property: "openProgress"
                    to: 0
                    // The effects tier rather than `elementMoveExit`, for the
                    // reasoning WallpaperSelector.qml's exit animation writes out:
                    // this is an opacity transition with a scale nudge on it rather
                    // than a departure across the screen, and `emphasizedAccel` at
                    // its own 200ms spends 46% of the transition in its last two
                    // frames - on an opacity that is a card which sits there and
                    // then blinks out.
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    // The window's lifetime IS this animation's.
                    onFinished: panelWindow.reallyOpen = false
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.overviewOpen = false;
                    } else if (event.key === Qt.Key_Left) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r-1");
                    } else if (event.key === Qt.Key_Right) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r+1");
                    }
                }

                SearchWidget {
                    id: searchWidget
                    anchors.horizontalCenter: parent.horizontalCenter
                    Synchronizer on searchingText {
                        property alias source: panelWindow.searchingText
                    }
                }

                Loader {
                    id: overviewLoader
                    active: panelWindow.reallyOpen && (Config?.options.overview.enable ?? true)
                    onItemChanged: blurRegion.publishNow()
                    sourceComponent: (Config?.options.overview.style ?? "default") === "niri" ? niriComponent : defaultComponent

                    Component {
                        id: defaultComponent
                        OverviewWidget {
                            screen: panelWindow.screen
                            visible: (panelWindow.searchingText == "")
                        }
                    }

                    Component {
                        id: niriComponent
                        NiriOverview {
                            screen: panelWindow.screen
                            panelWindow: panelWindow
                            visible: (panelWindow.searchingText == "")
                        }
                    }
                }
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.targetWindow()?.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.targetWindow()?.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    function toggleSymbols() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.targetWindow()?.setSearchingText(Config.options.search.prefix.symbols);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
        // Which screen's window the last open landed on - what
        // tests/run_persistent_surface_focus_probe.sh reads after moving focus between
        // two outputs. Empty until the first open.
        function activeScreen(): string {
            return overviewScope.activeWindow?.modelData.name ?? "";
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }

    GlobalShortcut {
        name: "overviewSymbolsToggle"
        description: "Toggle material symbols search on overview widget"

        onPressed: {
            overviewScope.toggleSymbols();
        }
    }
}