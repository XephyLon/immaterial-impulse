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
 * plate; every other edge, the dock's included, is the band alone - a
 * pinned dock meets it on its own terms (Dock.qml: on it as a tab, or a
 * gap above it). Input passes through (an empty
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
        // Bottom, not Top: the band lives in the gap under everything that
        // is not wallpaper. On Top it stacked by creation order against the
        // dock (a later-built frame covered the pill on the dock's strip)
        // and over a floating window's edge; on Bottom the dock, the bar
        // and every window are above it and the wallpaper is under it.
        WlrLayershell.layer: WlrLayer.Bottom
        color: band.painted ? FrameGeometry.color : "transparent"
        mask: Region {}
        anchors {
            left: band.edge !== "right"
            right: band.edge !== "left"
            top: band.edge !== "bottom"
            bottom: band.edge !== "top"
        }
        // Under the bar's plate on the bar's edge, at the screen edge
        // elsewhere; the horizontal bands span the width and the side bands
        // run between them, so no two bands overlap (the colour is
        // translucent: a crossing was painted twice).
        readonly property var bandMargins: FrameGeometry.bandMargins(band.edge)
        margins {
            top: band.bandMargins.top
            bottom: band.bandMargins.bottom
            left: band.bandMargins.left
            right: band.bandMargins.right
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
            }
            Band {
                screen: screenScope.modelData
                edge: "right"
                hidden: screenScope.hidden
            }
            Band {
                screen: screenScope.modelData
                edge: "top"
                hidden: screenScope.hidden
            }
            Band {
                screen: screenScope.modelData
                edge: "bottom"
                hidden: screenScope.hidden
            }
        }
    }
}
