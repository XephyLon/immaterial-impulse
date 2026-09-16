pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import "frame_geometry.js" as Geo

/**
 * Frame mode's geometry authority (docs/proposals/frame-mode.md): the shell's
 * edge surfaces read where the frame is from here instead of each deciding
 * for itself. Stage 1: one frame for every screen, the bar's edge is the
 * bar, the other three edges are a band as thick as the compositor's outer
 * gap (or `appearance.frame.thickness`), and the four inner corners carry
 * the screen-rounding fillet in the frame's colour. The dock is not part of
 * the frame: a pinned dock meets the band on its own edge - sitting on it as
 * a tab (`appearance.frame.dock` "attached") or a gap above it ("floating")
 * - and reads `dockAttached` and `thickness` from here to do so
 * (modules/imi/dock/DockReservation.qml). Off by default; a vertical bar is
 * not framed yet.
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
    // How a pinned dock meets the band on its edge: on it (a tab, the
    // default) or floating a gap above it. Anything but "floating" is
    // attached, so a hand-edited value cannot leave the dock nowhere.
    readonly property bool dockAttached: String(Config.options.appearance.frame.dock ?? "attached") !== "floating"
    readonly property var insets: Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness)
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

    // The readers. One frame for every screen, so neither takes a screen:
    // an earlier cut framed a pinned dock per screen (its zone drops on a
    // fullscreen monitor) and the per-screen plumbing went with the dock.
    function cornerMargins(corner) {
        return Geo.cornerMargins(corner, root.insets);
    }
    function bandMargins(edge) {
        return Geo.bandMargins(edge, root.barEdge, root.barThickness, root.thickness);
    }
}
