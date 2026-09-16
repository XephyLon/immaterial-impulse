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
 * Parameters of the `schedule` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: Appearance.spacing.space125

    readonly property var sun: ({ sunrise: Weather.data?.sunrise ?? "", sunset: Weather.data?.sunset ?? "" })
    readonly property int fromMin: ModeSchema.timeToMinutes(row.trigger.from, sun)
    readonly property int toMin: ModeSchema.timeToMinutes(row.trigger.to, sun)
    readonly property bool usesSun: ModeSchema.SUN_TOKENS.indexOf(row.trigger.from) !== -1
        || ModeSchema.SUN_TOKENS.indexOf(row.trigger.to) !== -1

    RowLayout {
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("From")
        }

        SunTimeField {
            value: row.trigger.from
            onCommitted: v => row.set({ from: v })
        }

        FormLabel {
            text: Translation.tr("to")
        }

        SunTimeField {
            value: row.trigger.to
            onCommitted: v => row.set({ to: v })
        }
    }

    // Its own line: beside the fields it ran past the card's edge.
    FormHint {
        visible: fromMin >= 0 && toMin >= 0 && fromMin >= toMin
        text: Translation.tr("Overnight: the window runs past midnight into the next day")
    }

    FormHint {
        visible: usesSun
        text: fromMin >= 0 && toMin >= 0
            ? Translation.tr("Today: sunrise %1, sunset %2 — from the weather widget's location.")
                .arg(Weather.data.sunrise).arg(Weather.data.sunset)
            : Translation.tr("Sunrise and sunset come from the weather widget; nothing has loaded yet, "
                + "so the window stays closed.")
    }

    RowLayout {
        spacing: Appearance.spacing.space50

        Repeater {
            model: 7

            // The shell's filter chip, in its selected tone: the default
            // (every day) is not the form's heaviest element.
            delegate: FilterChip {
                id: dayButton
                required property int index
                readonly property int day: dayButton.index + 1
                // No days listed means every day, and is drawn that way.
                readonly property var days: ModeSchema.toArray(row.trigger.days).map(Number)
                readonly property bool on: dayButton.days.length === 0 || dayButton.days.indexOf(dayButton.day) !== -1

                label: ModeUi.dayShort[dayButton.index]
                toggled: dayButton.on
                onClicked: {
                    const days = dayButton.days.length ? Array.from(dayButton.days) : [1, 2, 3, 4, 5, 6, 7];
                    const idx = days.indexOf(dayButton.day);
                    if (idx === -1)
                        days.push(dayButton.day);
                    else if (days.length > 1)
                        days.splice(idx, 1);
                    row.set({ days: days.sort((a, b) => a - b) });
                }
            }
        }
    }

    // A clock time, or one of the two sun tokens.
    component SunTimeField: RowLayout {
        id: sunField
        property string value: "00:00"
        signal committed(string value)
        readonly property bool isSun: ModeSchema.SUN_TOKENS.indexOf(sunField.value) !== -1
        spacing: Appearance.spacing.space75

        TimeField {
            visible: !sunField.isSun
            value: sunField.isSun ? "00:00" : sunField.value
            onCommitted: v => sunField.committed(v)
        }

        FormChoice {
            Layout.fillWidth: false
            current: sunField.isSun ? sunField.value : "clock"
            onPicked: v => {
                if (v === "clock")
                    sunField.committed(sunField.isSun ? "08:00" : sunField.value);
                else
                    sunField.committed(v);
            }
            options: [
                { displayName: Translation.tr("Time"), value: "clock" },
                { displayName: Translation.tr("Sunrise"), value: "sunrise" },
                { displayName: Translation.tr("Sunset"), value: "sunset" }
            ]
        }
    }
}
