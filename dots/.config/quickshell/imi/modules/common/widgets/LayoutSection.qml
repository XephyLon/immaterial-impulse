import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "../functions/layout_ops.js" as LayoutOps

ContentSubsection {
    id: root

    property string sectionTitle
    property var layout
    property var getWidgetName: (id) => id
    property var availableWidgets: []
    property var onUpdate: (list) => {}

    title: sectionTitle
    Layout.fillWidth: true
    Layout.leftMargin: Appearance.spacing.space100
    Layout.topMargin: -Appearance.spacing.space50

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space25

        Item {
            Layout.fillWidth: true
            implicitHeight: itemFlow.implicitHeight

            Flow {
                id: itemFlow
                anchors.fill: parent
                spacing: Appearance.spacing.space25

                Repeater {
                    id: itemRepeater
                    model: root.layout

                    delegate: SelectionGroupButton {
                        required property var modelData
                        required property int index
                        isDragging: dragHandler.active
                        leftmost: true; rightmost: true
                        buttonIcon: "close"
                        buttonText: root.getWidgetName(modelData)
                        toggled: !dragHandler.active

                        DragHandler {
                            id: dragHandler
                            target: null

                            // The dragged chip's own slot is a hole rather than
                            // a candidate: it is still laid out where it
                            // started, so it would be its own nearest for most
                            // of the gesture.
                            function slotCentres() {
                                const centres = []
                                for (let i = 0; i < itemRepeater.count; i++) {
                                    const child = i === index ? null : itemRepeater.itemAt(i)
                                    centres.push(child
                                        ? child.mapToItem(null, child.width / 2, child.height / 2)
                                        : null)
                                }
                                return centres
                            }

                            function findNewIndex(dragX, dragY) {
                                const nearest = LayoutOps.indexAt(
                                    slotCentres(), Qt.point(dragX, dragY), null)
                                return nearest === -1 ? index : nearest
                            }

                            onActiveChanged: {
                                if (!active) {
                                    dropIndicator.visible = false
                                    dropIndicator.targetIndex = -1
                                    const dragX = dragHandler.centroid.scenePosition.x
                                    const dragY = dragHandler.centroid.scenePosition.y
                                    const newIndex = findNewIndex(dragX, dragY)
                                    if (newIndex !== index)
                                        root.onUpdate(LayoutOps.move(root.layout, index, newIndex))
                                }
                            }

                            onCentroidChanged: {
                                if (!active) return
                                const dragX = dragHandler.centroid.scenePosition.x
                                const dragY = dragHandler.centroid.scenePosition.y
                                const newIndex = findNewIndex(dragX, dragY)

                                if (newIndex !== index) {
                                    const refChild = itemRepeater.itemAt(newIndex)
                                    if (refChild) {
                                        const refLocal = refChild.mapToItem(itemFlow, 0, 0)
                                        dropIndicator.x = newIndex < index
                                            ? refLocal.x - 5
                                            : refLocal.x + refChild.width + 1
                                        dropIndicator.y = refLocal.y
                                        dropIndicator.height = refChild.height
                                        dropIndicator.visible = true
                                        dropIndicator.targetIndex = newIndex
                                    }
                                } else {
                                    dropIndicator.visible = false
                                    dropIndicator.targetIndex = -1
                                }
                            }
                        }

                        onClicked: root.onUpdate(LayoutOps.remove(root.layout, index))
                    }
                }
            }

            Rectangle {
                id: dropIndicator
                property int targetIndex: -1
                visible: false
                width: 3
                height: 32 
                radius: Appearance.rounding.unsharpen
                color: Appearance.colors.colPrimary

                Behavior on x { NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration } }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: -Appearance.spacing.space50
                    width: 8; height: 8; radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -Appearance.spacing.space50
                    width: 8; height: 8; radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                }
            }
        }

        ToolbarPairedFab {
            Layout.rightMargin: Appearance.spacing.space100
            Layout.topMargin: -Appearance.spacing.space250
            Layout.alignment: Qt.AlignVCenter
            iconText: dropdown.dropdownOpen ? "keyboard_arrow_up" : "add"
            onClicked: dropdown.dropdownOpen = !dropdown.dropdownOpen
        }
    }

    Item {
        id: dropdown
        Layout.fillWidth: true
        Layout.topMargin: Appearance.spacing.space100
        visible: implicitHeight > 0
        implicitHeight: dropdownOpen ? dropdownRect.implicitHeight + 8 : 0
        opacity: dropdownOpen ? 1 : 0
        clip: true

        property bool dropdownOpen: false

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: dropdownRect
            anchors.top: parent.top
            anchors.topMargin: Appearance.spacing.space50
            width: parent.width
            implicitHeight: dropdownFlow.implicitHeight + Appearance.spacing.space100
            color: "transparent"
            radius: Appearance.rounding.large

            Flow {
                id: dropdownFlow
                anchors { fill: parent; margins: Appearance.spacing.space100 }
                spacing: Appearance.spacing.space25
                Repeater {
                    model: root.availableWidgets
                    delegate: SelectionGroupButton {
                        required property var modelData
                        leftmost: true; rightmost: true
                        buttonText: modelData.name
                        buttonIcon: modelData.icon ?? ""  
                        onClicked: {
                            root.onUpdate(LayoutOps.insert(
                                root.layout, modelData.id, root.layout.length))
                            const keepOpen = ["visualizer", "divisor"]
                            if (!keepOpen.includes(modelData.id)) {
                                Qt.callLater(() => { dropdown.dropdownOpen = false })
                            }
                        }
                    }
                }
                StyledText {
                    visible: root.availableWidgets.length === 0
                    text: Translation.tr("No widgets available")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }
}
