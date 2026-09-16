pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `volume` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: volumeCol
    required property var row

    spacing: Appearance.spacing.space125

    readonly property bool setsLevel: row.obj.level !== null && row.obj.level !== undefined

    // The shell's switch row; the slider rides its detail line while a
    // level is set.
    ConfigSwitch {
        Layout.fillWidth: true
        leftPadding: 0
        rightPadding: 0
        buttonIcon: "volume_up"
        text: Translation.tr("Set a level")
        description: volumeCol.setsLevel ? Translation.tr("Sets the volume to %1 %").arg(Math.round(volumeSlider.value))
            : Translation.tr("Off: leaves the volume where it is")
        checked: volumeCol.setsLevel
        onToggleRequested: row.patchValue({ level: volumeCol.setsLevel ? null : 40 })

        detailContent: StyledSlider {
            id: volumeSlider
            Layout.fillWidth: true
            visible: volumeCol.setsLevel
            from: 0
            to: 100
            stepSize: 1
            value: Number(row.obj.level) || 0
            onPressedChanged: {
                if (!pressed)
                    row.patchValue({ level: Math.round(value) });
            }
        }
    }

    FormChoice {
        text: Translation.tr("Mute")
        current: row.obj.muted === true ? "mute" : (row.obj.muted === false ? "unmute" : "keep")
        onPicked: v => row.patchValue({ muted: v === "keep" ? null : v === "mute" })
        options: [
            { displayName: Translation.tr("Leave mute as is"), value: "keep" },
            { displayName: Translation.tr("Mute"), value: "mute" },
            { displayName: Translation.tr("Unmute"), value: "unmute" }
        ]
    }
}
