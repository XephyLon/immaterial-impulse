import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The keyboard-shortcuts editor for one binding, shared by the cheatsheet's
 * per-row edit affordance and the settings page. Takes an annotated binding
 * from HyprlandKeybinds (identity, chord, dispatcher/params/flags, editable/
 * removable/overridden/added) and writes only through
 * HyprlandKeybindOverrides - never to any keybind file directly.
 *
 * Conflicts for the captured chord are recomputed reactively against the full
 * occupancy scan and block Apply; the scan cannot see loop-generated binds,
 * which is why the clean state reads "no conflicts detected" rather than
 * promising there are none.
 */
ColumnLayout {
    id: root

    property var bindingData: null
    signal done()

    function focusCapture() {
        capture.clear();
        capture.forceActiveFocus();
    }

    readonly property bool foreignShim: HyprlandKeybindOverrides.shimStatus === "foreign"
    readonly property bool writable: !root.foreignShim && root.bindingData !== null

    readonly property var conflicts: {
        // Referenced so the binding re-evaluates when the scans or the
        // override set change, not only when the capture does.
        const flatDefault = HyprlandKeybindOverrides.flatDefaultBinds;
        const flatUser = HyprlandKeybindOverrides.flatUserBinds;
        const overrideState = HyprlandKeybindOverrides.state;
        void flatDefault; void flatUser; void overrideState;
        if (!capture.hasChord || root.bindingData === null)
            return [];
        return HyprlandKeybindOverrides.conflictsFor(
            capture.mods, capture.key, root.bindingData.identity);
    }

    readonly property bool chordChanged: capture.hasChord && root.bindingData !== null
        && HyprlandKeybindOverrides.identityFor(capture.mods, capture.key)
           !== HyprlandKeybindOverrides.identityFor(root.bindingData.mods, root.bindingData.key)
    // Acknowledging a conflict is per-chord: capturing a different one has to
    // re-ask, or a stale "yes" from an earlier attempt would carry over.
    property string acknowledgedChord: ""
    readonly property string capturedIdentity: capture.hasChord
        ? HyprlandKeybindOverrides.identityFor(capture.mods, capture.key) : ""
    readonly property bool conflictAcknowledged: root.conflicts.length === 0
        || (root.capturedIdentity.length > 0 && root.acknowledgedChord === root.capturedIdentity)
    readonly property bool canApply: root.writable && root.chordChanged
        && root.conflictAcknowledged
        && (root.bindingData.editable || root.bindingData.added)

    function apply() {
        if (!root.canApply)
            return;
        const data = root.bindingData;
        if (data.added) {
            const entry = HyprlandKeybindOverrides.overrideFor(data.identity);
            HyprlandKeybindOverrides.reset(data.identity);
            HyprlandKeybindOverrides.addBinding(
                capture.mods, capture.key, entry?.command ?? "", entry?.description ?? "");
        } else {
            HyprlandKeybindOverrides.setRebind(data.identity, capture.mods, capture.key, data);
        }
        root.done();
    }

    spacing: Appearance.spacing.space150

    StyledText {
        Layout.fillWidth: true
        text: root.bindingData?.comment ?? ""
        font.pixelSize: Appearance.font.pixelSize.larger
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer1
        wrapMode: Text.Wrap
    }

    RowLayout {
        spacing: Appearance.spacing.space100
        StyledText {
            text: Translation.tr("Current:")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        Repeater {
            model: root.bindingData ? [...root.bindingData.mods, root.bindingData.key] : []
            delegate: KeyboardKey {
                required property var modelData
                key: modelData
            }
        }
        StyledText {
            visible: root.bindingData?.overridden ?? false
            text: Translation.tr("(customized)")
            color: Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    KeybindChordCapture {
        id: capture
        Layout.fillWidth: true
        visible: root.bindingData !== null && (root.bindingData.editable || root.bindingData.added)
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.bindingData !== null
            && !root.bindingData.editable && !root.bindingData.added
        text: Translation.tr("This shortcut's action is defined as code in the keybind config, so it cannot be moved to another chord from here. It can still be removed.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.foreignShim
        text: Translation.tr("The generated override file was edited by hand, so the shell refuses to change it. Delete %1 to edit shortcuts from here again.")
            .arg(HyprlandKeybindOverrides.shimPath)
        color: Appearance.colors.colError
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
    }

    StyledText {
        Layout.fillWidth: true
        visible: HyprlandSubmap.active
        text: Translation.tr("A keybind submap (%1) is active right now; the default shortcuts are suspended until it exits.")
            .arg(HyprlandSubmap.submapName)
        color: Appearance.colors.colError
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: capture.hasChord
        spacing: Appearance.spacing.space25

        StyledText {
            visible: root.conflicts.length === 0
            text: root.chordChanged
                ? Translation.tr("No conflicts detected for this chord")
                : Translation.tr("That is already this shortcut's chord")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Repeater {
            model: root.conflicts
            delegate: StyledText {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.submap.length > 0
                    ? Translation.tr("Conflicts with \"%1\" (submap %2)")
                        .arg(modelData.description).arg(modelData.submap)
                    : Translation.tr("Conflicts with \"%1\"").arg(modelData.description)
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }
        }

        // A conflict used to disable Apply outright, which left no way to
        // deliberately move a chord onto one already in use - and no
        // explanation, just a dead button. It is a warning to confirm now.
        // Hyprland keeps both binds; the shell cannot remove someone else's,
        // so say what will actually happen rather than implying a swap.
        ConfigSwitch {
            id: conflictConfirm
            Layout.fillWidth: true
            visible: root.conflicts.length > 0
            buttonIcon: "warning"
            text: Translation.tr("Assign it anyway — both shortcuts will fire on this chord")
            checked: root.acknowledgedChord === root.capturedIdentity
            onClicked: {
                root.acknowledgedChord = (root.acknowledgedChord === root.capturedIdentity)
                    ? "" : root.capturedIdentity;
            }
        }
    }

    // Auto-cancel. A click on a chord row opens this, and a misclick on a dense
    // list is easy - without a way out that costs nothing, the editor is a trap
    // that has to be dismissed deliberately. Any interaction cancels the
    // countdown: it only fires when the editor was opened and then ignored.
    Timer {
        id: idleCancel
        interval: 5000
        running: root.bindingData !== null && !capture.hasChord
            && !capture.activeFocus && capture.pendingMods.length === 0
        onTriggered: root.done()
    }

    StyledText {
        Layout.fillWidth: true
        visible: idleCancel.running
        horizontalAlignment: Text.AlignHCenter
        text: Translation.tr("Closing in %1s — press a shortcut to edit it")
            .arg(Math.ceil(idleCancel.interval / 1000))
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space50

        DialogButton {
            id: resetButton
            visible: (root.bindingData?.overridden ?? false) && !(root.bindingData?.added ?? false)
            enabled: root.writable
            buttonText: Translation.tr("Reset to default")
            onClicked: {
                HyprlandKeybindOverrides.reset(root.bindingData.identity);
                root.done();
            }
        }

        DialogButton {
            id: removeButton
            visible: root.bindingData?.removable ?? false
            enabled: root.writable
            buttonText: root.bindingData?.added
                ? Translation.tr("Delete shortcut")
                : Translation.tr("Remove binding")
            colEnabled: Appearance.colors.colError
            onClicked: {
                if (root.bindingData.added)
                    HyprlandKeybindOverrides.reset(root.bindingData.identity);
                else
                    HyprlandKeybindOverrides.removeBinding(root.bindingData.identity);
                root.done();
            }
        }

        Item { Layout.fillWidth: true }

        DialogButton {
            id: cancelButton
            buttonText: Translation.tr("Cancel")
            onClicked: root.done()
        }

        DialogButton {
            id: applyButton
            enabled: root.canApply
            buttonText: Translation.tr("Apply")
            onClicked: root.apply()
        }
    }
}
