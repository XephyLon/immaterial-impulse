import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

StyledPopup {
    id: root
    property var today: new Date()
    readonly property var pendingTodos: Todo.list.filter(todo => !todo.done)

    Item {
        implicitWidth: 340
        implicitHeight: 248

        StyledText {
            id: monthLabel
            anchors {
                left: parent.left
                top: parent.top
            }
            text: Qt.locale().toString(root.today, "MMMM")
            font.pixelSize: Appearance.font.pixelSize.huge
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            anchors {
                left: monthLabel.right
                leftMargin: Appearance.spacing.space100
                baseline: monthLabel.baseline
            }
            text: Qt.locale().toString(root.today, "yyyy")
            font.pixelSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnSurfaceVariant
        }

        Row {
            id: weekRow
            anchors {
                left: parent.left
                right: parent.right
                top: monthLabel.bottom
                topMargin: Appearance.spacing.space100
            }
            spacing: Appearance.spacing.space50

            Repeater {
                model: 7

                delegate: Rectangle {
                    required property int index
                    readonly property var date: {
                        const value = new Date(root.today)
                        value.setDate(root.today.getDate() - root.today.getDay() + index)
                        return value
                    }
                    readonly property bool isToday: date.toDateString() === root.today.toDateString()
                    width: (weekRow.width - weekRow.spacing * 6) / 7
                    height: 58
                    radius: Appearance.rounding.normal
                    color: isToday
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colSurfaceContainerHigh

                    StyledText {
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            top: parent.top
                            topMargin: Appearance.spacing.space75
                        }
                        text: Qt.locale().toString(parent.date, "ddd").slice(0, 2)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: parent.isToday ? Font.Bold : Font.Normal
                        color: parent.isToday
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            bottom: parent.bottom
                            bottomMargin: Appearance.spacing.space75
                        }
                        text: parent.date.getDate()
                        font.pixelSize: parent.isToday
                            ? Appearance.font.pixelSize.normal
                            : Appearance.font.pixelSize.small
                        font.weight: parent.isToday ? Font.Bold : Font.Normal
                        color: parent.isToday
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        Item {
            id: taskSection
            anchors {
                left: parent.left
                right: parent.right
                top: weekRow.bottom
                topMargin: Appearance.spacing.space100
            }
            height: 84

            Item {
                id: taskSummary
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: 56

                MaterialShapeWrappedMaterialSymbol {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                    }
                    shape: MaterialShape.Shape.Clover4Leaf
                    text: "checklist"
                    iconSize: Appearance.font.pixelSize.large
                    implicitSize: 36
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colPrimary
                }

                StyledText {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                    }
                    text: root.pendingTodos.length
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                }
            }

            Item {
                id: taskCards
                anchors {
                    left: taskSummary.right
                    leftMargin: Appearance.spacing.space100
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }

                Repeater {
                    model: Math.min(2, root.pendingTodos.length)

                    delegate: Rectangle {
                        required property int index
                        width: taskCards.width
                        height: 38
                        y: index * (height + Appearance.spacing.space50)
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colSurfaceContainerHigh

                        StyledText {
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: Appearance.spacing.space150
                                rightMargin: Appearance.spacing.space150
                                verticalCenter: parent.verticalCenter
                            }
                            text: `    ${root.pendingTodos[root.pendingTodos.length - 1 - index].content} `
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.pendingTodos.length === 0
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerHigh

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("No pending tasks")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        StyledText {
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            text: Translation.tr("%1 pending tasks").arg(root.pendingTodos.length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            text: Translation.tr("Uptime %1").arg(DateTime.uptime)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
