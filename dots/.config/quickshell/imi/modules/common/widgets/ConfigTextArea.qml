import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Set password: true to mask the input with the lockscreen's animated Material
// shape characters instead of plain text, with an optional reveal toggle.
//
// Set floatingLabel: true for the text-field shape of the settings row grammar
// (AGENT.md, design language): the label lives INSIDE the field, resting where
// the value will go and floating to the top edge once the field is focused or
// holds a value, and the field takes the whole row in place of the label
// column it no longer needs. The field grows to M3's filled-field height for
// the label to float into. A row with a `description` keeps its label column
// for the description's sake and the field stays at `fieldWidth`.
RowLayout {
    id: root

    property string text: ""
    property string description: ""
    // Shown as a hoverable "i" beside the label rather than inline, so a
    // rationale does not become a paragraph under the label.
    property string infoText: ""
    property string buttonIcon: ""
    property alias placeholderText: textArea.placeholderText
    property alias value: textArea.text
    property alias textArea: textArea
    property bool filled: true
    property bool showBorder: !filled
    property bool floatingLabel: false
    readonly property bool labelFloated: floatingLabel && (textArea.activeFocus || textArea.text.length > 0)
    property bool rounded: false
    property real fieldWidth: 220
    property real fieldHeight: floatingLabel ? 56 : 40
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
    // Keep the value on one line for inputs like URLs, where wrapping into a
    // stack of lines reads as broken. Overflow is clipped by the field rather
    // than wrapped.
    property bool singleLine: false
    // Optional trailing confirm button
    property bool confirmButtonVisible: false
    property string confirmButtonIcon: "check"
    property color colConfirmBackground: Appearance.colors.colPrimaryContainer
    property color colConfirmBackgroundHover: Appearance.colors.colPrimaryContainerHover
    property color colConfirmBackgroundActive: Appearance.colors.colPrimaryContainerActive
    property color colOnConfirmBackground: Appearance.colors.colOnPrimaryContainer
    signal confirmClicked()

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
        visible: !root.floatingLabel || root.description.length > 0
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            visible: !root.floatingLabel
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

    InfoTooltipIcon {
        tooltipText: root.infoText
        opacity: root.enabled ? 1 : 0.4
    }

    RowLayout {
        Layout.fillWidth: root.floatingLabel && root.description.length === 0
        Layout.alignment: Qt.AlignVCenter
        spacing: Appearance.spacing.space50

        Rectangle {
            id: fieldBg
            Layout.fillWidth: root.floatingLabel && root.description.length === 0
            Layout.preferredWidth: root.fieldWidth
            Layout.preferredHeight: root.fieldHeight
            Layout.alignment: Qt.AlignVCenter
            radius: root.cornerRadius
            clip: true
            color: textArea.activeFocus ? root.colBackgroundFocused : root.colBackground
            border.width: (hoverHandler.hovered || textArea.activeFocus) ? (textArea.activeFocus ? 2 : 1) : 0
            border.color: textArea.activeFocus ? root.colBorderFocused : root.colBorder

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on border.width {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            HoverHandler {
                id: hoverHandler
            }

            // The floating label. Under the TextArea in z-order, which is fine:
            // the field has no background of its own, and while the label rests
            // in the value's place the value is empty.
            StyledText {
                id: floatingLabelText
                visible: root.floatingLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Appearance.spacing.space150
                anchors.rightMargin: Appearance.spacing.space150
                y: root.labelFloated ? Appearance.spacing.space75 : (parent.height - height) / 2
                text: root.text
                elide: Text.ElideRight
                font.pixelSize: root.labelFloated ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                color: root.labelFloated && textArea.activeFocus ? root.colBorderFocused : root.colLabel
                opacity: root.enabled ? 1 : 0.4

                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on font.pixelSize {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            TextArea {
                id: textArea
                anchors.fill: parent
                anchors.leftMargin: Appearance.spacing.space150
                anchors.rightMargin: Appearance.spacing.space150
                // Leaves the top of the field to the floated label.
                anchors.topMargin: root.floatingLabel ? Appearance.spacing.space300 : 0
                enabled: root.enabled
                // TextArea has no echoMode (TextEdit-based, unlike TextField) - masking is
                // done purely by making the glyphs transparent and drawing PasswordChars
                // over them instead. NoWrap keeps a masked value on one line, matching
                // PasswordChars' flat left-to-right character layout.
                wrapMode: (root.password || root.singleLine) ? TextArea.NoWrap : TextArea.Wrap
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

                // The Basic style (pinned by `pragma Env QT_QUICK_CONTROLS_STYLE=Basic`)
                // draws placeholderText through its own PlaceholderText child - a Text
                // subclass left at the inherited Text.AutoText, unreachable
                // declaratively from here. PluginOptions feeds optionData.placeholder
                // straight from attacker-controlled manifests, so force the style's
                // placeholder to plain text once it exists.
                Component.onCompleted: {
                    for (const child of textArea.children) {
                        if (child instanceof Text)
                            child.textFormat = Text.PlainText;
                    }
                }

                // A masked or single-line field is conceptually one line - swallow
                // Enter/Return instead of letting TextArea insert a newline into
                // the stored value.
                Keys.onReturnPressed: (event) => {
                    if (root.password || root.singleLine) {
                        event.accepted = true;
                        textArea.focus = false;
                    }
                }
                Keys.onEnterPressed: (event) => {
                    if (root.password || root.singleLine) {
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
                        // Sized to the field's small text, not the lockscreen's
                        // hero row the widget was born on.
                        charSize: 12
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
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: Appearance.font.pixelSize.larger
                text: root.revealed ? "visibility_off" : "visibility"
                color: Appearance.colors.colOnLayer1
            }
        }
    }
    // Enters and leaves the way the bar's standalone pills do (TimerPill,
    // SubmapIndicator): the width glides between 0 and its size on the same
    // tier as the fade and the scale, so the field beside it reflows with the
    // motion instead of jumping a button-width in one frame, and the button
    // leaves the layout only once its width is gone. Recorded by the
    // maintainer on the presets "save" button: it snapped in and out.
    RippleButton {
        readonly property bool shown: root.confirmButtonVisible
        visible: implicitWidth > 0
        enabled: shown
        implicitWidth: shown ? 40 : 0
        implicitHeight: 40
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.7
        transformOrigin: Item.Center
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Layout.alignment: Qt.AlignVCenter
        buttonRadius: Appearance.rounding.small
        colBackground: root.colConfirmBackground
        colBackgroundHover: root.colConfirmBackgroundHover
        colRipple: root.colConfirmBackgroundActive
        onClicked: root.confirmClicked()

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.confirmButtonIcon
            iconSize: Appearance.font.pixelSize.large
            color: root.colOnConfirmBackground
        }
    }
}
