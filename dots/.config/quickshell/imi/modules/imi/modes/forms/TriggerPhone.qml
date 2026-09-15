pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `phone` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: Appearance.spacing.space125

    FormChoice {
        text: Translation.tr("Phone")
        current: row.trigger.reachable === false ? "away" : "near"
        onPicked: v => row.set({ reachable: v === "near" })
        options: [
            { displayName: Translation.tr("Reachable"), value: "near" },
            { displayName: Translation.tr("Out of reach"), value: "away" }
        ]
    }

    RowLayout {
        visible: row.trigger.reachable !== false
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("Phone battery below")
        }

        NumberField {
            suffix: "%"
            value: row.trigger.batteryBelow
            onCommitted: v => row.set({ batteryBelow: v })
        }

        FormHint {
            text: Translation.tr("Leave empty to ignore")
        }
    }

    FormHint {
        text: PhoneConnect.available
            ? (PhoneConnect.activeDevice
                ? Translation.tr("Watches %1 through Phone Connect.").arg(PhoneConnect.activeDevice.name)
                : Translation.tr("No phone is paired yet."))
            : Translation.tr("Needs KDE Connect or Valent (Phone Connect).")
    }
}
