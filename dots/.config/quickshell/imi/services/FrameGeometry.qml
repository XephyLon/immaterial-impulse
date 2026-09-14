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
    readonly property real barThickness: Appearance.sizes.barHeight
    readonly property real thickness: Geo.bandThickness(Config.options.appearance.frame.thickness, Config.options.hyprland.general.gapsOut)
    readonly property var insets: Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness)
    readonly property real innerRadius: Appearance.rounding.screenRounding
    readonly property color color: Appearance.colors.colBarBackground

    function cornerMargins(corner) { return Geo.cornerMargins(corner, root.insets); }
}
