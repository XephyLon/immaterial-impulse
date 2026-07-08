import QtQuick
import qs.modules.common

Item {
    property bool vertical: Config.options.bar.vertical
    property real btnSize: 40
    property real btnSpacing: 2
    property bool isMaterial: Config.options.bar.cornerStyle === 3

    width:  vertical ? btnSize : (1 + btnSpacing * 3)
    height: vertical ? (1 + btnSpacing * 3) : btnSize

    Rectangle {
        anchors.centerIn: parent
        width:  vertical ? Math.round(btnSize * 0.6) : 1
        height: vertical ? 1 : Math.round(btnSize * 0.6)
        color:  isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
    }
}