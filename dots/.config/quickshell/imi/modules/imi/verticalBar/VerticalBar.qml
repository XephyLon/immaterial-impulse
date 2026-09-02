import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.bar as Bar

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            // The Lockscreen tab takes the bar down exactly as the real lock
            // does, through the same gate (spec §1.5) - a teardown/rebuild per
            // tab flip, same as per lock/unlock.
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
                && !GlobalStates.editLockPreview
            required property ShellScreen modelData
            component: PanelWindow {
                id: barRoot
                screen: barLoader.modelData

                property var brightnessMonitor: Brightness.getMonitorForScreen(barLoader.modelData)
                
                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: { barRoot.superShow = true }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else { showBarTimer.stop(); barRoot.superShow = false; }
                    }
                }
                property bool superShow: false
                // See Bar.qml / issues #30, #31: stay shown while a bar popup is open.
                // The editMode term is Bar.qml's too - the bar is edited in
                // place, so auto-hide is suspended by this expression and never
                // by a write to `visible`, which destroys a layer surface.
                property bool mustShow: hoverRegion.containsMouse || superShow
                    || GlobalStates.editMode
                    || ((GlobalStates.mediaControlsOpen || GlobalStates.sysTrayOverflowOpen) && Config?.options.bar.autoHide.dismissPopups)
                // Bar.qml's split, through the same component: the animated
                // zone is on barSpaceReserver and never on this surface, and
                // an `exclusiveZone` here - even 0 - would put this window back
                // into Normal mode and let the reserver push it off the edge.
                exclusionMode: ExclusionMode.Ignore
                property QtObject barSpaceReserver: Bar.BarExclusiveZoneReserver {
                    screen: barLoader.modelData
                    barNamespace: "quickshell:verticalBar"
                    vertical: true
                    farEdge: Config.options.bar.bottom
                    // No edgeMargin: this surface declares no margins, so the
                    // compositor adds nothing to the zone.
                    zone: (Config?.options.bar.autoHide.enable && (!barRoot.mustShow || !Config?.options.bar.autoHide.pushWindows)) ? 0 :
                        Appearance.sizes.baseVerticalBarWidth + ((Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 4) ? Appearance.sizes.hyprlandGapsOut : 0)
                        + (Config.options.bar.cornerStyle === 3 ? (Config.options.hyprland.general.gapsOut || 5) : 0)
                }
                WlrLayershell.namespace: "quickshell:verticalBar"
                // In Appearance for the reason Bar.qml's height is: Edit Mode
                // keeps its chrome clear of this surface and cannot measure it.
                implicitWidth: Appearance.sizes.verticalBarSurfaceWidth
                mask: Region { item: hoverMaskRegion }
                color: "transparent"

                // Blur only the painted body shapes — same treatment as the
                // horizontal bar (see Bar.qml for the full rationale). Pairs
                // with rules.lua turning the whole-surface layerrule blur off
                // for this namespace.
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
                        // The M3 wrappers, which are the ONLY painted shapes in
                        // that style - without these the region is empty and an
                        // M3 vertical bar gets no blur at all (#93).
                        //
                        // Appearance.rounding.full (9999) is a "round me
                        // completely" sentinel rather than a length, so it is
                        // resolved here against the real shape. These wrappers
                        // are taller than wide, unlike the horizontal bar's, so
                        // it is min(w, h) / 2: height / 2 would declare a radius
                        // far larger than the painted pill and square the region
                        // off against it.
                        Region {
                            item: barContent.materialPillsPainted ? barContent.topMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.topMaterialPillItem.width, barContent.topMaterialPillItem.height) / 2)
                        }
                        Region {
                            item: barContent.materialPillsPainted ? barContent.centerMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.centerMaterialPillItem.width, barContent.centerMaterialPillItem.height) / 2)
                        }
                        Region {
                            item: barContent.materialPillsPainted ? barContent.bottomMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.bottomMaterialPillItem.width, barContent.bottomMaterialPillItem.height) / 2)
                        }
                        // Float Islands' three plates.
                        Region {
                            item: barContent.topIslandPainted ? barContent.topIslandItem : null
                            radius: barContent.topIslandItem.radius
                        }
                        Region {
                            item: barContent.centerIslandPainted ? barContent.centerIslandItem : null
                            radius: barContent.centerIslandItem.radius
                        }
                        Region {
                            item: barContent.bottomIslandPainted ? barContent.bottomIslandItem : null
                            radius: barContent.bottomIslandItem.radius
                        }
                    }
                }

                anchors {
                    left: !Config.options.bar.bottom
                    right: Config.options.bar.bottom
                    top: true
                    bottom: true
                }

                Component.onCompleted: { GlobalFocusGrab.addPersistent(barRoot); }
                Component.onDestruction: { GlobalFocusGrab.removePersistent(barRoot); }

                MouseArea {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors.fill: parent

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            leftMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            rightMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    RoundCorner {
                        id: topPillCorner
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0
                        y: barContent.centerPillY - implicitSize
                        implicitSize: Appearance.rounding.screenRounding
                        color: Appearance.colors.colBarBackground
                        corner: RoundCorner.CornerEnum.BottomLeft

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: topPillCorner
                                anchors.left: undefined
                                anchors.right: barContent.right
                            }
                            PropertyChanges {
                                target: topPillCorner
                                corner: RoundCorner.CornerEnum.BottomRight
                            }
                        }
                        AnchorChanges {
                            target: topPillCorner
                            anchors.left: barContent.right
                            anchors.right: undefined
                        }
                    }

                    RoundCorner {
                        id: bottomPillCorner
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0
                        y: barContent.centerPillY + barContent.centerPillHeight
                        implicitSize: Appearance.rounding.screenRounding
                        color: Appearance.colors.colBarBackground
                        corner: RoundCorner.CornerEnum.TopLeft

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: bottomPillCorner
                                anchors.left: undefined
                                anchors.right: barContent.right
                            }
                            PropertyChanges {
                                target: bottomPillCorner
                                corner: RoundCorner.CornerEnum.TopRight
                            }
                        }
                        AnchorChanges {
                            target: bottomPillCorner
                            anchors.left: barContent.right
                            anchors.right: undefined
                        }
                    }

                    VerticalBarContent {
                        id: barContent
                        
                        implicitWidth: Appearance.sizes.verticalBarWidth
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: parent.left
                            right: undefined
                            leftMargin: (Config?.options.bar.autoHide.enable && !mustShow) 
                                ? -Appearance.sizes.verticalBarWidth 
                                : (Config.options.bar.cornerStyle === 3 ? (Config.options.hyprland.general.gapsOut || 5) : 0)
                        }
                        Behavior on anchors.leftMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: parent.right
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.rightMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: barContent.right
                            right: undefined
                        }
                        width: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 && !barContent.centerOnly

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: barContent.left
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: topCorner
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"
                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges { topCorner.corner: RoundCorner.CornerEnum.TopRight }
                                }
                            }
                            RoundCorner {
                                id: bottomCorner
                                anchors {
                                    bottom: parent.bottom
                                    left: !Config.options.bar.bottom ? parent.left : undefined
                                    right: Config.options.bar.bottom ? parent.right : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"
                                corner: RoundCorner.CornerEnum.BottomLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges { bottomCorner.corner: RoundCorner.CornerEnum.BottomRight }
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
        function toggle(): void { GlobalStates.barOpen = !GlobalStates.barOpen }
        function close(): void { GlobalStates.barOpen = false }
        function open(): void { GlobalStates.barOpen = true }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"
        onPressed: { GlobalStates.barOpen = !GlobalStates.barOpen; }
    }
    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"
        onPressed: { GlobalStates.barOpen = true; }
    }
    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"
        onPressed: { GlobalStates.barOpen = false; }
    }
}
