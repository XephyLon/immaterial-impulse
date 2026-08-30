pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ComboBox {
    id: root

    property string buttonIcon: ""
    property real buttonRadius: height / 2
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    implicitHeight: 40
    Layout.fillWidth: true

    // The lift is applied to the three PARTS - background, content, arrow -
    // and never to the ComboBox itself. The popup is positioned by mapping
    // through its parent's transform, so a Scale on the root put the list
    // where the shrunken button was at the instant of release and left it
    // there ("a strange displacement of the collapsed menu"). Each part
    // scales about the control's centre, so the three read as one lift.
    component Lift: Scale {
        required property Item part
        origin.x: root.width / 2 - part.x
        origin.y: root.height / 2 - part.y
        xScale: surface.interactionMotion.scale
        yScale: surface.interactionMotion.scale
    }

    // Where the pointer is, for the ripple's origin. The ComboBox reports
    // that it is pressed, not where; the hover point at that instant is it.
    HoverHandler {
        id: pointer
        cursorShape: Qt.PointingHandCursor
    }

    background: PassiveRippleSurface {
        id: surface
        transform: Lift { part: surface }
        buttonRadius: root.buttonRadius
        colBackground: root.colBackground
        colBackgroundHover: root.colBackgroundHover
        colRipple: root.colBackgroundActive
        hostHovered: root.hovered
        // `down` also holds while the popup is open; the press is the moment.
        hostDown: root.pressed
        hostPressPoint: pointer.point.position
    }

    indicator: MaterialSymbol {
        id: arrow
        x: root.width - width - 16
        y: root.height / 2 - height / 2
        transform: Lift { part: arrow }
        text: "keyboard_arrow_down"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnSecondaryContainer

        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    contentItem: Item {
        id: content
        implicitWidth: buttonLayout.implicitWidth
        implicitHeight: buttonLayout.implicitHeight
        transform: Lift { part: content }

        RowLayout {
            id: buttonLayout
            anchors.fill: parent
            spacing: Appearance.spacing.space100
            anchors.leftMargin: Appearance.spacing.space200
            anchors.rightMargin: Appearance.spacing.space200

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.buttonIcon.length > 0 || !!(root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon)
                visible: active
                sourceComponent: MaterialSymbol {
                    text: {
                        if (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon) {
                            return root.model[root.currentIndex].icon;
                        }
                        return root.buttonIcon;
                    }
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                id: buttonLabel
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnSecondaryContainer
                text: root.displayText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: false
        alternativeVisibleCondition: root.hovered && buttonLabel.truncated
        delay: 0
        text: buttonLabel.text
    }

    delegate: ItemDelegate {
        id: itemDelegate
        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: 40

        required property var model
        required property int index
        readonly property bool chosen: root.currentIndex === itemDelegate.index
        property color colText: itemDelegate.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

        transform: Scale {
            origin.x: itemDelegate.width / 2
            origin.y: itemDelegate.height / 2
            xScale: rowSurface.interactionMotion.scale
            yScale: rowSurface.interactionMotion.scale
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        background: PassiveRippleSurface {
            id: rowSurface
            buttonRadius: Appearance.rounding.small
            colBackground: itemDelegate.chosen
                ? Appearance.colors.colSecondaryContainer
                : ColorUtils.transparentize(Appearance.colors.colLayer3)
            colBackgroundHover: itemDelegate.chosen
                ? Appearance.colors.colSecondaryContainerHover
                : Appearance.colors.colLayer3Hover
            colRipple: itemDelegate.chosen
                ? Appearance.colors.colSecondaryContainerActive
                : Appearance.colors.colLayer3Active
            hostHovered: itemDelegate.hovered
            hostDown: itemDelegate.down
            hostPressPoint: Qt.point(itemDelegate.pressX, itemDelegate.pressY)
        }

        contentItem: RowLayout {
            spacing: Appearance.spacing.space100
            anchors.leftMargin: Appearance.spacing.space150
            anchors.rightMargin: Appearance.spacing.space150

            Loader {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Appearance.font.pixelSize.larger
                active: typeof itemDelegate.model === 'object' && itemDelegate.model?.icon?.length > 0
                visible: active

                sourceComponent: Item {
                    implicitWidth: icon.implicitWidth
                    implicitHeight: Appearance.font.pixelSize.larger

                    MaterialSymbol {
                        id: icon
                        anchors.centerIn: parent
                        text: itemDelegate.model?.icon ?? ""
                        iconSize: Appearance.font.pixelSize.larger
                        color: itemDelegate.colText
                    }
                }
            }

            StyledText {
                id: label
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.larger
                color: itemDelegate.colText
                text: itemDelegate.model[root.textRole]
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: itemDelegate.hovered && label.truncated
            delay: 0
            text: label.text
        }
    }

    popup: Popup {
        y: root.height + 4
        width: root.width
        height: Math.min(listView.contentHeight + topPadding + bottomPadding, 300)
        padding: Appearance.spacing.space100

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        exit: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: StyledListView {
            id: listView
            clip: true
            implicitHeight: contentHeight
            spacing: Appearance.spacing.space25
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
        }
    }
}
