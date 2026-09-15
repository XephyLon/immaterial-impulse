import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: screenCorners
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    property var actionForCorner: ({
        [RoundCorner.CornerEnum.TopLeft]: () => GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen,
        [RoundCorner.CornerEnum.BottomLeft]: () => GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen,
        [RoundCorner.CornerEnum.TopRight]: () => GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen,
        [RoundCorner.CornerEnum.BottomRight]: () => GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
    })

    component CornerPanelWindow: PanelWindow {
        id: cornerPanelWindow
        property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
        property bool fullscreen
        // Frame mode needs its four inner fillets whatever the fake-rounding
        // setting says; outside it the setting rules as before.
        visible: FrameGeometry.enabled ? !fullscreen
            : (Config.options.appearance.fakeScreenRounding === 1 || (Config.options.appearance.fakeScreenRounding === 2 && !fullscreen))
        property var corner
        // Where this fillet sits in frame mode: at the inner corner, where
        // the bar (or band) meets the side band. FrameGeometry owns the
        // arithmetic AND the per-screen fullscreen rule; nothing here
        // computes an inset or decides whether the dock reserves.
        readonly property var frameMargins: FrameGeometry.enabled
            ? FrameGeometry.cornerMarginsForScreen(cornerWidget.isTopLeft ? "topLeft" : cornerWidget.isTopRight ? "topRight" : cornerWidget.isBottomLeft ? "bottomLeft" : "bottomRight", cornerPanelWindow.screen?.name ?? "")
            : ({ left: 0, top: 0, right: 0, bottom: 0 })

        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            item: sidebarCornerOpenInteractionLoader.active ? sidebarCornerOpenInteractionLoader : null
        }
        WlrLayershell.namespace: "quickshell:screenCorners"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"

        anchors {
            top: cornerWidget.isTopLeft || cornerWidget.isTopRight
            left: cornerWidget.isBottomLeft || cornerWidget.isTopLeft
            bottom: cornerWidget.isBottomLeft || cornerWidget.isBottomRight
            right: cornerWidget.isTopRight || cornerWidget.isBottomRight
        }
        margins {
            right: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * -1
            bottom: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * -1
        }

        // The window stays at the screen corner (the sidebar corner-open hit
        // rect lives at the true corner); in frame mode the fillet SHAPE
        // moves inward by the frame's margins, and the window grows to hold it.
        implicitWidth: cornerWidget.implicitWidth + cornerPanelWindow.frameMargins.left + cornerPanelWindow.frameMargins.right
        implicitHeight: cornerWidget.implicitHeight + cornerPanelWindow.frameMargins.top + cornerPanelWindow.frameMargins.bottom

        RoundCorner {
            id: cornerWidget
            anchors.fill: parent
            corner: cornerPanelWindow.corner
            // The frame's colour joins the fillet to the bar and the bands;
            // the fake screen rounding stays black.
            color: FrameGeometry.enabled ? FrameGeometry.color : "#000000"
            leftVisualMargin: cornerPanelWindow.frameMargins.left
            topVisualMargin: cornerPanelWindow.frameMargins.top
            rightVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * 1 + cornerPanelWindow.frameMargins.right
            bottomVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * 1 + cornerPanelWindow.frameMargins.bottom

            // In frame mode the fillet is concentric with the window corner it
            // wraps (the authority's radius); otherwise the screen rounding.
            implicitSize: FrameGeometry.enabled ? Math.round(FrameGeometry.innerRadius) : Appearance.rounding.screenRounding
            implicitHeight: Math.max(implicitSize, sidebarCornerOpenInteractionLoader.implicitHeight)
            implicitWidth: Math.max(implicitSize, sidebarCornerOpenInteractionLoader.implicitWidth)

            Loader {
                id: sidebarCornerOpenInteractionLoader
                active: {
                    if (!Config.options.sidebar.cornerOpen.enable) return false;
                    if (cornerPanelWindow.fullscreen) return false;
                    return (Config.options.sidebar.cornerOpen.bottom == cornerWidget.isBottom);
                }
                anchors {
                    top: (cornerWidget.isTopLeft || cornerWidget.isTopRight) ? parent.top : undefined
                    bottom: (cornerWidget.isBottomLeft || cornerWidget.isBottomRight) ? parent.bottom : undefined
                    left: (cornerWidget.isLeft) ? parent.left : undefined
                    right: (cornerWidget.isTopRight || cornerWidget.isBottomRight) ? parent.right : undefined
                }

                sourceComponent: FocusedScrollMouseArea {
                    id: mouseArea
                    implicitWidth: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    implicitHeight: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    hoverEnabled: true
                    onPositionChanged: {
                        // "Force hover at absolute corner" is a sub-option of
                        // "Hover to trigger" (the settings row is disabled when
                        // clickless is off). Gate on clickless too, otherwise the
                        // corner-end hover still opens the sidebar after the user
                        // turns hover-to-trigger off. See issue #50.
                        if (!Config.options.sidebar.cornerOpen.clickless) return;
                        if (!Config.options.sidebar.cornerOpen.clicklessCornerEnd) return;
                        const verticalOffset = Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset;
                        const correctX = (cornerWidget.isRight && mouseArea.mouseX >= mouseArea.width - 2) || (cornerWidget.isLeft && mouseArea.mouseX <= 2);
                        const correctY = (cornerWidget.isTop && mouseArea.mouseY > verticalOffset || cornerWidget.isBottom && mouseArea.mouseY < mouseArea.height - verticalOffset);
                        if (correctX && correctY)
                            screenCorners.actionForCorner[cornerPanelWindow.corner]();
                    }
                    onEntered: {
                        if (Config.options.sidebar.cornerOpen.clickless)
                            screenCorners.actionForCorner[cornerPanelWindow.corner]();
                    }
                    onPressed: {
                        screenCorners.actionForCorner[cornerPanelWindow.corner]();
                    }
                    onScrollDown: {
                        if (!Config.options.sidebar.cornerOpen.valueScroll)
                            return;
                        if (cornerWidget.isLeft)
                            Brightness.decreaseBrightness()
                        else {
                            const currentVolume = Audio.value;
                            const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
                            Audio.sink.audio.volume -= step;
                        }
                    }
                    onScrollUp: {
                        if (!Config.options.sidebar.cornerOpen.valueScroll)
                            return;
                        if (cornerWidget.isLeft)
                            Brightness.increaseBrightness()
                        else {
                            const currentVolume = Audio.value;
                            const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
                            Audio.sink.audio.volume = Math.min(1, Audio.sink.audio.volume + step);
                        }
                    }
                    onMovedAway: {
                        if (!Config.options.sidebar.cornerOpen.valueScroll)
                            return;
                        if (cornerWidget.isLeft)
                            GlobalStates.osdBrightnessOpen = false;
                        else
                            GlobalStates.osdVolumeOpen = false;
                    }

                    Loader {
                        active: Config.options.sidebar.cornerOpen.visualize
                        anchors.fill: parent
                        sourceComponent: Rectangle {
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: monitorScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

            // Hide when fullscreen - true fullscreen only, not maximized. See
            // HyprlandData.fullscreenByMonitorName for why that distinction needs
            // the polled data.
            property bool fullscreen: HyprlandData.fullscreenByMonitorName[monitorScope.monitor?.name ?? ""] ?? false
            // A special workspace open on top of the fullscreen window should bring corners back,
            // same reasoning as the bar's layer fix: fullscreen only buries them when nothing else is above it.
            property var thisMonitorData: HyprlandData.monitors.find(m => m.name === monitor.name)
            property bool specialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""

            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.TopLeft
                fullscreen: monitorScope.fullscreen && !monitorScope.specialOpen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.TopRight
                fullscreen: monitorScope.fullscreen && !monitorScope.specialOpen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.BottomLeft
                fullscreen: monitorScope.fullscreen && !monitorScope.specialOpen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.BottomRight
                fullscreen: monitorScope.fullscreen && !monitorScope.specialOpen
            }
        }
    }
}