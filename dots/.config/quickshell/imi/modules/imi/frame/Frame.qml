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
 * plate, and under a pinned dock on its edge (the compositor reserves each
 * occupant's zone and then its outer gap). Input passes through (an empty
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
        readonly property bool painted: !band.hidden && FrameGeometry.thickness > 0
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
        // The band on an occupied edge starts where that edge's zone(s) end;
        // `fullscreen` is this screen's, because the dock drops its zone on a
        // fullscreen monitor.
        property bool fullscreen: false
        margins {
            top: band.edge === "top" ? FrameGeometry.bandOffsetFor("top", band.fullscreen) : 0
            bottom: band.edge === "bottom" ? FrameGeometry.bandOffsetFor("bottom", band.fullscreen) : 0
            left: band.edge === "left" ? FrameGeometry.bandOffsetFor("left", band.fullscreen) : 0
            right: band.edge === "right" ? FrameGeometry.bandOffsetFor("right", band.fullscreen) : 0
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

            Band {
                screen: screenScope.modelData
                edge: "left"
                hidden: screenScope.hidden
                fullscreen: screenScope.fullscreen
            }
            Band {
                screen: screenScope.modelData
                edge: "right"
                hidden: screenScope.hidden
                fullscreen: screenScope.fullscreen
            }
            Band {
                screen: screenScope.modelData
                edge: "top"
                hidden: screenScope.hidden
                fullscreen: screenScope.fullscreen
            }
            Band {
                screen: screenScope.modelData
                edge: "bottom"
                hidden: screenScope.hidden
                fullscreen: screenScope.fullscreen
            }
        }
    }
}
