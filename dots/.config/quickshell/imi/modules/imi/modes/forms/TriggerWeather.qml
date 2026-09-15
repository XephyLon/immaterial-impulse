pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `weather` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: Appearance.spacing.space125

    StyledComboBox {
        Layout.preferredWidth: 200
        model: [
            Translation.tr("Any weather"), Translation.tr("Clear"), Translation.tr("Cloudy"), Translation.tr("Fog"),
            Translation.tr("Rain"), Translation.tr("Snow"), Translation.tr("Storm")
        ]
        currentIndex: Math.max(0, ["any", "clear", "cloudy", "fog", "rain", "snow", "storm"].indexOf(row.trigger.kind))
        onActivated: index => row.set({ kind: ["any", "clear", "cloudy", "fog", "rain", "snow", "storm"][index] })
    }

    RowLayout {
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("Colder than")
        }

        NumberField {
            from: -100
            to: 150
            value: row.trigger.tempBelow
            onCommitted: v => row.set({ tempBelow: v })
        }

        FormLabel {
            text: Translation.tr("Warmer than")
        }

        NumberField {
            from: -100
            to: 150
            value: row.trigger.tempAbove
            onCommitted: v => row.set({ tempAbove: v })
        }

        FormHint {
            text: Translation.tr("In the weather widget's unit · leave empty to ignore")
        }
    }

    FormHint {
        text: (Weather.data?.wDesc ?? "").length
            ? Translation.tr("Now in %1: %2, %3").arg(Weather.data.city).arg(Weather.data.wDesc).arg(Weather.data.temp)
            : Translation.tr("Needs the weather widget's location; nothing has loaded yet.")
    }
}
