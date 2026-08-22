import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One entry in a catalogue, drawn: a leading icon, a name, a description under
 * it, and whatever affordance says what happens if you act on the entry.
 *
 * Four surfaces had spelled that out by hand - Edit Mode's drawer five times
 * over (desktop widgets, bar widgets, dock apps, the lock islands, the lock
 * layout row), `ConfigSwitch` for every settings row in the shell, and the
 * plugin store's cards - and they had already drifted: the same plugin's
 * description elided in one, wrapped in another and was absent from the third,
 * and the byline sat on the title's line in one place and under it in another.
 *
 * ---- this component is not interactive, deliberately --------------------
 *
 * It has no `MouseArea`, no `Button` root and no hover state, because the
 * three surfaces cannot agree on one and must not be forced to. Edit Mode's
 * drawer rows are pointer areas BY CONSTRUCTION (65602708e): dragging a widget
 * out of the clipped drawer needs the implicit grab of the press to keep
 * delivering events after the pointer has left the row, which a control that
 * hands its press to a `Button` does not preserve - and `test_edit_mode_
 * contract.py` names the drawer as the deliberate exception to its
 * no-`MouseArea` sweep for exactly that reason. Everything else here is a
 * `RippleButton`. So the interactive surface stays with the call site and this
 * draws inside it.
 *
 * ---- what decides the row's height --------------------------------------
 *
 * Its labels and its affordance, never its leading glyph: the icon sits in a
 * wrapper that reports width only, so a decorative 23px glyph cannot stretch a
 * list of rows whose text is 15px. That is `OptionalMaterialSymbol`'s own
 * shape, kept rather than repaired, because every settings row in the shell is
 * already sized that way.
 */
ColumnLayout {
    id: root

    // The leading glyph. Empty draws no icon at all (and takes no width),
    // which is what a settings row with no `buttonIcon` wants.
    property string rowIcon: ""
    property real rowIconSize: Appearance.font.pixelSize.larger
    property color rowIconColor: Appearance.colors.colOnSecondaryContainer
    // The escape hatch for a leading visual that is not a Material Symbol -
    // a dock app's own icon is an `Image`. Set, it replaces the glyph; the
    // component is centred in the same width-only wrapper.
    property Component iconComponent: null

    property string title: ""
    property alias titleFont: titleLabel.font
    property color titleColor: Appearance.colors.colOnSecondaryContainer
    // A title that must fit its row fills the width and elides; one that is
    // followed by `titleContent` on the same line does not, or the byline is
    // pushed to the far edge. The two are exclusive, so it is one flag.
    property bool titleElides: false

    property string description: ""
    property alias descriptionFont: descriptionLabel.font
    property color descriptionColor: Appearance.colors.colSubtext
    // Wrapping is right where the row grows to fit (a settings page, a store
    // card) and wrong in a fixed-height list, where the second line is simply
    // clipped.
    property bool descriptionWraps: true

    // Shown as a hoverable "i" beside the row rather than inline, so a long
    // explanation does not stretch it.
    property string infoText: ""

    // On the title's own line, immediately after it: a byline, a version.
    property alias titleContent: titleRow.data
    // Before the affordance: row actions. Anything a call site appends to its
    // own row would otherwise land beyond the affordance.
    property alias trailingContent: trailingRow.data
    // The row's terminal control - the switch, the add/remove glyph, the
    // store's Install button. Separate from `trailingContent` so a component
    // built on this can own one while still offering the other to ITS callers.
    property alias affordance: affordanceRow.data
    // A full-width row beneath everything else: tags, badges. It spans the
    // whole row rather than the label block, so a call site can push trailing
    // items to the same right edge the affordance sits on.
    property alias detailContent: detailRow.data

    property real rowSpacing: Appearance.spacing.space150

    spacing: 0

    // Nothing in here dims itself on `enabled`. Every call site is inside a
    // control that already applies the disabled opacity to the whole thing,
    // and a second binding multiplies rather than replaces it (0.4 * 0.4 =
    // 0.16) - tests/lint_disabled_opacity.py holds the line.

    Component {
        id: glyphIcon
        Item {
            implicitWidth: glyph.implicitWidth
            MaterialSymbol {
                id: glyph
                anchors.centerIn: parent
                text: root.rowIcon
                iconSize: root.rowIconSize
                color: root.rowIconColor
            }
        }
    }

    Component {
        id: customIcon
        Item {
            implicitWidth: customIconLoader.implicitWidth
            Loader {
                id: customIconLoader
                anchors.centerIn: parent
                sourceComponent: root.iconComponent
            }
        }
    }

    RowLayout {
        id: mainRow
        Layout.fillWidth: true
        // A Layout nested in a Layout defaults to fillHeight TRUE, so the two
        // rows here would SPLIT any height the row is given beyond its
        // implicit one - which is exactly what a fixed-height list row hands
        // it. Stated on both, never inherited: the main row takes the slack
        // and stays centred, the detail row takes what it needs.
        Layout.fillHeight: true
        spacing: root.rowSpacing

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.iconComponent !== null || root.rowIcon.length > 0
            visible: active
            sourceComponent: root.iconComponent !== null ? customIcon : glyphIcon
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                StyledText {
                    id: titleLabel
                    Layout.fillWidth: root.titleElides
                    text: root.title
                    textFormat: Text.PlainText
                    color: root.titleColor
                    elide: root.titleElides ? Text.ElideRight : Text.ElideNone
                }
                RowLayout {
                    id: titleRow
                    Layout.alignment: Qt.AlignBaseline
                    spacing: Appearance.spacing.space50
                }
                // Keeps the title left-aligned when it is not the thing that
                // fills the line itself.
                Item {
                    visible: !root.titleElides
                    Layout.fillWidth: !root.titleElides
                }
            }

            StyledText {
                id: descriptionLabel
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.descriptionColor
                wrapMode: root.descriptionWraps ? Text.Wrap : Text.NoWrap
                elide: root.descriptionWraps ? Text.ElideNone : Text.ElideRight
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

        RowLayout {
            id: affordanceRow
            Layout.alignment: Qt.AlignVCenter
            spacing: Appearance.spacing.space50
        }
    }

    RowLayout {
        id: detailRow
        Layout.fillWidth: true
        Layout.fillHeight: false
        // Only when the slot is actually filled, so a row that leaves it empty
        // keeps its height exactly.
        Layout.topMargin: detailRow.children.length > 0
            ? Appearance.spacing.space100 : 0
        spacing: Appearance.spacing.space50
    }
}
