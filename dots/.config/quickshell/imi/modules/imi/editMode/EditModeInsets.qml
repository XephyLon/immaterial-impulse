pragma Singleton

import Quickshell
import qs.modules.common
import "../dock/dock_geometry.js" as DockGeometry

/**
 * What Edit Mode may not draw on: the edges the bar and the dock occupy.
 *
 * The mode leaves both where they are and at full size - editing them in place
 * is stage 8 and this is not it - so the desktop shrinks inside what is left,
 * and the toolbar and the tab bar sit in bands opened inside that. Stage 4
 * shipped without this and put the toolbar on top of the bar's widgets and the
 * tab bar on top of the dock's.
 *
 * ---- why this is one singleton rather than two derivations -----------------
 *
 * `EditModeChromeSurface` re-derives the viewport rather than having it
 * published, on the grounds that every input is available on both sides. That
 * reasoning still holds for the geometry and stops holding here: these numbers
 * come from `Config.options.bar.*`, `Config.options.dock.*` and
 * `dock_geometry.js`, and a second file reading them is a second answer to
 * "where is the dock" - which is exactly what `test_dock_position_contract.py`
 * exists to prevent for the dock's own tree. So the two surfaces read one
 * object, and it lives beside the mode that is its only caller.
 *
 * ---- what is reserved, and what deliberately is not ------------------------
 *
 * The bar's and the dock's LAYER SURFACES, whole. Not their painted bodies: the
 * bar's surface carries the screen-corner decorators below its body, the dock's
 * carries its elevation margin, and both take clicks there. The surface extent
 * is also the number the compositor reports, so `hyprctl layers` is a check on
 * this rather than an unrelated measurement.
 *
 * The reservation is a function of CONFIGURATION only - never of auto-hide,
 * hover reveal, `GlobalStates.barOpen`, or a fullscreen window dropping the
 * dock's exclusive zone. Those all move while the mode is on, and a viewport
 * that changes size mid-edit rescales every widget under the cursor and hands
 * every `Behavior` carrying the box a moving target (b710ef731). It is the same
 * decision `edit_mode.js` makes about the drawer's width, for the same reason:
 * reserve the space whether or not the thing is currently in it.
 */
Singleton {
    id: root

    // Exactly one bar exists - `ImmaterialImpulseFamily.qml` loads Bar or
    // VerticalBar on `Config.options.bar.vertical` - so this is which edge it
    // is on, not which of two. Through `DockGeometry.barEdge` rather than
    // spelled out, because that overloaded pair (`bar.bottom` means "right"
    // when the bar is vertical) already has one place it becomes an edge name,
    // and `test_dock_position_contract.py` caught this file re-deriving it.
    readonly property bool barVertical: Config.options?.bar.vertical ?? false
    readonly property string barSide: DockGeometry.barEdge(
        root.barVertical, Config.options?.bar.bottom ?? false)
    readonly property real barThickness: root.barVertical
        ? Appearance.sizes.verticalBarSurfaceWidth
        : Appearance.sizes.barSurfaceThickness

    // The dock's outward side IS its edge, so this is `normalizedEdge` and not
    // `outwardSide` reading it: a file may take the stored key only straight
    // into that call, which is the same one-derivation rule.
    readonly property string dockSide: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")
    readonly property real dockThickness: (Config.options?.dock.enable ?? false)
        ? DockGeometry.thickness(Config.options?.dock.height ?? 60,
            Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)
        : 0

    // A screen the bar is not drawn on gets none of its inset. The dock has no
    // such list - `Dock.qml` runs over every screen - so nothing here does
    // either, rather than inventing a second rule for it.
    function barShownOn(screenName) {
        const list = Config.options?.bar.screenList;
        return !list || list.length === 0 || list.indexOf(screenName) !== -1;
    }

    // The two panels can share an edge (a bottom bar over a bottom dock), so
    // the terms add rather than the larger winning.
    function insetsFor(screenName) {
        const insets = { top: 0, bottom: 0, left: 0, right: 0 };
        if (root.barShownOn(screenName))
            insets[root.barSide] += root.barThickness;
        insets[root.dockSide] += root.dockThickness;
        return insets;
    }
}
