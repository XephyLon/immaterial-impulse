import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Set password: true to mask the input with the lockscreen's animated Material
// shape characters instead of plain text, with an optional reveal toggle.
RowLayout {
    id: root

    property string text: ""
    property string description: ""
    property string buttonIcon: ""
    property alias placeholderText: textArea.placeholderText
    property alias value: textArea.text
    property alias textArea: textArea
    property bool filled: true
    property bool showBorder: !filled
    property bool rounded: false
    property real fieldWidth: 220
    property real fieldHeight: 40
    property color colBackground: filled ? Appearance.colors.colLayer1 : "transparent"
    property color colBackgroundFocused: filled ? Appearance.colors.colLayer2 : "transparent"
    property color colBorder: Appearance.colors.colOutlineVariant
    property color colBorderFocused: Appearance.colors.colPrimary
    property color colOnBackground: Appearance.colors.colOnLayer1
    property color colLabel: Appearance.colors.colOnSecondaryContainer
    property real cornerRadius: rounded ? Appearance.rounding.large : Appearance.rounding.small
    property bool password: false
    property bool revealButton: password
    property bool revealed: false

    spacing: Appearance.spacing.space150
    Layout.leftMargin: Appearance.spacing.space100
    Layout.rightMargin: Appearance.spacing.space100

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
        opacity: root.enabled ? 1 : 0.4
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.text
            color: root.colLabel
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            opacity: root.enabled ? 1 : 0.4
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: Appearance.spacing.space50

        Rectangle {
            id: fieldBg
            Layout.preferredWidth: root.fieldWidth
            Layout.preferredHeight: root.fieldHeight
            Layout.alignment: Qt.AlignVCenter
            radius: root.cornerRadius
            clip: true
            color: textArea.activeFocus ? root.colBackgroundFocused : root.colBackground
            border.width: (hoverHandler.hovered || textArea.activeFocus) ? (textArea.activeFocus ? 2 : 1) : 0
            border.color: textArea.activeFocus ? root.colBorderFocused : root.colBorder

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }
            Behavior on border.color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }
            Behavior on border.width {
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            HoverHandler {
                id: hoverHandler
            }

            TextArea {
                id: textArea
                anchors.fill: parent
                anchors.leftMargin: Appearance.spacing.space150
                anchors.rightMargin: Appearance.spacing.space150
                enabled: root.enabled
                // TextArea has no echoMode (TextEdit-based, unlike TextField) - masking is
                // done purely by making the glyphs transparent and drawing PasswordChars
                // over them instead. NoWrap keeps a masked value on one line, matching
                // PasswordChars' flat left-to-right character layout.
                wrapMode: root.password ? TextArea.NoWrap : TextArea.Wrap
                verticalAlignment: TextEdit.AlignVCenter
                selectByMouse: true
                inputMethodHints: root.password ? Qt.ImhSensitiveData : Qt.ImhNone
                placeholderTextColor: Appearance.colors.colSubtext
                color: root.password && !root.revealed ? "transparent" : root.colOnBackground
                selectedTextColor: root.password && !root.revealed ? "transparent" : Appearance.colors.colOnSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer
                renderType: Text.NativeRendering
                background: null
                padding: 0
                font {
                    family: Appearance.font.family.main
                    pixelSize: Appearance.font.pixelSize.small
                    hintingPreference: Font.PreferFullHinting
                    variableAxes: Appearance.font.variableAxes.main
                }

                // A masked field is conceptually single-line - swallow Enter/Return
                // instead of letting TextArea insert a newline into the stored value.
                Keys.onReturnPressed: (event) => {
                    if (root.password) {
                        event.accepted = true;
                        textArea.focus = false;
                    }
                }
                Keys.onEnterPressed: (event) => {
                    if (root.password) {
                        event.accepted = true;
                        textArea.focus = false;
                    }
                }

                Loader {
                    active: root.password && !root.revealed
                    // Keep the Flickable-based glyph overlay purely visual so clicks reach
                    // the TextArea beneath it.
                    enabled: false
                    anchors.fill: parent
                    sourceComponent: PasswordChars {
                        charSize: 16
                        length: textArea.text.length
                        selectionStart: textArea.selectionStart
                        selectionEnd: textArea.selectionEnd
                        cursorPosition: textArea.cursorPosition
                        showCursor: textArea.activeFocus
                    }
                }
            }
        }

        RippleButton {
            visible: root.password && root.revealButton
            enabled: root.enabled
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            onClicked: root.revealed = !root.revealed

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -2
                iconSize: Appearance.font.pixelSize.larger
                text: root.revealed ? "visibility_off" : "visibility"
                color: Appearance.colors.colOnLayer1
            }
        }
    }
}
