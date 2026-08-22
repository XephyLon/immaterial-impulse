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

    property bool reallyOpen: false

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                closeAnimTimer.stop();
                root.reallyOpen = true;
            } else {
                closeAnimTimer.restart();
            }
        }
    }

    Timer {
        id: closeAnimTimer
        interval: Appearance.animation.sidebarSlideExit.duration
        onTriggered: root.reallyOpen = false
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

            mask: Region {
                item: content
            }

            implicitHeight: Appearance.sizes.wallpaperSelectorHeight
            implicitWidth: Appearance.sizes.wallpaperSelectorWidth

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
                content.slideIn();
            }
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

                // The tier the next slide will run on, held as plain state and
                // assigned by whichever direction is about to move - never bound
                // to `GlobalStates.wallpaperSelectorOpen`.
                //
                // Bound to the flag, the exit ran the ENTRANCE curve. A
                // `NumberAnimation` latches its duration and easing when it
                // starts, the close is an imperative `content.y = ...` from the
                // handler for that flag, and nothing orders the Behavior's
                // bindings to re-evaluate before the handler that starts it. So
                // the animation could begin still holding the open branch.
                //
                // Measured off a 60fps capture rather than reasoned about: the
                // close moved 659px, and its per-frame share of that distance
                // went 32.2 16.1 10.8 8.0 6.8 ... against 32.6 14.5 10.4 8.1 6.5
                // predicted by `standardDecel` (the entrance) and 1.3 3.2 4.4 5.3
                // 5.9 by `standardAccel` (the exit). The panel decelerated OUT -
                // a third of the way gone in one frame, then coasting - which is
                // the opposite of what leaving should look like.
                //
                // Assignment before the write is what makes it deterministic: a
                // QML property write propagates to dependent bindings
                // synchronously, so the animation has the right tier by the time
                // `y` moves. `DesktopContextMenu.qml:46-47` holds its two the
                // same way and for the same reason.
                property int slideDuration: Appearance.animation.sidebarSlideEnter.duration
                property int slideEasingType: Appearance.animation.sidebarSlideEnter.type
                property var slideCurve: Appearance.animation.sidebarSlideEnter.bezierCurve

                function takeTier(tier) {
                    content.slideDuration = tier.duration;
                    content.slideEasingType = tier.type;
                    content.slideCurve = tier.bezierCurve;
                }

                function slideIn() {
                    content.takeTier(Appearance.animation.sidebarSlideEnter);
                    content.y = -content.height;
                    Qt.callLater(() => { content.y = 0; });
                }

                Connections {
                    target: GlobalStates
                    function onWallpaperSelectorOpenChanged() {
                        if (!GlobalStates.wallpaperSelectorOpen) {
                            content.takeTier(Appearance.animation.sidebarSlideExit);
                            content.y = -content.height;
                        }
                    }
                }

                Behavior on y {
                    NumberAnimation {
                        duration: content.slideDuration
                        easing.type: content.slideEasingType
                        easing.bezierCurve: content.slideCurve
                    }
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