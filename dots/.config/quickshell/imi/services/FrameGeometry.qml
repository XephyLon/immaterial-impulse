pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
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
    // What the compositor reserves for the bar - the settled exclusive zone
    // Bar.qml's reserver asks for, one token in Appearance for both. Known
    // stage-1 limits: the bar's per-screen list and auto-hide are not
    // modelled - one frame, the bar assumed present at its full zone on
    // every screen.
    readonly property real barThickness: Appearance.sizes.barExclusiveZone
    readonly property real thickness: Geo.bandThickness(Config.options.appearance.frame.thickness, Config.options.hyprland.general.gapsOut)
    // A pinned dock reserves its edge like the bar does; an unpinned or
    // disabled dock reserves nothing and the edge is a plain band edge.
    // A pinned dock reserves its edge like the bar does; an unpinned or
    // disabled dock reserves nothing and the edge is a plain band edge. The
    // zone is Appearance.sizes.dockExclusiveZone, the token Dock.qml's own
    // exclusiveZone reads. Dock.qml also drops its zone on a monitor with a
    // fullscreen window, which is why the per-screen readers below take a
    // `fullscreen` flag.
    readonly property bool dockReserves: (Config.options.dock.enable ?? false) && GlobalStates.dockPinned
    readonly property string dockEdge: root.dockReserves ? String(Config.options.dock.edge ?? "bottom") : ""
    readonly property real dockThickness: root.dockReserves ? Appearance.sizes.dockExclusiveZone : 0
    readonly property var insets: Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, root.dockEdge, root.dockThickness)
    // The window rounding the COMPOSITOR runs, asked once at start and again
    // on every config reload, so a hypr/custom override is honoured; the
    // shell's own option is the fallback until the answer arrives.
    property int liveRounding: -1
    readonly property real innerRadius: Geo.innerRadius(root.liveRounding >= 0 ? root.liveRounding : Config.options.hyprland.decoration.rounding)
    readonly property color color: Appearance.colors.colBarBackground

    Process {
        id: roundingProbe
        command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = Number(JSON.parse(text).int);
                    if (!isNaN(v)) root.liveRounding = v;
                } catch (e) {
                    // No answer (no Hyprland, an odd build): the option stays the source.
                }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") roundingProbe.running = true;
        }
    }

    // Per-screen readers: on a monitor with a fullscreen window the dock
    // reserves nothing (Dock.qml's own rule), so that edge is a band edge there.
    function insetsFor(fullscreen) {
        return fullscreen ? Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, "", 0) : root.insets;
    }
    function cornerMarginsFor(corner, fullscreen) { return Geo.cornerMargins(corner, root.insetsFor(fullscreen)); }
    function bandOffsetFor(edge, fullscreen) {
        return Geo.bandOffset(edge, root.barEdge, root.barThickness, fullscreen ? "" : root.dockEdge, fullscreen ? 0 : root.dockThickness);
    }

    function cornerMargins(corner) { return root.cornerMarginsFor(corner, false); }
    function bandOffset(edge) { return root.bandOffsetFor(edge, false); }
}
