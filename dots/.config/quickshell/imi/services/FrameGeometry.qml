pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.modules.common
import qs.modules.imi.dock
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
    // disabled dock reserves nothing and the edge is a plain band edge. The
    // zone is DockReservation.zone, the value Dock.qml's own exclusiveZone
    // reads. Dock.qml also drops its zone on a monitor with a fullscreen
    // window (WM.fullscreenOnMonitor), which is why the per-screen readers
    // below ask the same predicate by screen name.
    readonly property bool dockReserves: (Config.options.dock.enable ?? false) && GlobalStates.dockPinned
    readonly property string dockEdge: root.dockReserves ? String(Config.options.dock.edge ?? "bottom") : ""
    readonly property real dockThickness: root.dockReserves ? DockReservation.zone : 0
    readonly property var insets: Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, root.dockEdge, root.dockThickness)
    // The window rounding the COMPOSITOR runs, asked when frame mode is on
    // (at start, when it is switched on, and on every config reload while
    // on), so a hypr/custom override is honoured; the shell's own option is
    // the fallback until the answer arrives. Nothing is spawned while the
    // mode is off.
    property int liveRounding: -1
    readonly property real innerRadius: Geo.innerRadius(root.liveRounding >= 0 ? root.liveRounding : Config.options.hyprland.decoration.rounding)
    readonly property color color: Appearance.colors.colBarBackground

    // Re-armed by dropping and raising a companion flag, never by writing
    // `running` (an imperative write over a binding destroys it: the switch
    // that "detached from the config and then lied about it").
    property bool probeArmed: true
    Process {
        id: roundingProbe
        command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
        running: root.enabled && root.probeArmed
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
            if (event.name !== "configreloaded" || !root.enabled) return;
            root.probeArmed = false;
            root.probeArmed = true;
        }
    }

    // Per-screen readers, by screen name: on a monitor with a fullscreen
    // window the dock reserves nothing, and the predicate is the one Dock.qml
    // itself uses (WM.fullscreenOnMonitor) - owned here, never handed in by
    // a caller, so the bands and the fillets cannot be given two answers.
    // Memoised once per change of its inputs: WM.fullscreenOnMonitor scans
    // the workspaces' toplevels, and eight bindings per screen (four bands,
    // four fillets) would each re-run that scan on every Hyprland event.
    readonly property var dockReservesByScreen: {
        const map = {};
        for (const screen of Quickshell.screens)
            map[screen.name] = root.dockReserves && !WM.fullscreenOnMonitor(screen.name);
        return map;
    }
    function dockReservesOn(screenName) {
        return root.dockReservesByScreen[screenName] ?? false;
    }
    function insetsForScreen(screenName) {
        return root.dockReservesOn(screenName) ? root.insets : Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, "", 0);
    }
    function cornerMarginsForScreen(corner, screenName) {
        return Geo.cornerMargins(corner, root.insetsForScreen(screenName));
    }
    function bandExtentForScreen(edge, screenName) {
        const reserves = root.dockReservesOn(screenName);
        return Geo.bandExtent(edge, root.thickness, reserves ? root.dockEdge : "", reserves ? root.dockThickness : 0);
    }
    function bandMarginsForScreen(edge, screenName) {
        const reserves = root.dockReservesOn(screenName);
        return Geo.bandMargins(edge, root.barEdge, root.barThickness, reserves ? root.dockEdge : "", reserves ? root.dockThickness : 0);
    }
}
