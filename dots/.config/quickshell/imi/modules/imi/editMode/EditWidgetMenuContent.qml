import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins
import "../../common/functions/edit_mode.js" as EditMode
import "../../common/plugins/gridSizes.js" as GridSizes

/**
 * The per-widget context menu's card: Remove, Pin, and the Size stepper
 * (spec §4.1's in-mode right-click, §5's resize rule, §9's boundary).
 *
 * ---- what each row is allowed to be ----------------------------------------
 *
 * Everything here is placement, span, or presence - the three things spec §9
 * lets the mode write, and `lint_edit_mode_scope.py` polices this file like the
 * rest of the directory:
 *
 * - **Pin** is `positionLocked`, one of §9's two deliberate edge cases: a
 *   "Widget behaviour" toggle that is *about* placement. It writes through the
 *   one existing writer - `PluginState.setOption(id, "positionLocked", ...)` -
 *   exactly as the settings page's toggle bar does: one writer, two call
 *   sites, not two meanings. Its drawn state is a binding on the stored value
 *   (seeded the way PluginWidget seeds it, from the manifest), never local
 *   state, so a pin flipped from Settings while this menu is open moves the
 *   row - the ConfigSwitch intent lesson applied to a row that draws a check.
 *
 * - **Size** is a stepper OVER `offeredGridSizes` and nothing else: the two
 *   chevrons move an index through the spans the manifest offers, in the
 *   manifest's own order (which gridSizes.js documents as the resize order),
 *   and the write is the host's `__gridSize` - the same value the grip and the
 *   settings row commit. No pointer delta and no pixel ever comes near it,
 *   which is §5's rule: the host can only ever assign an offered span. A
 *   widget offering one span gets NO row (omitted, not disabled - the
 *   PluginOptions rule), and a widget that declined `grid` altogether
 *   (calendar, world-clock, custom-image) offers zero spans, so its own
 *   handles keep the size they chose and the host never overwrites it.
 *
 * - **Remove** is presence on the surface. `plugins.enabled` is one global
 *   list and the desktop renders it on every monitor, so removing here removes
 *   the widget everywhere - the same write the drawer's toggle and Settings >
 *   Widgets make, through the same `EditMode.enabledWithout` spelling. The
 *   removal destroys this menu's widget, whose Component.onDestruction then
 *   closes the menu (PluginWidget's vacate); `dismissRequested` is still
 *   raised so the window does not depend on that round trip.
 *
 * ---- why the writes live here ----------------------------------------------
 *
 * The drawer reports gestures and lets the chrome surface write, because its
 * writes need the surface's geometry (a drop point mapped into the canvas).
 * The menu's writes are id-keyed with no geometry in them, and this item is
 * what the runtime harness can build and click - a window no harness can
 * construct (weston implements no wlr-layer-shell) would put the writes where
 * no test reaches them. The scope lint polices the whole directory either way.
 */
