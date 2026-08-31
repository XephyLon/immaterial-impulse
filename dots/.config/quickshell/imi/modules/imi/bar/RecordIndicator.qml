import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// M3E live-activity chip for an active screen recording: an error-toned
// pill with the recording glyph, the elapsed time, and - when other apps
// are screencasting at the same time - a count badge naming how many.
// Click stops the recording (the same stop the keybind and record.sh's
// toggle take). TimerPill is the shape grammar; PrivacyIndicator keeps
// the passive capture signals, this chip is the one live activity the
// user started and will want to end.
MouseArea {
    id: root

    property bool vertical: false

    readonly property bool shown: ScreenRecord.recording
    readonly property bool paused: ScreenRecord.recordPaused
    readonly property int othersWatching: MediaCapture.screencastApps.length

    // Elapsed off the persisted start stamp, so the chip keeps counting
    // across a shell restart mid-recording - record.sh owns the recording
    // process AND the stamp, for the same reason it owns record.enable.
    readonly property real startedAt: Persistent.states.record.startedAt
    property int elapsedSeconds: 0
    function updateElapsed() {
        root.elapsedSeconds = root.startedAt > 0
            ? Math.max(0, Math.floor(Date.now() / 1000 - root.startedAt))
            : 0;
    }
    onStartedAtChanged: updateElapsed()
    Timer {
        // Frozen while paused: a counting timer under a pause glyph reads
        // as a chip that missed the pause. (Wall time resumes with a jump -
        // gsr's recorded duration diverges from the wall clock either way.)
        running: root.shown && !root.paused
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateElapsed()
    }

    // The error CONTAINER pair: in a dark scheme the base colError is the
    // light rose, and this chip wants the deeper red under light glyphs.
    readonly property color pillColor: Appearance.colors.colErrorContainer
    readonly property color onColor: Appearance.colors.colOnErrorContainer
    readonly property string icon: paused ? "pause" : "screen_record"
    readonly property string label: {
        const s = root.elapsedSeconds;
        const m = Math.floor(s / 60).toString().padStart(2, "0");
        return `${m}:${(s % 60).toString().padStart(2, "0")}`;
    }

    // Stay visible while collapsing so the pill can fade/scale out instead
    // of vanishing; the width still animates for a smooth bar reflow.
    visible: implicitWidth > 0
    enabled: shown
    hoverEnabled: true
    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.barHeight
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    cursorShape: Qt.PointingHandCursor
    onClicked: ScreenRecord.stopRecord()

    // The badge: how many OTHER apps are screencasting while this records.
    component CountBadge: Rectangle {
        visible: root.othersWatching > 0
        implicitWidth: Math.max(implicitHeight, badgeText.implicitWidth + Appearance.spacing.space50)
        implicitHeight: badgeText.implicitHeight
        radius: Appearance.rounding.full
        color: root.onColor
        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: root.othersWatching
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.pillColor
        }
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        // The badge belongs to the group pill's footprint, not the bar's -
        // shift onto the group pill's centre along the bar's thickness.
        anchors.verticalCenterOffset: root.vertical ? 0 : Appearance.sizes.barStandalonePillOffset
        anchors.horizontalCenterOffset: root.vertical ? Appearance.sizes.barStandalonePillOffset : 0
        radius: Appearance.rounding.full
        color: root.pillColor
        opacity: root.shown ? (root.containsMouse ? 0.88 : 1) : 0
        scale: root.shown ? 1 : 0.7
        transformOrigin: Item.Center
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        implicitWidth: pillRow.implicitWidth + Appearance.spacing.space150 * 2
        implicitHeight: root.vertical
            ? pillColumn.implicitHeight + Appearance.spacing.space50 * 2
            : Appearance.sizes.barStandalonePillHeight

        RowLayout {
            id: pillRow
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50
            MaterialSymbol {
                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                fill: 1
                color: root.onColor
            }
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.onColor
            }
            CountBadge {}
        }

        ColumnLayout {
            id: pillColumn
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 0
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                fill: 1
                color: root.onColor
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: root.onColor
            }
            CountBadge { Layout.alignment: Qt.AlignHCenter }
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.shown && root.containsMouse
        text: (root.paused
            ? Translation.tr("Recording paused — click to stop")
            : Translation.tr("Recording — click to stop"))
            + (root.othersWatching > 0
                ? "\n" + Translation.tr("%1 app(s) are screencasting").arg(root.othersWatching)
                : "")
    }
}
