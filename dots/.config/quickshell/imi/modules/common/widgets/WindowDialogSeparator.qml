import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    // The rule runs the full width of the CARD, so it cancels exactly the
    // padding the dialog holds its content in - published on the content
    // column this is always a direct child of. It read
    // `Appearance.rounding.large` while that padding happened to be the
    // corner radius; the two are separate now and only one of them is a
    // spacing decision. The fallback is never drawn in this tree - a
    // separator outside a dialog stops at the content box rather than
    // reaching for a number it cannot know.
    readonly property real cardBleed: parent?.contentPadding ?? 0

    implicitHeight: 1
    color: Appearance.colors.colOutline
    Layout.fillWidth: true
    Layout.leftMargin: -cardBleed
    Layout.rightMargin: -cardBleed
    Layout.topMargin: -Appearance.spacing.space100
    Layout.bottomMargin: -Appearance.spacing.space100
}
