import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// A segmented single-choice row: a label, and one button per option. Rooted
// on a column rather than a row so that a full-width line can sit UNDER the
// choice - `detailContent`, where Settings > Capture puts the quality tier's
// computed bitrate (the row grammar's live hint; AGENT.md, design language).
ColumnLayout {
    id: root
    property string text: ""
    property string icon: ""
    // Shown as a hoverable "i" beside the label rather than inline, so a long
    // explanation doesn't stretch the row.
    property string infoText: ""
    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    property var currentValue: null
    // A full-width row beneath the choice, for what the current option means
    // on this machine. Empty for every caller that does not set it, and an
    // empty RowLayout has no height, so it costs nothing elsewhere. The gap
    // above it follows what is DRAWN in it rather than what is declared, so a
    // hint that hides itself takes its gap with it.
    property alias detailContent: detailRow.data

    signal selected(var newValue)

    spacing: 0
    Layout.leftMargin: Appearance.spacing.space100
    Layout.rightMargin: Appearance.spacing.space100

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space150

        RowLayout {
            spacing: Appearance.spacing.space150
            visible: root.text !== ""
            OptionalMaterialSymbol {
                icon: root.icon
                opacity: root.enabled ? 1 : 0.4
            }
            StyledText {
                id: labelWidget
                Layout.fillWidth: true
                text: root.text
                color: Appearance.colors.colOnSecondaryContainer
                opacity: root.enabled ? 1 : 0.4
            }
            InfoTooltipIcon {
                tooltipText: root.infoText
                opacity: root.enabled ? 1 : 0.4
            }
        }

        Flow {
            id: buttonsFlow
            Layout.fillWidth: !root.text
            Layout.alignment: Qt.AlignRight
            spacing: Appearance.spacing.space25

            Repeater {
                model: root.options
                delegate: SelectionGroupButton {
                    id: paletteButton
                    required property var modelData
                    required property int index
                    onYChanged: {
                        if (index === 0) {
                            paletteButton.leftmost = true
                        } else {
                            var prev = buttonsFlow.children[index - 1]
                            var thisIsOnNewLine = prev && prev.y !== paletteButton.y
                            paletteButton.leftmost = thisIsOnNewLine
                            prev.rightmost = thisIsOnNewLine
                        }
                    }
                    leftmost: index === 0
                    rightmost: index === root.options.length - 1
                    buttonIcon: modelData.icon || ""
                    buttonText: modelData.displayName
                    toggled: root.currentValue == modelData.value
                    // An option the shell declines. It is still drawn, and still
                    // drawn as current if a stored config already holds it -
                    // dropping it from the model would silently shorten the row
                    // with nothing on screen saying why.
                    enabled: root.enabled && !(modelData.disabled ?? false)
                    onClicked: {
                        root.selected(modelData.value);
                    }
                }
            }
        }
    }

    RowLayout {
        id: detailRow
        Layout.fillWidth: true
        Layout.topMargin: detailRow.visibleChildren.length > 0
            ? Appearance.spacing.space100 : 0
        spacing: Appearance.spacing.space50
    }
}
