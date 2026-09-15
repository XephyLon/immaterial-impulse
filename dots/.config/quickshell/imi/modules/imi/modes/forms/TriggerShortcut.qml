pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `shortcut` event. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: form
    required property var row

    spacing: Appearance.spacing.space125

    readonly property string name: ModeSchema.shortcutName(row.trigger, row.ownerId)
    readonly property string globalName: `quickshell:modes-${form.name}`

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("Name")
        }

        PlainField {
            Layout.preferredWidth: 200
            monospace: true
            value: row.trigger.name
            placeholder: form.name
            onCommitted: v => row.set({ name: v })
        }

        FormHint {
            text: Translation.tr("Optional; the routine's id otherwise")
        }
    }

    FormHint {
        text: Translation.tr("Bind a key to this global shortcut in your Hyprland config, e.g.")
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: bindText.implicitHeight + 16
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer3

        StyledText {
            id: bindText
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
                topMargin: 8
            }
            text: `hl.bind("SUPER + SHIFT + R", hl.dsp.global("${form.globalName}"))\n`
                + `bind = SUPER SHIFT, R, global, ${form.globalName}`
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer3
        }
    }

    FormHint {
        text: Translation.tr("First line for the Lua config, second for a classic hyprland.conf.")
    }
}
