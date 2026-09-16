pragma Singleton

import Quickshell
import qs.services
import qs.modules.common
import "dock_geometry.js" as DockGeometry

/**
 * What a pinned dock asks of the compositor on its edge, from the dock's own
 * derivation (dock_geometry.js): the zone it reserves - the ONE value
 * Dock.qml's exclusiveZone reads - and, in frame mode, how far the whole
 * surface moves in from the screen edge to meet the frame's band
 * (services/FrameGeometry.qml): on it as a tab when attached, a gap above it
 * when floating. The compositor adds that margin to the zone by itself. It
 * lives here, on the dock's side, rather than as an Appearance token: the
 * design-token singleton is the layer everything builds on and should know
 * no feature.
 */
Singleton {
    readonly property real zone: DockGeometry.exclusiveZone(
        Config.options?.dock.height ?? 60,
        Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)
    readonly property bool attached: FrameGeometry.enabled && FrameGeometry.dockAttached
    readonly property real frameOffset: DockGeometry.frameOffset(
        FrameGeometry.enabled, FrameGeometry.dockAttached,
        FrameGeometry.thickness, Appearance.sizes.hyprlandGapsOut)
}
