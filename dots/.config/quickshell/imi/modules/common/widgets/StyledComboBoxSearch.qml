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
    property string searchText: ""

    property int visibleCount: {
        if (!root.searchText || root.searchText.length === 0) 
            return root.model?.length ?? 0
        return (root.model ?? []).filter(item => {
            const display = typeof item === "object" ? (item[root.textRole] ?? "") : String(item)
            return display.toLowerCase().includes(root.searchText.toLowerCase())
        }).length
    }

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
                active: root.buttonIcon.length > 0 || (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon)
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
        implicitHeight: visible ? 40 : 0
        visible: {
            if (!root.searchText || root.searchText.length === 0) return true
            const display = typeof model === "object" ? (model[root.textRole] ?? "") : String(model)
            return display.toLowerCase().includes(root.searchText.toLowerCase())
        }

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
        clip: true
        height: Math.min(
            searchField.implicitHeight + 20 + (visibleCount * 42) + topPadding + bottomPadding,
            320
        )
        padding: Appearance.spacing.space100

        onVisibleChanged: {
            if (visible) {
                searchField.forceActiveFocus()
            } else {
                root.searchText = ""
                searchField.text = ""
            }
        }

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        exit: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow { target: popupBackground }
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            spacing: Appearance.spacing.space50

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchField.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Appearance.spacing.space50
                    spacing: Appearance.spacing.space100

                    MaterialSymbol {
                        Layout.leftMargin: Appearance.spacing.space100
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search..."
                        color: Appearance.colors.colOnLayer1
                        background: null
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        onTextChanged: root.searchText = text
                        Keys.onDownPressed: listView.incrementCurrentIndex()
                        Keys.onUpPressed: listView.decrementCurrentIndex()
                        Keys.onReturnPressed: {
                            if (listView.currentIndex >= 0) {
                                root.currentIndex = listView.currentIndex
                                root.popup.close()
                            }
                        }
                    }

                    MaterialSymbol {
                        visible: searchField.text.length > 0
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                        Layout.rightMargin: Appearance.spacing.space100
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            StyledListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 320 - searchField.implicitHeight - 8 - 46)
                clip: true
                spacing: Appearance.spacing.space25
                model: root.popup.visible ? root.delegateModel : null
                currentIndex: root.highlightedIndex
            }
        }
    }
}