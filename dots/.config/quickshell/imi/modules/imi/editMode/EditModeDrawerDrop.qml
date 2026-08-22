import QtQuick
import qs
import qs.modules.common
import "../../common/functions/edit_mode.js" as EditMode

/**
 * The other half of the drawer's drag: a desktop widget carried back INTO the
 * drawer and let go there leaves the desktop.
 *
 * ---- why the write is here and not on the widget ---------------------------
 *
 * The gesture is split across two layer surfaces and each half is where it can
 * be. The pointer, the widget and its identity are on `quickshell:background`,
 * so that is where the decision is made (`PluginWidget.releaseRemovesWidget`);
 * every store the mode writes is written under `modules/imi/editMode/`, which
 * is the directory `lint_edit_mode_scope.py` polices - a `plugins.enabled`
 * write moved one directory sideways is that lint's own worked example of how
 * the rule gets lost. So the drop is announced through `GlobalStates` and
 * answered here.
 *
 * It is not a method on `EditModeChromeSurface` for the reason
 * `EditWidgetMenuContent` gives for owning its own Remove: this write is
 * id-keyed with no geometry in it, and the surface is a `PanelWindow` no
 * harness can construct (weston implements no wlr-layer-shell), so putting it
 * there would put it where no test reaches it.
 *
 * ---- and why there is exactly one --------------------------------------------
 *
 * `plugins.enabled` is ONE global list drawn on every monitor - the reason the
 * menu's Remove removes everywhere - so a listener per chrome surface would
 * answer one drop once per screen and spend an undo entry on each. This is
 * declared once, beside the menu's window, in `EditModeChrome.qml`.
 */
QtObject {
    id: root

    // A `QtObject` has no default property, so a bare `Connections` beside it
    // fails with `Cannot assign to non-existent default property` and takes the
    // whole type down - the trap `StyledPopup` already records.
    readonly property Connections drops: Connections {
        target: GlobalStates
        function onEditWidgetDroppedOnDrawer(pluginId) {
            root.removeWidget(pluginId);
        }
    }

    // Presence, through the one spelling - the same write the menu's Remove and
    // the drawer's own toggle make, so the three cannot disagree about order or
    // duplicates. The undo closure holds the whole enabled list from before and
    // captures the Config singleton only, because the stack outlives every
    // widget, menu and surface the mode can destroy.
    //
    // Nothing here touches the widget's stored POSITION, and that is the point:
    // the drag deliberately committed none, so the store still says where the
    // widget was and re-enabling puts it back there rather than under the panel
    // it was dropped on.
    //
    // The membership guard is not decoration. A drop is one gesture and must be
    // one undo entry; an id that is not on the desktop would otherwise push a
    // closure that "restores" a list nothing changed, and Ctrl+Z would spend a
    // press doing nothing visible.
    function removeWidget(pluginId) {
        if (!GlobalStates.editMode || pluginId === "") return;
        if (!Config.options.plugins.enabled.includes(pluginId)) return;
        const before = EditMode.listCopy(Config.options.plugins.enabled);
        GlobalStates.editUndoPush(() =>
            Config.setNestedValue("plugins.enabled", before));
        Config.setNestedValue("plugins.enabled",
            EditMode.enabledWithout(Config.options.plugins.enabled, pluginId));
    }
}
