import qs.services
import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RowLayout {
    id: root

    property string text: ""
    property string description: ""
    // Shown as a hoverable "i" beside the label rather than inline, so a
    // rationale does not become a paragraph under the label.
    property string infoText: ""
    property string buttonIcon: ""
    // Entries are `{ displayName, value }`, and one may carry
    // `recommended: true`: its label is drawn with a "(Recommended)" suffix,
    // so the default choice is said on the row - the dropdown shape of the
    // settings row grammar (AGENT.md, design language).
    property var model: []
    property string textRole: "displayName"
    property var currentValue: undefined

    property real fieldWidth: 220

    property alias comboBox: comboBox

    signal selected(var newValue)

    // The model as drawn: the recommended entry's label carries the suffix and
    // every other entry passes through untouched. The copy keeps `value`,
    // which is what `onActivated` reads, and the indices are the model's own,
    // which is what `currentIndex` is resolved against.
    readonly property var displayModel: {
        if (typeof root.model?.map !== "function")
            return root.model;
        return root.model.map(item => {
            if (!item || !item.recommended)
                return item;
            const copy = Object.assign({}, item);
            copy[root.textRole] = Translation.tr("%1 (Recommended)").arg(item[root.textRole]);
            return copy;
        });
    }

    spacing: Appearance.spacing.space150
    Layout.leftMargin: Appearance.spacing.space100
    Layout.rightMargin: Appearance.spacing.space100

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
        opacity: root.enabled ? 1 : 0.4
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            opacity: root.enabled ? 1 : 0.4
        }
    }

    InfoTooltipIcon {
        tooltipText: root.infoText
        opacity: root.enabled ? 1 : 0.4
    }

    StyledComboBox {
        id: comboBox
        Layout.preferredWidth: root.fieldWidth
        Layout.alignment: Qt.AlignVCenter
        enabled: root.enabled
        textRole: root.textRole
        model: root.displayModel

        currentIndex: {
            const index = root.model.findIndex(item => item.value === root.currentValue);
            return index !== -1 ? index : 0;
        }

        onActivated: index => {
            root.selected(comboBox.model[index].value);
        }
    }
}
