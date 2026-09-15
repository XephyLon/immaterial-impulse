pragma Singleton

import Quickshell
import qs.modules.common
import "dock_geometry.js" as DockGeometry

/**
 * What a pinned dock asks the compositor to reserve on its edge - the ONE
 * value Dock.qml's exclusiveZone and frame mode's geometry authority both
 * read, from the dock's own derivation (dock_geometry.js). It lives here,
 * on the dock's side, rather than as an Appearance token: the design-token
 * singleton is the layer everything builds on and should know no feature.
 */
Singleton {
    readonly property real zone: DockGeometry.exclusiveZone(
        Config.options?.dock.height ?? 60,
        Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)
}
