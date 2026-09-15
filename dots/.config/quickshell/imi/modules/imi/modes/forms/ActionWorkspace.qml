pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `workspace` action: go there, or take the focused
 * window there. `row` is the ActionRow this form unfolds from; every
 * change goes back through it.
 */
ColumnLayout {
    id: wsCol
    required property var row

    spacing: Appearance.spacing.space125

    readonly property bool moving: (row.obj.action ?? "go") === "move"
    readonly property string target: String(row.obj.target ?? "")
    readonly property var quick: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]

    FormChoice {
        text: Translation.tr("Do")
        current: wsCol.moving ? "move" : "go"
        onPicked: v => row.patchValue({ action: v })
        options: [
            { displayName: Translation.tr("Go to"), value: "go" },
            { displayName: Translation.tr("Move the focused window to"), value: "move" }
        ]
    }

    Flow {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space75

        Repeater {
            model: wsCol.quick.concat(["+1", "-1", "empty", "special"])

            delegate: RippleButton {
                id: chip
                required property string modelData
                readonly property bool on: chip.modelData === wsCol.target

                implicitHeight: 32
                implicitWidth: Math.max(32, chipText.implicitWidth + Appearance.spacing.space250)
                buttonRadius: Appearance.rounding.full
                colBackground: on ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                colBackgroundHover: on ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
                colRipple: on ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
                onClicked: row.patchValue({ target: chip.modelData })

                contentItem: StyledText {
                    id: chipText
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: {
                        if (chip.modelData === "+1")
                            return Translation.tr("Next");
                        if (chip.modelData === "-1")
                            return Translation.tr("Previous");
                        if (chip.modelData === "empty")
                            return Translation.tr("Empty");
                        if (chip.modelData === "special")
                            return Translation.tr("Special");
                        return chip.modelData;
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: chip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100

        FormLabel {
            text: Translation.tr("Or")
        }

        PlainField {
            Layout.fillWidth: true
            monospace: true
            value: wsCol.target
            placeholder: Translation.tr("name:mail, special:scratch, r+1…")
            onCommitted: v => row.patchValue({ target: v.trim() })
        }
    }

    ConfigSwitch {
        Layout.fillWidth: true
        visible: !wsCol.moving
        buttonIcon: "undo"
        text: Translation.tr("Go back when it ends")
        description: Translation.tr("Returns to the workspace that was focused when this ran")
        checked: row.obj.back === true
        onToggleRequested: row.patchValue({ back: !checked })
    }
}
