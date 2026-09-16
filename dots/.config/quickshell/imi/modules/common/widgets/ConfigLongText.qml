import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A settings row for LONG text - a system prompt, a template, a note: the
 * label on its own line above a field that takes the row's width, grows
 * with the text from `minLines` to `maxLines`, and scrolls inside itself
 * past that with the caret kept in view. Same fill, border, radius and
 * focus colours as ConfigTextArea's field, so the two read as one family.
 *
 * ConfigTextArea is a VALUE field: one line, a fixed height, the label
 * beside it or floating inside it. A paragraph put in one had no room and
 * no scroll (the AI system prompt was clipped to its first lines), which is
 * what this row exists for.
 */
ColumnLayout {
    id: root

    property string text: ""
    property string description: ""
    // Shown as a hoverable "i" beside the label rather than inline, so a long
    // explanation does not stretch the row.
    property string infoText: ""
    property string buttonIcon: ""
    property alias placeholderText: textArea.placeholderText
    property alias value: textArea.text
    property alias textArea: textArea
    property int minLines: 4
    property int maxLines: 10
    property color colBackground: Appearance.colors.colLayer1
    property color colBackgroundFocused: Appearance.colors.colLayer2
    property color colBorder: Appearance.colors.colOutlineVariant
    property color colBorderFocused: Appearance.colors.colPrimary
    property color colOnBackground: Appearance.colors.colOnLayer1
    property color colLabel: Appearance.colors.colOnSecondaryContainer

    readonly property real lineHeight: metrics.height
    readonly property real fieldPadding: Appearance.spacing.space150

    Layout.fillWidth: true
    Layout.leftMargin: Appearance.spacing.space100
    Layout.rightMargin: Appearance.spacing.space100
    spacing: Appearance.spacing.space75

    FontMetrics {
        id: metrics
        font: textArea.font
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space150

        OptionalMaterialSymbol {
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.text
                color: root.colLabel
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }

        InfoTooltipIcon {
            tooltipText: root.infoText
        }
    }

    Rectangle {
        id: fieldBg
        Layout.fillWidth: true
        // Grows with the text between the two line counts; past the maximum
        // the flickable inside takes over.
        implicitHeight: Math.min(root.maxLines, Math.max(root.minLines, textArea.lineCount)) * root.lineHeight
            + root.fieldPadding * 2
        radius: Appearance.rounding.small
        clip: true
        color: textArea.activeFocus ? root.colBackgroundFocused : root.colBackground
        border.width: (hoverHandler.hovered || textArea.activeFocus)
            ? (textArea.activeFocus ? Appearance.borderWidth.emphasis : Appearance.borderWidth.standard) : 0
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
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        HoverHandler {
            id: hoverHandler
        }

        // The TextArea is attached to the flickable (TextArea.flickable), so
        // the control sizes the content and keeps the caret scrolled into
        // view as it moves; the flickable brings the shell's wheel handling
        // and scrollbar.
        StyledFlickable {
            id: flick
            anchors.fill: parent
            anchors.margins: root.fieldPadding
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TextArea.flickable: StyledTextArea {
                id: textArea
                enabled: root.enabled
                wrapMode: TextArea.Wrap
                selectByMouse: true
                color: root.colOnBackground
                placeholderTextColor: Appearance.colors.colSubtext
                background: null
                padding: 0

                Component.onCompleted: {
                    for (const child of textArea.children) {
                        if (child instanceof Text)
                            child.textFormat = Text.PlainText;
                    }
                }
            }
        }

        ScrollEdgeFade {
            target: flick
        }
    }
}
