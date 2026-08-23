import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // The window outlives the flag by exactly one exit animation, and it is the
    // ANIMATION that says when - never a Timer whose interval has to be kept in
    // agreement with a duration declared somewhere else.
    //
    // It used to be a Timer at `sidebarSlideExit.duration`, and measured on a
    // 60fps capture that timer fired while the panel still had a quarter of its
    // travel left: the last frame drawn was 74.6% of the way out and the next
    // one had no panel in it at all. An accelerating exit carries most of its
    // distance in its last frames, and a Behavior's animation starts a frame
    // after the write that triggers it, so the two ends were never going to
    // line up. The exit's own `onFinished` cannot be early or late.
    property bool reallyOpen: false

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen)
                root.reallyOpen = true;
        }
    }

    Loader {
        id: wallpaperSelectorLoader
        active: root.reallyOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property var monitor: WM.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: Hyprland.focusedMonitor?.name == monitor?.name

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            // The mask reads a proxy pinned to the card's LAYOUT rect, never
            // the card itself: the card scales during its entrance
            // (transformOrigin Top, 0.85 -> 1), a Region maps the item
            // through its render transform, and Hyprland snapshots the input
            // region when the focus grab is installed - which is
            // mid-entrance. The snapshot kept the scaled rect forever: a
            // ~60px band inside each side edge of the surface where hover
            // and clicks still reached the card (the live input region had
            // settled to full size) but the grab's stale copy said
            // "outside", so any click there cleared the grab and dismissed
            // the selector. Click-mapped live: x <= 2021 and >= 3099 closed
            // on a 1960..3160 surface, which is the 0.9-scale rect exactly.
            // Anchors track layout geometry and ignore render transforms, so
            // the proxy is the full rect at every instant.
            Item {
                id: inputRegionProxy
                anchors.fill: content
            }
            mask: Region {
                item: inputRegionProxy
            }

            implicitHeight: Appearance.sizes.wallpaperSelectorHeight
            implicitWidth: Appearance.sizes.wallpaperSelectorWidth

            Component.onCompleted: GlobalFocusGrab.addDismissable(panelWindow)
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.wallpaperSelectorOpen = false;
                }
            }

            // The selector's card carries its own shadow, and the catch-all
            // surface blur frosted it - the same defect #82 fixed for the
            // panels. The region covers the card and not the elevation margin
            // the shadow lives in.
            WindowBlurRegion {
                targetWindow: panelWindow
                regionItem: content.blurTarget
                regionRadius: content.blurTargetRadius
            }

            WallpaperSelectorContent {
                id: content
                width: parent.width
                height: parent.height
                x: 0
                y: 0

                // The selector ARRIVES rather than flies in, and that is the
                // whole of what changed here.
                //
                // It used to travel its own full height - 690px of the panel,
                // measured as 728px of drawn edge on a 1080p screen - on the
                // sidebar tiers. Those exist for a sidebar: a panel fastened to
                // a screen edge, whose travel IS its own extent, so a full-extent
                // slide reads as the panel coming out of the edge it lives on.
                // This is not one of those. It is a floating sheet with a margin
                // on all four sides, and moving it 690px in 250ms - 2760px/s
                // average - is the largest single motion in this shell, on the
                // surface with the most content in it.
                //
                // Two things measured on a 60fps capture in a nested compositor,
                // with a static desktop and a control pair of frames that
                // differed by 0.0000:
                //
                //  - the ENTRANCE never animated at all. `slideIn()` wrote
                //    `content.y = -content.height` and then deferred `y = 0` to
                //    the next turn of the event loop, so the Behavior was handed
                //    a start value and a target one turn apart: the first write
                //    started an animation that had advanced ~0ms when the second
                //    retargeted it back. Measured, 99.6% of the travel landed in
                //    ONE frame and the panel simply appeared. So the surface the
                //    user complained about was popping in and sliding out.
                //  - the EXIT was cut off. See the window's own lifetime above.
                //
                // What replaces it is the entrance the rest of this shell already
                // uses for a surface that appears in place - `DesktopMenu` and
                // `EditWidgetMenu` both open at `scale: 0.85` with the opacity at
                // zero - and it is docs/M3_GUIDELINES.md §2's "Component Entrance
                // and Exit" written out: a spatial transformation combined with
                // an effects transition, on `elementMoveEnter` in and - see the
                // exit animation's own note for why it is not the exit tier -
                // the effects tier out. It is also what
                // docs/p3drovfx-motion-measured-2026-08-22.md §2.1 measured off
                // the sibling fork: horizontal displacement of ZERO on every
                // frame of the entrance, the element already at its final
                // position, only opacity and a scale moving.
                //
                // ONE scalar drives both channels, because §2 requires opacity to
                // finish on the same schedule as the scale - two Behaviors at two
                // tiers is what makes a component reach full opacity while still
                // growing, which reads as a hiccup. The two sites named above are
                // the shell's existing examples of exactly that split; this one
                // does not repeat it.
                //
                // The third property the survey measured - a small rise - is
                // deliberately NOT here. Its job is to say which direction the
                // element comes from, and `transformOrigin: Item.Top` already
                // says it: the sheet is pinned under the bar and unfurls out of
                // its own top edge. A translate on top of that would push the top
                // edge past the window's own, where the surface clips it.
                //
                // Started animations rather than a `Behavior`, for
                // ExpandablePanel's reason and one more: a Behavior branching on
                // the flag is the tier race lint_behavior_tier_race.py exists
                // for, and a Behavior's animation never raises `finished`
                // (motion_policy.js records the probe), which is exactly what the
                // window's lifetime needs.
                property real openProgress: 0

                readonly property real entranceScaleFrom: 0.85
                opacity: content.openProgress
                scale: content.entranceScaleFrom
                    + (1 - content.entranceScaleFrom) * content.openProgress
                transformOrigin: Item.Top

                function arrive() {
                    exitAnim.stop();
                    enterAnim.start();
                }
                function leave() {
                    enterAnim.stop();
                    exitAnim.start();
                }

                // `openProgress` starts at 0 as its DECLARED value and is only
                // ever written to 1. A start value written through the animated
                // property is the defect this replaces.
                Component.onCompleted: content.arrive()

                Connections {
                    target: GlobalStates
                    function onWallpaperSelectorOpenChanged() {
                        if (GlobalStates.wallpaperSelectorOpen)
                            content.arrive();
                        else
                            content.leave();
                    }
                }

                NumberAnimation {
                    id: enterAnim
                    target: content
                    property: "openProgress"
                    to: 1
                    // The tier written out rather than taken from its factory:
                    // `elementMoveEnter`'s component carries `alwaysRunToEnd`,
                    // and this is a transition the user can reverse mid-flight
                    // by toggling the selector twice. Written out it is still a
                    // whole tier - duration, type and curve together - which is
                    // what §2 asks for.
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }

                NumberAnimation {
                    id: exitAnim
                    target: content
                    property: "openProgress"
                    to: 0
                    // The effects tier rather than `elementMoveExit`, and this
                    // is the one place the guideline's two sections disagree
                    // with each other - §2's "Component Entrance and Exit" says
                    // take the exit tier, and its "Expandable Content" pairs a
                    // spatial exit with opacity on `elementMoveFast`. One
                    // scalar can only take one curve, so the tie is broken by
                    // what the channels actually are: this exit is an opacity
                    // transition with a 15% scale nudge on it, not a departure
                    // across the screen, and `emphasizedAccel` is shaped for
                    // the second. Measured, at its own 200ms it spends 46% of
                    // the whole transition in its last two frames - which on
                    // something flying off screen is an element already gone,
                    // and on an opacity is a panel that sits above 45% for
                    // two thirds of the exit and then blinks out. The capture
                    // showed exactly that: 14, 23, 57, 100 percent gone on the
                    // last four frames.
                    //
                    // `expressiveEffects` at the same 200ms is 84% done by
                    // 83ms and tails off, so the panel reads as dismissed
                    // immediately and the remainder is a fade nobody has to
                    // watch. That is also where the survey's §5.4 points - it
                    // measured their exits at 117-150ms against our catalogued
                    // 200 - reached without minting a tier.
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    // The window's lifetime IS this animation's, so the panel
                    // cannot be destroyed part way out.
                    onFinished: root.reallyOpen = false
                }
            }
        }
    }

    function toggleWallpaperSelector() {
        if (Config.options.wallpaperSelector.useSystemFileDialog) {
            Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
            return;
        }
        GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
    }

    IpcHandler {
        target: "wallpaperSelector"

        function toggle(): void {
            root.toggleWallpaperSelector();
        }

        function random(): void {
            Wallpapers.randomFromCurrentFolder();
        }
    }

    GlobalShortcut {
        name: "wallpaperSelectorToggle"
        description: "Toggle wallpaper selector"
        onPressed: {
            root.toggleWallpaperSelector();
        }
    }

    GlobalShortcut {
        name: "wallpaperSelectorRandom"
        description: "Select random wallpaper in current folder"
        onPressed: {
            Wallpapers.randomFromCurrentFolder();
        }
    }
}