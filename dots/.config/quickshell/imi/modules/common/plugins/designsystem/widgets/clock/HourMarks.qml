pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import ".."

Item {
    id: root
    property real implicitSize: 135 * Appearance.effectiveScale
    property real markLength: 12 * Appearance.effectiveScale
    property real markWidth: 4 * Appearance.effectiveScale
    property color color: Appearance.colors.colOnSecondaryContainer
    property color colOnBackground: Appearance.colors.colSecondaryContainer
    property real padding: 8 * Appearance.effectiveScale

    Rectangle {
        color: root.color
        anchors.centerIn: parent
        implicitWidth: root.implicitSize
        implicitHeight: root.implicitSize
        radius: width / 2

        // Hour mark lines
        Repeater {
            model: 12

            Item {
                required property int index
                anchors.fill: parent
                rotation: 360 / 12 * index 

                Rectangle {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: root.padding
                    }
                    implicitWidth: root.markLength
                    implicitHeight: root.markWidth

                    radius: width / 2
                    color: root.colOnBackground
                }
            }
        }
    }

}