Item {
    id: root

    // The manifest, not an id: the card knows nothing about the catalogue,
    // and whoever opens it resolves the id against `PluginManager` (the menu
    // window) or hands in its own (the runtime harness, whose manifests are
    // synthetic and exist in no catalogue).
    property var manifest: null
    signal dismissRequested()

    readonly property var offeredSizes: GridSizes.offeredSizes(root.manifest?.grid ?? null)
    // The stored choice, read once so every derivation below shares one
    // reactive dependency on the plugin-state store.
    readonly property var storedSpan: root.manifest
        ? PluginState.option(root.manifest.id, "__gridSize") : undefined
    // Stored choice -> manifest default, resolved the way the host resolves
    // it, so the value the stepper starts from is the span the widget is
    // actually drawn at - including when the stored span is one the manifest
    // no longer offers and resolveSize has fallen back.
    readonly property var currentSize: GridSizes.resolveSize(root.manifest?.grid ?? null,
        root.storedSpan)
    // The two neighbours, from the module (tst_grid_sizes.qml owns the walk):
    // null means "nowhere to step", which is exactly what the chevron's
    // enabled reads.
    readonly property var stepBack: GridSizes.steppedSize(root.manifest?.grid ?? null,
        root.storedSpan, -1)
    readonly property var stepForward: GridSizes.steppedSize(root.manifest?.grid ?? null,
        root.storedSpan, 1)

    // The same seed PluginWidget's own binding reads, or the row would
    // disagree with the widget for a manifest that ships `locked: true`.
    readonly property bool pinned: root.manifest
        ? PluginState.option(root.manifest.id, "positionLocked",
            root.manifest.desktopWidget?.locked === true)
        : false

    // A step moves along the offered order, never a pixel: the write is
    // whatever GridSizes.steppedSize answers, formatted the way the grip and
    // the settings row format it. A null answer - off either end, or nothing
    // to step - writes nothing, so a click racing the store cannot walk off
    // the list. The menu stays open: stepping several spans and watching the
    // widget morph between them is what a stepper is for.
    function stepSize(direction) {
        if (!root.manifest) return;
        const next = GridSizes.steppedSize(root.manifest.grid ?? null,
            root.storedSpan, direction);
        if (!next) return;
        // A span commit is one of §7.3's committed mutations. The closure
        // captures the id and the old stored choice, and reaches only the
        // PluginState singleton - never this card or its widget, both of
        // which the mode can destroy while the stack outlives them.
        const id = root.manifest.id;
        const before = PluginState.option(id, "__gridSize", null);
        GlobalStates.editUndoPush(() => PluginState.setOption(id, "__gridSize", before));
        PluginState.setOption(id, "__gridSize",
            GridSizes.formatSize(next));
    }

    implicitWidth: 260
    implicitHeight: rows.implicitHeight

    GroupedList {
        id: rows
        width: parent.width
        itemVerticalPadding: Appearance.spacing.space200
        bgcolor: Appearance.colors.colLayer0

        // The widget's name, so the menu says which widget it is about - the
        // pointer is on the widget, the menu may be clamped away from it.
        Item {
            implicitHeight: 40
            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Appearance.spacing.space150
                    rightMargin: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space150
                MaterialSymbol {
                    text: "widgets"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.manifest?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }
        }

        RippleButton {
            id: pinRow
            objectName: "editMenuPin"
            implicitHeight: 40
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2
            // The intent shape: the click flips the value at its source (the
            // same read the `pinned` binding makes), and the check beside the
            // label follows the store - never a local flag the write could
            // detach from.
            onClicked: {
                if (!root.manifest) return;
                PluginState.setOption(root.manifest.id, "positionLocked", !root.pinned);
            }
            contentItem: RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Appearance.spacing.space150
                    rightMargin: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space150
                MaterialSymbol {
                    text: "push_pin"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Pin position")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
                MaterialSymbol {
                    visible: root.pinned
                    text: "check"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // The stepper. `rowVisible`, never `visible`: a GroupedList row hidden
        // the second way keeps its plate (see GroupedList.qml).
        Item {
            id: sizeRow
            property bool rowVisible: root.offeredSizes.length > 1
            implicitHeight: 40
            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Appearance.spacing.space150
                    rightMargin: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space150
                MaterialSymbol {
                    text: "aspect_ratio"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Size")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
                RippleButton {
                    id: sizeDownButton
                    objectName: "editMenuSizeDown"
                    implicitWidth: 32
                    implicitHeight: 32
                    enabled: root.stepBack !== null
                    onClicked: root.stepSize(-1)
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
                StyledText {
                    text: root.currentSize
                        ? `${root.currentSize.cols} × ${root.currentSize.rows}` : ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
                RippleButton {
                    id: sizeUpButton
                    objectName: "editMenuSizeUp"
                    implicitWidth: 32
                    implicitHeight: 32
                    enabled: root.stepForward !== null
                    onClicked: root.stepSize(1)
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        RippleButton {
            id: removeRow
            objectName: "editMenuRemove"
            implicitHeight: 40
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2
            // Presence: the same write the drawer's toggle and Settings >
            // Widgets make, through the one spelling. The dismiss is raised as
            // well as earned through the widget's own vacate, so the window
            // closes even where no widget instance exists to be destroyed.
            onClicked: {
                if (!root.manifest) return;
                // A remove is a committed mutation (§7.3): the closure holds
                // the whole enabled list from before the write, so undoing
                // re-enables the widget at the position the store still
                // holds for it.
                const before = EditMode.listCopy(Config.options.plugins.enabled);
                GlobalStates.editUndoPush(() =>
                    Config.setNestedValue("plugins.enabled", before));
                Config.setNestedValue("plugins.enabled",
                    EditMode.enabledWithout(Config.options.plugins.enabled, root.manifest.id));
                root.dismissRequested();
            }
            contentItem: RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Appearance.spacing.space150
                    rightMargin: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space150
                MaterialSymbol {
                    text: "delete"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Remove from desktop")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
