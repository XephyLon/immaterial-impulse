import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins.designsystem.services
import "../../common/functions/cavaBands.js" as CavaBands

Item {
    id: root
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool mirrored: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property list<real> points: CavaService.values
    property int barCount: 20
    property real dotSize: 3
    property real dotSpacing: Appearance.spacing.space50
    property real maxBarHeight: (vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.barHeight) * 0.7
    property real maxVisualizerValue: CavaService.maxValue

    // One reshape per spectrum rather than a nearest-index lookup per dot: the
    // producer emits more bands than this widget has dots, and picking one
    // index per dot threw away the ones in between.
    readonly property var levels: CavaBands.bands(root.points, root.barCount, root.maxVisualizerValue)
    // Temporal smoothing as one filter over the array per cava frame, not a
    // `Behavior on height` per dot: twenty NumberAnimations restarted sixty
    // times a second, twice over (the bar carries two of these), on the main
    // thread the sidebars' slide runs on. Same fix as the desktop widget's.
    // k = 0.55 at 60 frames/s is the 80ms the animation gave.
    property var displayed: []
    onLevelsChanged: {
        const target = root.levels, prev = root.displayed, next = new Array(target.length);
        for (let j = 0; j < target.length; j++) {
            const was = prev[j] ?? 0;
            next[j] = was + (target[j] - was) * 0.55;
        }
        root.displayed = next;
    }

    // A fullscreen window on this monitor covers the bar - Bar.qml:67 chooses
    // the Top layer precisely so that it does, except while a special workspace
    // sits on top, which puts the bar back on Overlay and in front. Mirrored
    // here rather than passed down because the visualiser is placed by the
    // layout registry, not by Bar.qml, so there is no parent to read it from.
    //
    // The bar is *occluded*, never hidden: its surface stays mapped and QML
    // keeps `visible` true, so nothing in the item tree knows. Gating this
    // claim on `visible` - the obvious guard - would therefore not fire at all.
    readonly property var thisMonitorData: HyprlandData.monitors.find(monitor =>
        monitor.name === root.QsWindow.window?.screen?.name)
    readonly property bool coveredByFullscreen:
        (HyprlandData.workspaceById[root.thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false)
        && ((root.thisMonitorData?.specialWorkspace?.name ?? "") === "")

    // This widget only exists while "visualizer" sits in a bar layout, which is
    // the layout term the old process gate spelled out by reading the config -
    // but existing is not enough on its own, because bands nobody can see still
    // animate at the refresh rate.
    CavaRef { active: !root.coveredByFullscreen }

    implicitWidth: vertical
        ? Appearance.sizes.verticalBarWidth
        : (isMaterial
            ? barsRow.implicitWidth + 16
            : barCount * (dotSize + dotSpacing))
    implicitHeight: vertical
        ? (isMaterial
            ? barsColumn.implicitHeight + 16
            : barCount * (dotSize + dotSpacing))
        : Appearance.sizes.barHeight

    transform: Scale {
        xScale: !root.vertical && root.mirrored ? -1 : 1
        origin.x: root.width / 2
    }


    Row {
        id: barsRow
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: root.dotSpacing

        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                width: root.dotSize
                property real pointValue: {
                    if (!root.isPlaying || root.points.length === 0) return root.dotSize
                    return Math.max(root.dotSize, (root.displayed[index] ?? 0) * root.maxBarHeight)
                }
                height: pointValue
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colPrimary
                opacity: root.isPlaying ? 0.85 : 0.3
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }
    }

    Column {
        id: barsColumn
        visible: root.vertical
        anchors.centerIn: parent
        spacing: root.dotSpacing

        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                height: root.dotSize
                property real pointValue: {
                    if (!root.isPlaying || root.points.length === 0) return root.dotSize
                    const rawIndex = root.mirrored ? (root.barCount - 1 - index) : index
                    return Math.max(root.dotSize, (root.displayed[rawIndex] ?? 0) * root.maxBarHeight)
                }
                width: pointValue
                radius: height / 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: Appearance.colors.colPrimary
                opacity: root.isPlaying ? 0.85 : 0.3
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }
    }
}