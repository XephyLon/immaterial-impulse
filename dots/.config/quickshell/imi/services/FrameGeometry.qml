pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common
import "frame_geometry.js" as Geo

/**
 * Frame mode's geometry authority (docs/proposals/frame-mode.md): the shell's
 * edge surfaces read where the frame is from here instead of each deciding
 * for itself. Stage 1: one frame for every screen, the bar's edge is the
 * bar, the other three edges are a band as thick as the compositor's outer
 * gap (or `appearance.frame.thickness`), and the four inner corners carry
 * the screen-rounding fillet in the frame's colour. Off by default; a
 * vertical bar is not framed yet.
 */
Singleton {
    id: root
    readonly property bool enabled: (Config.options.appearance.frame.enable ?? false) && !Config.options.bar.vertical
    readonly property string barEdge: Config.options.bar.bottom ? "bottom" : "top"
    // What the compositor reserves for the bar (the zone the windows start
    // after), not what the bar paints. Known stage-1 limits: the bar's
    // per-screen list and auto-hide are not modelled - one frame, the bar
    // assumed present at its full zone on every screen.
    readonly property real barThickness: Appearance.sizes.baseBarHeight
        + ((Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 4) ? Appearance.sizes.hyprlandGapsOut : 0)
    readonly property real thickness: Geo.bandThickness(Config.options.appearance.frame.thickness, Config.options.hyprland.general.gapsOut)
    // The dock's edge is left to the dock (see frame_geometry.js).
    readonly property string dockEdge: (Config.options.dock.enable ?? false) ? String(Config.options.dock.edge ?? "bottom") : ""
    readonly property var insets: Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, root.dockEdge)
    readonly property real innerRadius: Geo.innerRadius(Config.options.hyprland.decoration.rounding, root.thickness)
    readonly property color color: Appearance.colors.colBarBackground

    function cornerMargins(corner) { return Geo.cornerMargins(corner, root.insets); }
    function bandOffset(edge) { return Geo.bandOffset(edge, root.barEdge, root.barThickness); }
    function edgeHasBand(edge) { return root.insets[edge] > 0; }
}
