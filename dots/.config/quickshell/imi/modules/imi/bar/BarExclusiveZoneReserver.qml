import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common

// The bar's exclusive zone, moved onto a surface that has nothing else to lose.
//
// A layer surface's exclusive zone is a protocol value on the surface itself,
// not a property of anything drawn in it: every write is a
// set_exclusive_zone + commit and a compositor-wide re-arrange of the windows
// behind it. The visible bar slides in and out of auto-hide on a margin
// Behavior over `elementMoveFast`, while its zone snapped between two integers
// - so the bar glided and the windows behind it jumped, in opposite directions
// at the two ends of one gesture. Animating the zone on the bar's own window
// would reconfigure the surface the bar is being drawn on, once per frame, for
// the whole slide.
//
// This window is that animation's home: one pixel thick, masked to nothing,
// painting nothing, so a per-frame reconfigure costs a re-arrange and no
// repaint. Both bars use it - the two must not each decide what their exclusive
// zone does, for the same reason `bar_widget_source.js` exists.
PanelWindow {
    id: reserver

    // What the bar's body occupies when it is out, before the margin the
    // compositor adds on top of it. 0 means "reserve nothing".
    property real zone: 0
    // The margin the visible bar holds off the screen edge with. Hyprland adds
    // an anchored-edge margin to a live exclusive zone - measured on this
    // machine, the bar's 40px zone under its 5px top margin reserves 45 - so
    // the fold is what keeps the reserved area the number it has always been.
    // It is folded into the ANIMATED value rather than into this surface's own
    // margins because a margin does not animate: the last frame of a hide would
    // be a jump from `edgeMargin` to 0.
    property real edgeMargin: 0
    // The bar's edge, as the two facts each bar already holds: `vertical` picks
    // the axis and `farEdge` is that bar's `Config.options.bar.bottom`.
    property bool vertical: false
    property bool farEdge: false
    // The visible bar's own namespace, deliberately reused rather than minted.
    // A new one falls through the catch-all `ignore_alpha = 0.05` in
    // rules.lua and asks the compositor to blur behind a surface that paints
    // nothing; both bars' namespaces already carry `blur = false`, so this
    // needs no rules.lua entry at all - which is the half that would otherwise
    // ship silently broken on any machine whose Hyprland config is older than
    // this commit.
    required property string barNamespace

    WlrLayershell.namespace: reserver.barNamespace
    // Never Overlay: an Overlay surface holds the compositor's fullscreen fast
    // path shut whatever its size. It also does not follow the bar's
    // fullscreen+special promotion, because that promotion exists to stop the
    // bar's pixels being buried and this window has none - the reserved area is
    // the same on every layer.
    WlrLayershell.layer: WlrLayer.Top

    // Three anchors, the odd one out being the edge the bar is on - that is
    // what tells the compositor which edge the zone is measured from.
    anchors {
        top: reserver.vertical ? true : !reserver.farEdge
        bottom: reserver.vertical ? true : reserver.farEdge
        left: reserver.vertical ? !reserver.farEdge : true
        right: reserver.vertical ? reserver.farEdge : true
    }
    implicitWidth: 1
    implicitHeight: 1

    // Writing `exclusiveZone` at all forces `exclusionMode` to Normal
    // (`WlrLayershell::setExclusiveZone`), so this is what the window is in
    // either way - stated rather than left to that side effect.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Math.round(reserver.animatedZone)

    readonly property real settledZone: reserver.zone > 0 ? reserver.zone + reserver.edgeMargin : 0
    property real animatedZone: reserver.settledZone
    // The same tier the bar's own slide takes, so the compositor's reflow rides
    // the curve the picture does.
    Behavior on animatedZone {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(reserver)
    }

    color: "transparent"
    // An empty mask is what makes a mapped, permanently-present surface
    // harmless: Quickshell sets Qt::WindowTransparentForInput for a mask that
    // resolves to nothing, so this window cannot take a click the bar or the
    // desktop under it should have had.
    mask: Region {}
}
