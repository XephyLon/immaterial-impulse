import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The AI pane's tools bar (spec 2026-08-31): the fork's ControlChip grammar
 * on imi tokens. The floating status pill's content lives here now.
 *
 * THE BRIDGE, stated: no popover views in this sub-project. A chip
 * pre-fills its command into the input field and the existing suggestion
 * flow answers; the caret and this file's seams are what the sessions
 * drawer (sub-project 2) fills with the slide-in canvas. This is a module
 * component beside AiMessage, not a shared widget - reading Ai directly
 * is its job.
 */
Item {
    id: root

    property var inputField: null
    property string commandPrefix: "/"

    /** Below this the chips drop their labels and keep icons and values. */
    readonly property bool compact: root.width < 340

    implicitHeight: 32

    function prefill(command) {
        if (!root.inputField) return;
        root.inputField.text = command;
        root.inputField.cursorPosition = root.inputField.text.length;
        root.inputField.forceActiveFocus();
    }

    component ControlChip: RippleButton {
        id: chip
        property string chipIcon: ""
        property string label: ""
        property string value: ""
        property string hint: ""
        property bool caret: false
        property bool alwaysLabel: false
        /** An informational chip: keeps its ink and tooltip, drops the ripple. */
        property bool inert: false
        property color chipInk: Appearance.colors.colOnLayer1
        readonly property bool showLabel: (chip.alwaysLabel || !root.compact) && chip.label.length > 0

        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 32
        implicitWidth: chipContent.implicitWidth + Appearance.spacing.space200 * 2
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: chip.inert ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        rippleEnabled: !chip.inert

        contentItem: RowLayout {
            id: chipContent
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50

            MaterialSymbol {
                text: chip.chipIcon
                iconSize: Appearance.font.pixelSize.larger
                color: chip.chipInk
            }
            StyledText {
                visible: chip.showLabel
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.chipInk
                animateChange: true
            }
            StyledText {
                visible: chip.value.length > 0
                text: chip.value
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.chipInk
                animateChange: true
            }
            MaterialSymbol {
                visible: chip.caret
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.normal
                color: chip.chipInk
                // Reserved: the sessions-drawer sub-project rotates this
                // when its view opens; the Behavior waits here so the
                // motion lands with the feature, not as a second pass.
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        StyledToolTip {
            text: chip.hint
            extraVisibleCondition: chip.hint.length > 0 && chip.hovered
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.space50

        ControlChip { // Model: the name is a value, so compact keeps it.
            chipIcon: "network_intelligence"
            value: Ai.getModel()?.name ?? Translation.tr("Model")
            caret: true
            hint: Translation.tr("Current model\nSet it with %1model MODEL").arg(root.commandPrefix)
            onClicked: root.prefill(root.commandPrefix + "model ")
        }
        ControlChip {
            chipIcon: "device_thermostat"
            value: Ai.temperature.toFixed(1)
            hint: Translation.tr("Temperature\nChange with %1temp VALUE").arg(root.commandPrefix)
            onClicked: root.prefill(root.commandPrefix + "temp ")
        }
        ControlChip {
            chipIcon: Ai.currentModelHasApiKey ? "key" : "key_off"
            chipInk: Ai.currentModelHasApiKey ? Appearance.colors.colOnLayer1
                                              : Appearance.m3colors.m3error
            hint: Ai.currentModelHasApiKey
                ? Translation.tr("API key is set\nChange with %1key YOUR_API_KEY").arg(root.commandPrefix)
                : Translation.tr("No API key\nSet it with %1key YOUR_API_KEY").arg(root.commandPrefix)
            onClicked: root.prefill(root.commandPrefix + "key ")
        }
        ControlChip {
            visible: Ai.tokenCount.total > 0
            inert: true
            chipIcon: "token"
            value: `${Ai.tokenCount.total}`
            hint: Translation.tr("Total token count\nInput: %1\nOutput: %2").arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
        }

        Item { Layout.fillWidth: true }

        ControlChip {
            chipIcon: "edit_square"
            hint: Translation.tr("New chat")
            onClicked: Ai.clearMessages()
        }
    }
}
