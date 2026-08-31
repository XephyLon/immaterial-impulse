import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/preset_groups.js" as PresetGroups
import QtQuick
import QtQuick.Layouts

/**
 * The selective-apply dialog (spec 2026-08-31). Opens with every ordinary
 * group preselected, so Enter-on-Apply stays a whole-preset apply - except
 * the commands row, which is the apps.* injection fence and never
 * preselects. Groups a preset does not hold render disabled rather than
 * vanishing, so a partial preset still shows the whole vocabulary.
 *
 * Driven entirely by Presets.pendingApplyName so the Profile page only has
 * to request the apply; the window-level host in SettingsContent binds
 * `show` and forwards dismissal, mirroring PluginInstallDialog.
 */
WindowDialog {
    id: root
    backgroundWidth: 400

    // Cached copy of the pending request: Presets clears it on
    // confirm/cancel, and the dialog must keep its content readable through
    // the close animation instead of blanking out.
    property string presetName: ""
    property var presetData: null

    readonly property string pending: Presets.pendingApplyName
    onPendingChanged: root.syncPending()
    Component.onCompleted: root.syncPending()

    readonly property var counts: PresetGroups.presentCounts(root.presetData ?? ({}))
    property var selected: ({})
    readonly property int selectedCount: PresetGroups.GROUPS
        .filter(g => root.selected[g.id] === true).length

    function syncPending() {
        if (Presets.pendingApplyName === "")
            return;
        root.presetName = Presets.pendingApplyName;
        root.presetData = Presets.pendingApplyData;
        const initial = {};
        for (const group of PresetGroups.GROUPS)
            initial[group.id] = group.defaultOn && (root.counts[group.id] ?? 0) > 0;
        root.selected = initial;
    }

    function toggle(id) {
        const next = Object.assign({}, root.selected);
        next[id] = !next[id];
        root.selected = next;
    }

    function confirm() {
        const ids = PresetGroups.GROUPS.map(g => g.id).filter(id => root.selected[id]);
        Presets.apply(root.presetName,
            PresetGroups.sectionsFor(root.presetData ?? ({}), ids));
        root.dismiss();
    }

    WindowDialogTitle {
        text: Translation.tr("Apply %1").arg(root.presetName)
    }

    Repeater {
        model: PresetGroups.GROUPS.filter(g => g.id !== "commands")
        delegate: ConfigSwitch {
            required property var modelData
            Layout.fillWidth: true
            buttonIcon: modelData.icon
            text: Translation.tr(modelData.label)
            enabled: (root.counts[modelData.id] ?? 0) > 0
            description: (root.counts[modelData.id] ?? 0) > 0
                ? Translation.tr("%1 sections").arg(root.counts[modelData.id])
                : Translation.tr("Not in this preset")
            checked: root.selected[modelData.id] === true
            onToggleRequested: root.toggle(modelData.id)
        }
    }

    WindowDialogSeparator {}

    // The fence. Never preselected, whatever the preset's origin.
    ConfigSwitch {
        Layout.fillWidth: true
        buttonIcon: "terminal"
        text: Translation.tr("App launch commands")
        enabled: (root.counts.commands ?? 0) > 0
        description: (root.counts.commands ?? 0) > 0
            ? Translation.tr("Runs shell commands from the preset — review before enabling")
            : Translation.tr("Not in this preset")
        checked: root.selected.commands === true
        onToggleRequested: root.toggle("commands")
    }

    WindowDialogButtonRow {
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }
        DialogButton {
            buttonText: Translation.tr("Apply")
            enabled: root.selectedCount > 0
            onClicked: root.confirm()
        }
    }
}
