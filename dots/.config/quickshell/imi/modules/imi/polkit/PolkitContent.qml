import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    Keys.onPressed: event => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            PolkitService.cancel();
        }
    }

    function submit() {
        PolkitService.submit(inputField.text);
    }
    Connections {
        target: PolkitService
        function onInteractionAvailableChanged() {
            if (!PolkitService.interactionAvailable) return;
            inputField.text = "";
            inputField.forceActiveFocus();
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        Component.onCompleted: {
            opacity = 1
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    WindowDialog {
        anchors.centerIn: parent
        backgroundWidth: 450
        show: false
        Component.onCompleted: {
            show = true
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            iconSize: 26
            text: "security"
            color: Appearance.colors.colSecondary
        }

        WindowDialogTitle {
            id: titleText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Authentication")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignLeft
            text: PolkitService.cleanMessage
        }

        // The shell's own field, not Material's outlined one. `MaterialTextField`
        // hands the container to QtQuick Controls' Material style
        // (`Material.containerStyle: Material.Outlined`), which draws a boxed
        // outline with the prompt floating in a notch cut through it - a shape
        // that appears nowhere else in this shell. Every field the user meets
        // here is a filled pill: the lock screen's own password box is a
        // `ToolbarTextField`, and so are the launcher, the wallpaper selector
        // and the screen translator. The two password prompts in this shell
        // should not be two different controls.
        //
        // The fill is `colLayer4` because the dialog's body is `WindowDialog`'s
        // `m3surfaceContainerHigh`, i.e. layer 3 - a field nested in it is the
        // tier above, and `colLayer4` is that tier already composited over
        // layer 3. `colLayer1`, the widget's own default, is a tier BELOW the
        // card it would be sitting on and reads as a hole in it.
        ToolbarTextField {
            id: inputField
            Layout.fillWidth: true
            Layout.fillHeight: false
            clip: true
            focus: true
            enabled: PolkitService.interactionAvailable
            placeholderText: PolkitService.cleanPrompt
            echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
            colBackground: Appearance.colors.colLayer4
            color: Appearance.colors.colOnLayer4
            onAccepted: root.submit();

            Keys.onPressed: event => { // Esc to close
                if (event.key === Qt.Key_Escape) {
                    PolkitService.cancel();
                }
            }
        }

        WindowDialogButtonRow {
            Layout.bottomMargin: Appearance.spacing.space150 // I honestly don't know why this is necessary
            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: PolkitService.cancel();
            }
            DialogButton {
                enabled: PolkitService.interactionAvailable
                buttonText: Translation.tr("OK")
                onClicked: root.submit();
            }
        }
    }
}
