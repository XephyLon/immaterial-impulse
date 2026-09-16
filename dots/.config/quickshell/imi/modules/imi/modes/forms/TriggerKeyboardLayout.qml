pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `keyboardLayout` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: Appearance.spacing.space125

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("Layout code")
        }

        PlainField {
            Layout.preferredWidth: 120
            monospace: true
            value: row.trigger.code
            placeholder: "fr"
            onCommitted: v => row.set({ code: v })
        }

        Repeater {
            model: Array.from(HyprlandXkb.layoutCodes ?? []).filter((c, i, a) => c && a.indexOf(c) === i)

            delegate: DialogButton {
                required property string modelData
                buttonText: modelData
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                colText: Appearance.colors.colOnSecondaryContainer
                onClicked: row.set({ code: modelData })
            }
        }
    }

    FormHint {
        text: HyprlandXkb.currentLayoutCode.length
            ? Translation.tr("Active now: %1 (%2)").arg(HyprlandXkb.currentLayoutName).arg(HyprlandXkb.currentLayoutCode)
            : Translation.tr("Switch layouts once so the shell learns the codes.")
    }
}
