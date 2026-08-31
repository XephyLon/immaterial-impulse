import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    required property ListView target

    anchors {
        bottom: parent.bottom
        horizontalCenter: parent.horizontalCenter
        bottomMargin: Appearance.spacing.space150
    }

    // Distance, not atYEnd: the chase settles within a pixel of the end
    // and atYEnd's own margin math left the pill lingering there.
    readonly property bool farFromEnd: (target.originY + target.contentHeight
        + target.bottomMargin - target.height - target.contentY) > 8
    opacity: farFromEnd ? 1 : 0
    scale: farFromEnd ? 1 : 0.7
    visible: opacity > 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    implicitWidth: contentItem.implicitWidth + 8 * 2
    implicitHeight: contentItem.implicitHeight + 4 * 2

    colBackground: Appearance.colors.colSecondary
    colBackgroundHover: Appearance.colors.colSecondaryHover
    colRipple: Appearance.colors.colSecondaryActive
    buttonRadius: Appearance.rounding.verysmall

    downAction: () => {
        target.positionViewAtEnd()
    }

    contentItem: Row {
        id: contentItem
        spacing: Appearance.spacing.space50
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "arrow_downward"
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Scroll to Bottom")
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
    }
}
