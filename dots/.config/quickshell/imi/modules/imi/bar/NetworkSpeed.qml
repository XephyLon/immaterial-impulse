import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import "network_speed.js" as Net

MouseArea {
    id: root

    property bool vertical: false
    // The logic lives in network_speed.js (parser, sample state, label) so
    // it is testable without the bar - tests/tst_network_speed.qml. This
    // file owns the FileView, the poll and the state object.
    property var sampleState: Net.initialState()
    readonly property real downloadBytesPerSecond: root.sampleState.downloadBytesPerSecond
    readonly property real uploadBytesPerSecond: root.sampleState.uploadBytesPerSecond
    readonly property real downloadedBytes: root.sampleState.downloadedBytes
    readonly property real uploadedBytes: root.sampleState.uploadedBytes

    implicitWidth: vertical ? 36 : speedColumn.implicitWidth + 8
    implicitHeight: vertical ? speedColumn.implicitHeight + 6 : 32

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    function formatRate(rate, compact) {
        return Net.formatRate(rate, compact)
    }

    function updateRate(contents) {
        const totals = Net.parseProcNetDev(contents)
        root.sampleState = Net.advance(root.sampleState, totals.rx, totals.tx, Date.now())
    }

    FileView {
        id: networkStats
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: root.updateRate(text())
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: networkStats.reload()
    }

    TextMetrics {
        id: regularRateMetrics
        text: "999.9 MB/s"
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Medium
    }

    component SpeedLine: RowLayout {
        id: speedLine

        required property string iconName
        required property real rate
        required property color accentColor

        readonly property string rateText: root.formatRate(rate, root.vertical)

        spacing: root.vertical ? Appearance.spacing.space25 : Appearance.spacing.space50

        MaterialSymbol {
            text: speedLine.iconName
            iconSize: root.vertical
                ? Appearance.font.pixelSize.smallest
                : Appearance.font.pixelSize.smaller
            color: speedLine.accentColor
            opacity: speedLine.rate > 0 ? 1 : 0.45

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.preferredWidth: root.vertical ? -1 : regularRateMetrics.width
            horizontalAlignment: Text.AlignRight
            text: speedLine.rateText
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    ColumnLayout {
        id: speedColumn
        anchors.centerIn: parent
        spacing: -Appearance.spacing.space50

        SpeedLine {
            iconName: "arrow_upward"
            rate: root.uploadBytesPerSecond
            accentColor: Appearance.colors.colTertiary
        }

        SpeedLine {
            iconName: "arrow_downward"
            rate: root.downloadBytesPerSecond
            accentColor: Appearance.colors.colPrimary
        }
    }

    NetworkSpeedPopup {
        hoverTarget: root
        downloadSpeed: root.downloadBytesPerSecond
        uploadSpeed: root.uploadBytesPerSecond
        downloadedBytes: root.downloadedBytes
        uploadedBytes: root.uploadedBytes
    }
}
