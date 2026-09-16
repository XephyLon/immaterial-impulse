import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A settings row that states something and offers an action: a glyph on
 * the row inset, body text that wraps, and whatever is declared inside on
 * the right (a DialogButton, a RippleButtonWithIcon, a count). The
 * text-and-action rows in Accounts, Modes & Routines and Services had the
 * same preamble ten times over.
 *
 * `rowVisible`, not `visible`, is how a GroupedList row comes and goes.
 */
RowLayout {
    id: root

    property string icon: ""
    property string text: ""
    property bool rowVisible: true
    default property alias actions: trailing.data

    spacing: Appearance.spacing.space200

    MaterialSymbol {
        Layout.leftMargin: Appearance.spacing.space100
        visible: root.icon.length > 0
        text: root.icon
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnLayer1
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.text
        color: Appearance.colors.colOnLayer1
    }

    RowLayout {
        id: trailing
        Layout.rightMargin: Appearance.spacing.space100
        spacing: Appearance.spacing.space100
    }
}
