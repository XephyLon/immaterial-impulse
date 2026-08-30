import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.quickToggles
import QtQuick

/**
 * The classic style's tile, drawn from a QuickToggleModel.
 *
 * The model is what a toggle IS - its icon, its state, its actions, its
 * tooltip - and the Android style has read it since the models existed.
 * The classic style kept eleven files that re-derived the same things by
 * hand from the services, and they had already started to disagree (Game
 * mode went through hyprctl here and through HyprlandConfig there). One
 * model, two renderings.
 *
 * A right-click is `altAction`; a panel that opens a dialog for the toggle
 * binds it to that, the way the Android panel answers `openMenu`.
 */
GroupButton {
    id: button
    property QuickToggleModel toggleModel: null
    property string buttonIcon: toggleModel?.icon ?? ""

    baseWidth: 40
    baseHeight: 40
    clickedWidth: baseWidth + 20
    toggled: toggleModel?.toggled ?? false
    visible: toggleModel?.available ?? true
    altAction: toggleModel?.altAction ?? null
    buttonRadius: (altAction && toggled) ? Appearance?.rounding.normal : Math.min(baseHeight, baseWidth) / 2
    buttonRadiusPressed: Appearance?.rounding?.small

    // A model with no main action (Phone Connect) opens its menu on the
    // left click too; that is what the classic tile did.
    onClicked: {
        if (!button.toggleModel) return;
        if (button.toggleModel.mainAction) button.toggleModel.mainAction();
        else if (button.altAction) button.altAction();
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        iconSize: 22
        fill: toggled ? 1 : 0
        color: toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: buttonIcon
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    StyledToolTip {
        extraVisibleCondition: (button.toggleModel?.tooltipText ?? "").length > 0
        text: button.toggleModel?.tooltipText ?? ""
    }
}
