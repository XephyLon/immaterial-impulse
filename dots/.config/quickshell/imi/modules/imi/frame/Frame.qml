import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The frame's three bands (frame mode, stage 1): the two side edges and the
 * edge opposite the bar, drawn in the bar's colour so bar, bands and the
 * ScreenCorners fillets read as one connected surface. Input passes
 * through (an empty mask); nothing is reserved - the band lives in the
 * outer gap windows already leave. Hidden with the bar's rules for a
 * fullscreen window.
 */
Scope {
    id: frame

    component Band: PanelWindow {
        id: band
        required property string edge // "left" | "right" | "top" | "bottom"
        property bool fullscreen: false
        visible: FrameGeometry.enabled && !fullscreen && FrameGeometry.thickness > 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:frame"
        WlrLayershell.layer: WlrLayer.Top
        color: FrameGeometry.color
        mask: Region {}
        anchors {
            left: band.edge !== "right"
            right: band.edge !== "left"
            top: band.edge !== "bottom"
            bottom: band.edge !== "top"
        }
        implicitWidth: (band.edge === "left" || band.edge === "right") ? FrameGeometry.thickness : 0
        implicitHeight: (band.edge === "top" || band.edge === "bottom") ? FrameGeometry.thickness : 0
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            property bool fullscreen: HyprlandData.fullscreenByMonitorName[screenScope.monitor?.name ?? ""] ?? false
            property var thisMonitorData: HyprlandData.monitors.find(m => m.name === monitor?.name)
            property bool specialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""
            readonly property bool hidden: fullscreen && !specialOpen

            Band { screen: screenScope.modelData; edge: "left"; fullscreen: screenScope.hidden }
            Band { screen: screenScope.modelData; edge: "right"; fullscreen: screenScope.hidden }
            Band { screen: screenScope.modelData; edge: FrameGeometry.barEdge === "top" ? "bottom" : "top"; fullscreen: screenScope.hidden }
        }
    }
}
