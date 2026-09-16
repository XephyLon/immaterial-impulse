import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Dynamic-island-style bar pill mirroring the sidebar pomodoro/stopwatch.
// Only visible while a timer is running; clicking opens the right sidebar
// (where the full pomodoro/stopwatch controls live). Pomodoro takes priority
// when both run.
MouseArea {
    id: root

    property bool vertical: false

    readonly property bool pomodoro: TimerService.pomodoroRunning
    readonly property bool stopwatch: TimerService.stopwatchRunning && !pomodoro
    readonly property bool shown: pomodoro || stopwatch

    // Vivid accent fill with its matching on-color. Use the BASE primary/secondary
    // pair (not the *container* variants) - the base pair is M3's high-contrast
    // pairing, whereas generated container/on-container pairs can be low-contrast.
    readonly property color pillColor: pomodoro
        ? (TimerService.pomodoroBreak ? Appearance.colors.colSecondary : Appearance.colors.colPrimary)
        : Appearance.colors.colPrimary
    readonly property color onColor: pomodoro
        ? (TimerService.pomodoroBreak ? Appearance.colors.colOnSecondary : Appearance.colors.colOnPrimary)
        : Appearance.colors.colOnPrimary
    readonly property string icon: pomodoro
        ? (TimerService.pomodoroBreak ? "coffee" : "timer")
        : "avg_pace"
    readonly property string label: pomodoro
        ? root.formatSeconds(TimerService.pomodoroSecondsLeft)
        : root.formatSeconds(Math.floor(TimerService.stopwatchTime) / 100)

    // Stay visible while collapsing so the pill can fade/scale out instead of
    // vanishing; the width still animates for a smooth bar reflow.
    visible: implicitWidth > 0
    enabled: shown
    hoverEnabled: true
    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.barHeight
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    cursorShape: Qt.PointingHandCursor
    onClicked: GlobalStates.sidebarRightOpen = true

    function formatSeconds(totalSeconds) {
        const s = Math.max(0, Math.floor(totalSeconds));
        const m = Math.floor(s / 60).toString().padStart(2, "0");
        const sec = (s % 60).toString().padStart(2, "0");
        return `${m}:${sec}`;
    }

    BarStandalonePill {
        id: pill
        vertical: root.vertical
        shown: root.shown
        dimmed: root.containsMouse
        color: root.pillColor

        RowLayout {
            id: pillRow
            visible: !root.vertical
            spacing: Appearance.spacing.space50
            MaterialSymbol {
                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                color: root.onColor
            }
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.onColor
            }
        }

        ColumnLayout {
            id: pillColumn
            visible: root.vertical
            spacing: 0
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                color: root.onColor
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: root.onColor
            }
        }
    }

    StyledToolTip {
        // MouseArea exposes containsMouse, not `hovered`, so gate explicitly -
        // otherwise StyledToolTip's parent.hovered===undefined check leaves it
        // permanently visible.
        extraVisibleCondition: root.shown && root.containsMouse
        text: root.pomodoro
            ? (TimerService.pomodoroBreak ? Translation.tr("Pomodoro — break") : Translation.tr("Pomodoro — focus"))
            : Translation.tr("Stopwatch")
    }
}
