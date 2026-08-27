pragma ComponentBehavior: Bound
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

Item {
    id: root

    // The index this bar DRAWS as current. A plain property the call site binds
    // to whatever owns the selection (the left sidebar's SwipeView), and that
    // this widget never writes: a control that assigns to its own bound
    // property destroys the binding and then shows local state for the rest of
    // the session - #158's defect, and the reason ConfigSwitch answers a click
    // with an intent. A click here is the same thing, `currentIndexRequested`,
    // and the call site moves the source.
    property int currentIndex: 0
    signal currentIndexRequested(int index)

    required property var tabButtonList
    function incrementCurrentIndex() { root.currentIndexRequested(root.currentIndex + 1) }
    function decrementCurrentIndex() { root.currentIndexRequested(root.currentIndex - 1) }
    function setCurrentIndex(index)  { root.currentIndexRequested(index) }

    property real cardHeight: 30
    property bool expanded: false

    implicitHeight: expanded 
        ? tabButtonList.length * (cardHeight + 2)
        : cardHeight

    Behavior on implicitHeight {
        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
    }

    Repeater {
        model: root.tabButtonList
        delegate: Rectangle {
            required property int index
            required property var modelData
            property bool isCurrent: index === root.currentIndex
            property int totalCount: root.tabButtonList.length

            property int visualPosition: {
                if (isCurrent) return totalCount - 1
                const slots = Array.from({length: totalCount}, (_, i) => i).filter(i => i !== root.currentIndex)
                return slots.indexOf(index)
            }

            visible: isCurrent || root.expanded
            width: root.width
            height: 30

            y: root.expanded 
                ? visualPosition * (cardHeight + 2)
                : isCurrent ? 0 : 0

            z: isCurrent ? 0 : (totalCount - visualPosition)

            topLeftRadius: Appearance.rounding.normal
            topRightRadius: Appearance.rounding.normal
            bottomLeftRadius: isCurrent ? 0 : Appearance.rounding.unsharpenmore
            bottomRightRadius: isCurrent ? 0 : Appearance.rounding.unsharpenmore

            color: isCurrent
                ? Appearance.colors.colLayer1
                : Appearance.colors.colPrimaryContainer

            opacity: isCurrent ? 1 : (0.3 + ((totalCount - 1 - visualPosition) / Math.max(totalCount - 1, 1)) * 0.3)

            Behavior on y {
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
            }

            Rectangle {
                visible: isCurrent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.spacing.space150
                width: 30
                height: 4
                radius: height / 2
                color: Appearance.colors.colSurfaceContainerHighest
                opacity: 0.6
            }

            RowLayout {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Appearance.spacing.space150
                spacing: Appearance.spacing.space100

                MaterialSymbol {
                    text: parent.parent.modelData.icon
                    iconSize: Appearance.font.pixelSize.larger
                    color: parent.parent.isCurrent
                        ? Appearance.colors.colOnLayer1
                        : Appearance.colors.colOnPrimaryContainer
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }

                StyledText {
                    text: parent.parent.modelData.name
                    color: parent.parent.isCurrent
                        ? Appearance.colors.colOnLayer1
                        : Appearance.colors.colOnPrimaryContainer
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    if (!root.expanded) {
                        root.expanded = true
                        return
                    }
                    root.setCurrentIndex(parent.index)
                }
            }

            DragHandler {
                id: dragHandler
                enabled: isCurrent
                target: null
                onTranslationChanged: {
                    if (translation.y < -20) {
                        root.expanded = false
                    } else if (translation.y > 20) {
                        root.expanded = true
                    }
                }
            }
        }
    }
}