pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `idle` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: Appearance.spacing.space125

    RowLayout {
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("No input for")
        }

        DurationField {
            seconds: row.trigger.sec
            minimum: 1
            onCommitted: sec => row.set({ sec: Math.max(5, sec) })
        }
    }

    ConfigSwitch {
        Layout.fillWidth: true
        buttonIcon: "coffee"
        text: Translation.tr("Even while Keep Awake is on")
        description: Translation.tr("Off: an idle inhibitor (a movie, Keep Awake) counts as activity")
        checked: row.trigger.ignoreInhibitors === true
        onToggleRequested: row.set({ ignoreInhibitors: !checked })
    }
}
