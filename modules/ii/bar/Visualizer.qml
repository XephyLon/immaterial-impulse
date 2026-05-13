import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property list<real> points: GlobalStates.visualizerPoints

    property int barCount: 20
    property real dotSize: 3
    property real dotSpacing: 3
    property real maxBarHeight: Appearance.sizes.barHeight * 0.7
    property real maxVisualizerValue: 1000

    implicitWidth: vertical
        ? Appearance.sizes.verticalBarWidth
        : (barCount * (dotSize + dotSpacing))
    implicitHeight: Appearance.sizes.barHeight

    Row {
        anchors.centerIn: parent
        spacing: root.dotSpacing

        Repeater {
            model: root.barCount

            Rectangle {
                id: dot
                required property int index
                width: root.dotSize
                property real pointValue: {
                    if (!root.isPlaying || root.points.length === 0) return root.dotSize
                    const idx = Math.floor(index * root.points.length / root.barCount)
                    const v = root.points[idx] ?? 0
                    return Math.max(root.dotSize, (v / root.maxVisualizerValue) * root.maxBarHeight)
                }
                height: pointValue
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colPrimary
                opacity: root.isPlaying ? 0.85 : 0.3

                Behavior on height {
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 300 }
                }
            }
        }
    }
}