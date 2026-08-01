import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Privacy indicator pill (macOS/Android style). Only visible while an app is
// actively using the microphone, camera, and/or screencast; hidden when idle.
// Each signal has its own icon that eases in/out independently, and the whole
// pill eases in/out when the first/last signal toggles.
MouseArea {
    id: root

    property bool vertical: false

    readonly property bool micOn: MediaCapture.micActive
    readonly property bool cameraOn: MediaCapture.cameraActive
    readonly property bool screencastOn: MediaCapture.screencastActive
    // Shell-owned captures: an active recording and the armed instant-replay
    // buffer are ongoing screen grabs too - they belong in the privacy pill.
    readonly property bool recordingOn: ScreenRecord.recording
    readonly property bool replayOn: ScreenRecord.replaying
    readonly property bool shown: micOn || cameraOn || screencastOn || recordingOn || replayOn

    // Vivid error fill with its matching on-color. The BASE error pair is M3's
    // high-contrast pairing; the *container* variants can be low-contrast.
    readonly property color pillColor: Appearance.colors.colError
    readonly property color onColor: Appearance.colors.colOnError

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

    // One icon slot that collapses its width and fades/scales when its signal is
    // off, so icons appear/disappear smoothly instead of popping in and out.
    component IconSlot: Item {
        id: slot
        property bool on: false
        property string sym: ""
        readonly property int sz: Appearance.font.pixelSize.large
        readonly property int gap: Appearance.spacing.space50
        // Collapse along the layout axis: width in a horizontal bar, height in a
        // vertical one.
        implicitWidth: root.vertical ? sz : (on ? sz + gap : 0)
        implicitHeight: root.vertical ? (on ? sz + gap : 0) : sz
        opacity: on ? 1 : 0
        scale: on ? 1 : 0.4
        clip: true
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: slot.sym
            iconSize: slot.sz
            color: root.onColor
        }
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        radius: Appearance.rounding.full
        color: root.pillColor
        // Fade + scale with the whole show/hide so it eases in and out.
        opacity: root.shown ? (root.containsMouse ? 0.88 : 1) : 0
        scale: root.shown ? 1 : 0.7
        transformOrigin: Item.Center
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        implicitWidth: (root.vertical ? iconColumn.implicitWidth : iconRow.implicitWidth) + Appearance.spacing.space100 * 2
        // Match the M3 group pill height (bar height minus BarGroup's 4px insets).
        implicitHeight: root.vertical
            ? iconColumn.implicitHeight + Appearance.spacing.space50 * 2
            : Appearance.sizes.barStandalonePillHeight

        Row {
            id: iconRow
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: 0
            IconSlot { on: root.micOn; sym: "mic" }
            IconSlot { on: root.cameraOn; sym: "videocam" }
            IconSlot { on: root.screencastOn; sym: "screen_share" }
            IconSlot { on: root.recordingOn; sym: "screen_record" }
            IconSlot { on: root.replayOn; sym: "replay" }
        }

        Column {
            id: iconColumn
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 0
            IconSlot { on: root.micOn; sym: "mic" }
            IconSlot { on: root.cameraOn; sym: "videocam" }
            IconSlot { on: root.screencastOn; sym: "screen_share" }
            IconSlot { on: root.recordingOn; sym: "screen_record" }
            IconSlot { on: root.replayOn; sym: "replay" }
        }
    }

    // Hover popup listing what's in use, instead of a cramped multi-line tooltip.
    PrivacyIndicatorPopup {
        hoverTarget: root
    }
}
