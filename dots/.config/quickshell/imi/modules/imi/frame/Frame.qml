import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The frame's four bands (frame mode, stage 1), one per screen edge, drawn
 * in the bar's colour so bar, bands and the ScreenCorners fillets read as
 * one connected surface. The band on the bar's edge sits under the bar
 * plate (the compositor reserves the bar's zone and then its outer gap);
 * an edge the dock owns gets no band. Input passes through (an empty
 * mask); nothing is reserved - the band lives in the outer gap windows
 * already leave. Painted transparent, never unmapped, for a fullscreen
 * window.
 */
Scope {
    id: frame

    component Band: PanelWindow {
        id: band
        required property string edge // "left" | "right" | "top" | "bottom"
        property bool hidden: false
        // Mapped for as long as frame mode is on: `visible` on a layer
        // surface destroys and recreates it, so a fullscreen window or a
        // thickness of 0 paints the band transparent instead. The surface
        // reserves nothing and takes no input, so a transparent band costs
        // nothing (namespace rule in hypr/hyprland/rules.lua: no_anim).
        readonly property bool painted: !band.hidden && FrameGeometry.thickness > 0 && FrameGeometry.edgeHasBand(band.edge)
        visible: FrameGeometry.enabled
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:frame"
        WlrLayershell.layer: WlrLayer.Top
        color: band.painted ? FrameGeometry.color : "transparent"
        mask: Region {}
        anchors {
            left: band.edge !== "right"
            right: band.edge !== "left"
            top: band.edge !== "bottom"
            bottom: band.edge !== "top"
        }
        // The band on the bar's edge starts where the bar's zone ends.
        margins {
            top: band.edge === "top" ? FrameGeometry.bandOffset("top") : 0
            bottom: band.edge === "bottom" ? FrameGeometry.bandOffset("bottom") : 0
        }
        implicitWidth: (band.edge === "left" || band.edge === "right") ? Math.max(1, FrameGeometry.thickness) : 0
        implicitHeight: (band.edge === "top" || band.edge === "bottom") ? Math.max(1, FrameGeometry.thickness) : 0
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            property bool fullscreen: HyprlandData.fullscreenByMonitorName[screenScope.monitor?.name ?? ""] ?? false
            property bool specialOpen: HyprlandData.specialWorkspaceByMonitorName[screenScope.monitor?.name ?? ""] ?? false
            readonly property bool hidden: fullscreen && !specialOpen

            Band { screen: screenScope.modelData; edge: "left"; hidden: screenScope.hidden }
            Band { screen: screenScope.modelData; edge: "right"; hidden: screenScope.hidden }
            Band { screen: screenScope.modelData; edge: "top"; hidden: screenScope.hidden }
            Band { screen: screenScope.modelData; edge: "bottom"; hidden: screenScope.hidden }
        }
    }
}
