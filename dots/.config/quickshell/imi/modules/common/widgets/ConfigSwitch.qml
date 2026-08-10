import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property string description: ""
    // Shown as a hoverable "i" beside the control rather than inline, so a long
    // explanation doesn't stretch the row.
    property string infoText: ""
    property alias iconSize: iconWidget.iconSize
    // A full-width row beneath everything else, for detail about the row - a
    // byline, tags stating a fact about it. It spans the whole control rather
    // than just the label block, so a call site can push trailing items to the
    // same right edge the switch sits on; inside the label block they would
    // stop short of the switch and hang diagonally beneath it.
    //
    // Empty for every caller that does not set it, and an empty RowLayout has
    // no height, so this costs nothing elsewhere.
    property alias detailContent: detailRow.data
    // Sits on the label's own line, immediately after it. For a secondary
    // phrase that belongs to the title rather than under it - a byline, a
    // version. The label is one StyledText, so a caller cannot mix type sizes
    // into it directly.
    property alias titleContent: titleRow.data
    // Sits immediately before the switch. Row actions have to go in here: the
    // switch is the last thing in this component, so anything a call site
    // appends to its own row can only land beyond it.
    property alias trailingContent: trailingRow.data
    // A click is an intent to flip, not a state change of its own. Assigning to
    // `checked` from a handler destroys the call site's `checked:` binding on
    // the very first click, after which nothing external - a preset, a
    // hand-edited config, a migration - can move the switch again, while the
    // row's own write-back keeps working: the setting changes and the switch
    // lies (#158). The call site owns the value and flips it at the source;
    // `checked` here only ever follows it back.
    //
    // A signal of its own rather than AbstractButton's inherited `toggled()`:
    // RippleButton declares `property bool toggled` (its "draw me as active"
    // flag), which shadows that signal, so `onToggled` at a call site would be
    // the property's change handler rather than this.
    signal toggleRequested()
    colBackgroundHover: "transparent"

    // Nothing in here dims itself on `enabled`. RippleButton already applies the
    // disabled opacity to this whole control - including the switch track, which
    // has none of its own - so a second binding on the icon, the label or a
    // content slot multiplies rather than replaces it, and the row landed at
    // 0.4 * 0.4 = 0.16 instead of 0.4. tests/lint_disabled_opacity.py holds the
    // line.

    Layout.fillWidth: true
    implicitHeight: contentItem.implicitHeight + 8 
    font.pixelSize: Appearance.font.pixelSize.small

    onClicked: root.toggleRequested()

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space150
            OptionalMaterialSymbol {
                id: iconWidget
                icon: root.buttonIcon
                iconSize: Appearance.font.pixelSize.larger
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    StyledText {
                        id: labelWidget
                        text: root.text
                        textFormat: Text.PlainText
                        font: root.font
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    RowLayout {
                        id: titleRow
                        Layout.alignment: Qt.AlignBaseline
                        spacing: Appearance.spacing.space50
                    }
                    // Keeps the label left-aligned now that it no longer fills
                    // the row itself.
                    Item { Layout.fillWidth: true }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.description.length > 0
                    text: root.description
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
            InfoTooltipIcon {
                tooltipText: root.infoText
            }

            RowLayout {
                id: trailingRow
                Layout.alignment: Qt.AlignVCenter
                spacing: Appearance.spacing.space50
            }

            StyledSwitch {
                id: switchWidget
                down: root.down
                Layout.fillWidth: false
                // A Switch is checkable by default and moves its own `checked`
                // on a click or a thumb drag, so it would show the flip even
                // where the call site declines the intent - and stay wrong
                // until the config next changed. Non-checkable it still emits
                // `clicked`, and its `checked` stays a picture of the row's.
                checkable: false
                checked: root.checked
                onClicked: root.clicked()
            }
        }

        RowLayout {
            id: detailRow
            Layout.fillWidth: true
            // Only when the slot is actually filled, so the 164 callers that
            // leave it empty keep their current row height exactly.
            Layout.topMargin: detailRow.children.length > 0
                ? Appearance.spacing.space100 : 0
            spacing: Appearance.spacing.space50
        }
    }
}
