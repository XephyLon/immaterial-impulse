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
    property bool reallyOpen: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? columnLayout : null
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

        WindowBlurRegion {
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

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    focusGrabAfterCommit.framesLeft = 0;
                    GlobalFocusGrab.dismiss();
                    columnLayout.leave();
                } else {
                    // The content is asked for before the card is asked to
                    // arrive, in this order: an entrance started against an
                    // unbuilt card is an entrance nothing advances.
                    overviewScope.reallyOpen = true;
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
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: overviewScope.reallyOpen
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
                onFinished: overviewScope.reallyOpen = false
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
                active: overviewScope.reallyOpen && (Config?.options.overview.enable ?? true)
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

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    function toggleSymbols() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.symbols);
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