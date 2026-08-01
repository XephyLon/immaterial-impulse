import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RowLayout {
    id: root
    property string text: ""
    property string icon: ""
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

    signal selected(var newValue)

    spacing: Appearance.spacing.space150
    Layout.leftMargin: Appearance.spacing.space100
    Layout.rightMargin: Appearance.spacing.space100

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
                onClicked: {
                    root.selected(modelData.value);
                }
            }
        }
    }
}