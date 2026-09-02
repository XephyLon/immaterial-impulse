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

        // The unlabelled path's right edge. With the Flow the only item in the
        // row, its `Layout.alignment: Qt.AlignRight` aligned it inside a cell
        // that was already its own width and the surplus stayed at the row's
        // end - so in a card the chips sat left, right after the title, and
        // four stacked cards had four different right edges. The spacer takes
        // the surplus (the Flow's maximum is its natural width), and when the
        // row is narrower than the chips the spacer is 0 and the Flow shrinks
        // and wraps as before. The labelled path's label already fills.
        Item {
            visible: !root.text
            Layout.fillWidth: true
        }

        Flow {
            id: buttonsFlow
            Layout.fillWidth: !root.text
            Layout.alignment: Qt.AlignRight
            spacing: Appearance.spacing.space25

            // A Flow with no width of its own takes its implicitWidth, and a
            // Flow computes THAT from the width it currently has - so the two
            // define each other. Built in one pass it happens to settle on one
            // line; incubated across frames (which is how a settings page is
            // built since the page host stopped blocking on construction) it
            // latches at the narrow intermediate width, wraps every chip onto
            // its own line, and never re-flows, because the wrap is what keeps
            // the implicit width narrow. Measured on this row at 628px: 43px
            // tall built synchronously, 154px incubated.
            //
            // `naturalWidth` is summed from the buttons' own implicit widths,
            // which owe nothing to this Flow, so it is an answer rather than a
            // circle. Handing it over as the PREFERRED width leaves the layout
            // free to give less when there is less, and the chips wrap then for
            // the real reason.
            readonly property real naturalWidth: {
                let total = 0;
                let counted = 0;
                for (let i = 0; i < children.length; i++) {
                    const child = children[i];
                    if (!child.visible || child.implicitWidth <= 0) continue;
                    total += child.implicitWidth;
                    counted++;
                }
                return counted > 0 ? total + spacing * (counted - 1) : 0;
            }
            // On BOTH paths. The first fix handed the natural width over only
            // when the row had a label - the unlabelled row, which the Quick
            // page's Bar & Screen cards use (`Layout.fillWidth: false`,
            // right-aligned under a heading of their own), kept the circle,
            // and the same four chips latched one per line there once the
            // page was built across frames ("This broke again").
            Layout.preferredWidth: buttonsFlow.naturalWidth
            // An ALIGNED child is handed its preferred size and positioned,
            // never resized, so a row too narrow for its chips overflowed
            // rather than wrapping - the Quick page's Bar style card, once a
            // fifth style joined, drew its last chip past the card's edge
            // (measured: a 461px Flow in a 442px card). On the unlabelled path
            // the Flow FILLS its cell up to the natural width as a maximum: a
            // wider cell leaves it at the natural width, right-aligned, and a
            // narrower one gives it less, which is when the chips wrap for the
            // real reason. The labelled path keeps its aligned natural width -
            // the label beside it is what would yield, and it has no minimum.
            Layout.maximumWidth: root.text ? Number.POSITIVE_INFINITY : buttonsFlow.naturalWidth

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
