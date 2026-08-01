import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    property bool hasEvent: false

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 36;
    implicitHeight: 36;

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small
    
    contentItem: StyledText {
        anchors.fill: parent
        text: day
        horizontalAlignment: Text.AlignHCenter
        font.weight: bold ? Font.DemiBold : Font.Normal
        color: (isToday == 1) ? Appearance.m3colors.m3onPrimary : 
            (isToday == 0) ? Appearance.colors.colOnLayer1 : 
            Appearance.colors.colOutlineVariant

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    // "Has events" indicator: a small dot under the day number.
    Rectangle {
        visible: button.hasEvent
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Appearance.spacing.space50
        implicitWidth: Appearance.spacing.space50
        implicitHeight: Appearance.spacing.space50
        radius: Appearance.rounding.full
        color: (button.isToday == 1) ? Appearance.m3colors.m3onPrimary : Appearance.colors.colPrimary
    }
}

