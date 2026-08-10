pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }
                property bool superShow: false
                // Stay shown while a bar popup is open so it isn't orphaned above
                // a hidden bar; the popup closes itself on pointer-leave, then the
                // bar hides. See issues #30, #31.
                property bool mustShow: hoverRegion.containsMouse || superShow
                    || ((GlobalStates.mediaControlsOpen || GlobalStates.sysTrayOverflowOpen) && Config?.options.bar.autoHide.dismissPopups)
                property var thisMonitorData: HyprlandData.monitors.find(m => m.name === barRoot.screen?.name)
                property bool monitorHasFullscreen: HyprlandData.workspaceById[thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false
                property bool monitorHasSpecialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows)) ? 0 : Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                WlrLayershell.namespace: "quickshell:bar"
                // Overlay layer only while special workspace sits on top of a fullscreen window on this monitor,
                // else Top layer so fullscreen apps cover the bar as normal (Hyprland buries Top layer under fullscreen+special).
                WlrLayershell.layer: (monitorHasFullscreen && monitorHasSpecialOpen) ? WlrLayer.Overlay : WlrLayer.Top
                // A detached bar style (cornerStyle 3) holds the surface off the
                // screen edge by barDetachMargin. That gap is not part of the
                // surface, so with auto-hide on it is a band the pointer can
                // never reach: the reveal strip lives *inside* the window, and
                // hovering the gap reaches whatever is behind it instead. It
                // also made hiding look wrong - the bar slid up inside a
                // surface that already started below the edge, so the gap above
                // it never moved.
                //
                // While auto-hide is on the surface takes the edge and the
                // content carries the gap instead, which looks identical and
                // costs no surface reconfiguration.
                readonly property real detachInset: Appearance.sizes.barDetachInset
                implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding + detachInset
                // When Overlay-layer, bar shares a layer with the screen-corner click zones (ScreenCorners.qml)
                // and same-layer overlap is resolved by stacking, not layer priority - bar was winning and
                // swallowing the tiny corner-open hit rects. Carve them out of the bar's own mask so clicks
                // reach the corners underneath. Only relevant on the edge the bar and corners share.
                property bool cutOutCornerOpenZones: (monitorHasFullscreen && monitorHasSpecialOpen) && (Config.options.bar.bottom === Config.options.sidebar.cornerOpen.bottom)
                property int cornerOpenCutWidth: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionWidth : 0
                property int cornerOpenCutHeight: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionHeight : 0
                mask: Region {
                    item: hoverMaskRegion
                    Region {
                        intersection: Intersection.Subtract
                        x: 0
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                    Region {
                        intersection: Intersection.Subtract
                        x: barRoot.width - barRoot.cornerOpenCutWidth
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                }
                color: "transparent"

                // Blur only the painted body shapes. The bar's drop shadow and
                // the screen-rounding margin live outside these rects, so the
                // compositor's blur can't frost them (#82) — same treatment as
                // the sidebars. Pairs with rules.lua turning the whole-surface
                // layerrule blur off for this namespace. The RoundCorner
                // decorators and the Islands pills are left out: a region is a
                // plain rect, so covering their transparent parts would frost
                // bare wallpaper; they are opaque by default and merely read as
                // unblurred translucency under transparency mode. The M3
                // wrappers ARE covered (dc4e0662c) - under that style they are
                // the only painted shapes, so leaving them out meant an empty
                // region and no blur at all.
                WindowBlurRegion {
                    targetWindow: barRoot
                    region: Region {
                        Region {
                            item: barContent.backgroundPainted ? barContent.backgroundItem : null
                            radius: barContent.backgroundItem.radius
                        }
                        Region {
                            item: barContent.centerPillPainted ? barContent.centerPillItem : null
                            topLeftRadius: barContent.centerPillItem.topLeftRadius
                            topRightRadius: barContent.centerPillItem.topRightRadius
                            bottomLeftRadius: barContent.centerPillItem.bottomLeftRadius
                            bottomRightRadius: barContent.centerPillItem.bottomRightRadius
                        }
                        // The M3 wrappers. Their own radius is `full` (9999),
                        // which is a "round me completely" sentinel rather than
                        // a length, so it is resolved to the real pill radius
                        // here - a region is a plain rounded rect and would
                        // otherwise be squared off against the painted shape.
                        Region {
                            item: barContent.materialPillsPainted ? barContent.leftMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.leftMaterialPillItem.width, barContent.leftMaterialPillItem.height) / 2)
                        }
                        Region {
                            item: barContent.materialPillsPainted ? barContent.centerMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.centerMaterialPillItem.width, barContent.centerMaterialPillItem.height) / 2)
                        }
                        Region {
                            item: barContent.materialPillsPainted ? barContent.rightMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.rightMaterialPillItem.width, barContent.rightMaterialPillItem.height) / 2)
                        }
                    }
                }

                // Positioning
                anchors {
                    top: !Config.options.bar.bottom
                    bottom: Config.options.bar.bottom
                    left: true
                    right: true
                }

                // The dead row is on the right and bottom screen edges only, so
                // a top-anchored bar has nothing to overhang. See the tokens'
                // own comment in Appearance for what these two terms are and
                // why the bottom one used to come out +5 instead of -1.
                margins {
                    top: Appearance.sizes.barDetachMargin
                    right: Appearance.sizes.barDeadPixelOverhang
                    bottom: Appearance.sizes.barBottomMargin
                }

                // Include in focus grab
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(barRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                }

                // Drag files over the bar to pop the drop shelf out below it -
                // the Wayland-native drop shelf summon (a DropArea learns of a
                // drag the moment it crosses this surface; nothing else can).
                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onEntered: drag => {
                        if (!Config.options.dropShelf.dragToBarReveal || !drag.hasUrls) {
                            drag.accepted = false
                            return
                        }
                        drag.accepted = true
                        if (!GlobalStates.dropShelfOpen) {
                            GlobalStates.dropShelfX = drag.x
                            GlobalStates.dropShelfAnchorBelow = !Config.options.bar.bottom
                            GlobalStates.dropShelfY = Config.options.bar.bottom
                                ? barRoot.screen.height - Appearance.sizes.barHeight - 10
                                : Appearance.sizes.barHeight
                            GlobalStates.dropShelfOpen = true
                            DropShelf.armAutoDismiss()
                        }
                    }
                    onDropped: drop => {
                        if (!drop.hasUrls) {
                            drop.accepted = false
                            return
                        }
                        DropShelf.addItems(drop.urls)
                        drop.accept()
                    }
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    // The window's input region, and the only thing that can
                    // reveal an auto-hidden bar: the pointer has to land inside
                    // it for hoverRegion to see anything at all.
                    //
                    // Kept inside the surface on purpose. Anchoring this to
                    // barContent with negative margins was the obvious way to
                    // write it, but while the bar is hidden barContent sits at
                    // y = -barHeight, so the published rect began roughly a
                    // whole bar height *above* the surface and the compositor
                    // was left to clamp it. The reveal strip is only
                    // hoverRegionWidth (2px by default) tall once clamped, so
                    // an off-by-one there costs half of it - and the row that
                    // goes missing is y = 0, the screen edge, which is exactly
                    // where a pointer thrown at the top of the screen lands.
                    Item {
                        id: hoverMaskRegion
                        readonly property real reveal: Config.options.bar.autoHide.hoverRegionWidth
                        // The detach inset counts as the bar's own space, not a
                        // gap outside it. Leaving it out made the strip start
                        // below the edge whenever the bar was *shown*, so a
                        // pointer resting on row 0 revealed the bar, fell
                        // outside the strip the moment it appeared, and hid it
                        // again - a reveal/hide oscillation for as long as the
                        // pointer stayed on the edge.
                        readonly property real rawTop: barContent.y - reveal - Appearance.sizes.barDetachInset
                        readonly property real rawBottom: barContent.y + barContent.height + reveal

                        x: 0
                        width: parent.width
                        y: Math.max(0, rawTop)
                        height: Math.max(0, Math.min(parent.height, rawBottom) - y)
                    }

                    RoundCorner {
                        id: leftPillCorner
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0
                        x: barContent.centerPillX - implicitSize
                        implicitSize: Appearance.rounding.screenRounding
                        color: Appearance.colors.colBarBackground
                        corner: RoundCorner.CornerEnum.TopRight

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: leftPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: leftPillCorner
                                corner: RoundCorner.CornerEnum.BottomRight
                            }
                        }
                        AnchorChanges {
                            target: leftPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }

                    BarContent {
                        id: barContent
                        
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: (Config?.options.bar.autoHide.enable && !mustShow)
                                ? -Appearance.sizes.barHeight : barRoot.detachInset
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                        }
                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: (Config?.options.bar.autoHide.enable && !mustShow)
                                    ? -Appearance.sizes.barHeight : barRoot.detachInset
                            }
                        }
                    }

                    RoundCorner {
                        id: rightPillCorner
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0
                        x: barContent.centerPillX + barContent.centerPillWidth
                        implicitSize: Appearance.rounding.screenRounding
                        color: Appearance.colors.colBarBackground
                        corner: RoundCorner.CornerEnum.TopLeft

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: rightPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: rightPillCorner
                                corner: RoundCorner.CornerEnum.BottomLeft
                            }
                        }
                        AnchorChanges {
                            target: rightPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }
                    
                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 && !barContent.centerOnly// Hug

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    right: parent.right
                                    top: !Config.options.bar.bottom ? parent.top : undefined
                                    bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
