pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import ".."

Item {
    id: root
    property real numberSize: 80 * Appearance.effectiveScale
    property real margins: 10 * Appearance.effectiveScale
    property color color: Appearance.colors.colOnSecondaryContainer

    property real hourLineSize: 4 * Appearance.effectiveScale
    property real minuteLineSize: 2 * Appearance.effectiveScale
    property real hourLineLength: 18 * Appearance.effectiveScale
    property real minuteLineLength: 7 * Appearance.effectiveScale

    property int hours: 12
    property int minutes: 60

    // Full dial style hour lines
    Repeater {
        model: root.hours

        Item {
            required property int index
            rotation: 360 / root.hours * index
            anchors.fill: parent

            Rectangle {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: root.margins
                }
                implicitWidth: root.hourLineLength
                implicitHeight: root.hourLineSize
                radius: implicitWidth / 2
                color: root.color
            }
        }
    }

    // Minute lines
    Repeater {
        model: root.minutes

        Item {
            required property int index
            rotation: 360 / root.minutes * index 
            anchors.fill: parent

            Rectangle {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: root.margins
                }
                implicitWidth: root.minuteLineLength
                implicitHeight: root.minuteLineSize
                radius: implicitWidth / 2
                color: root.color
            }
        }
    }
}
