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
    // The diagonal ripple, the sibling fork's calendar entrance: each cell
    // arrives (row + col) * 28ms after the trigger, so the month sweeps in
    // from the top-left corner. Channel discipline: the cell is a
    // RippleButton, so the entrance is spoken entirely through `appear` -
    // the one seam the control folds into its own opacity and rise - never
    // through opacity or scale, which the interaction model owns. Header
    // cells pass no grid position and stay inert.
    property int gridRow: -1
    property int gridCol: -1
    property int entranceKey: 0
    onEntranceKeyChanged: {
        if (gridRow < 0 || gridCol < 0)
            return;
        cellRipple.stop();
        button.appear = 0;
        cellRipple.start();
    }
    SequentialAnimation {
        id: cellRipple
        PauseAnimation {
            duration: Appearance.animation.scale((Math.max(0, button.gridRow) + Math.max(0, button.gridCol)) * 28)
        }
        NumberAnimation {
            target: button
            property: "appear"
            from: 0
            to: 1
            duration: Appearance.animation.scale(220)
            easing.type: Easing.OutCubic
        }
    }

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

