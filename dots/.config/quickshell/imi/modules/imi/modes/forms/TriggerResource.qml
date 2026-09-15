pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `resource` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: Appearance.spacing.space125

    readonly property bool isTemp: String(row.trigger.metric).endsWith("Temp")

    StyledComboBox {
        Layout.preferredWidth: 240
        model: [
            Translation.tr("CPU load"), Translation.tr("CPU temperature"),
            Translation.tr("GPU load"), Translation.tr("GPU temperature"),
            Translation.tr("Memory used"), Translation.tr("Swap used"), Translation.tr("Disk used")
        ]
        currentIndex: Math.max(0, ["cpuUsage", "cpuTemp", "gpuUsage", "gpuTemp", "memory", "swap", "disk"]
            .indexOf(row.trigger.metric))
        onActivated: index => row.set({
            metric: ["cpuUsage", "cpuTemp", "gpuUsage", "gpuTemp", "memory", "swap", "disk"][index]
        })
    }

    RowLayout {
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("Above")
        }

        NumberField {
            to: 1000
            value: row.trigger.above
            onCommitted: v => row.set({ above: v })
        }

        FormLabel {
            text: Translation.tr("Below")
        }

        NumberField {
            to: 1000
            value: row.trigger.below
            onCommitted: v => row.set({ below: v })
        }

        FormHint {
            text: isTemp ? Translation.tr("°C · leave one empty") : Translation.tr("% · leave one empty")
        }
    }

    FormHint {
        text: Translation.tr("Read every few seconds with 5 units of slack, so a value on the line does not flap.")
    }
}
