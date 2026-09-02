import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/barEdges.js" as BarEdges

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

    // An alarm, under every bar style and in both themes: the saturated
    // member of the error pair (colAlarm - dark's errorContainer, light's
    // error) with its on-colour. colError alone was a pastel pink pill with
    // a dark glyph in the dark theme, which is the pair the other way round
    // and read as decoration rather than danger. Hover is a colour, not a dim.
    readonly property color pillColor: root.containsMouse ? Appearance.colors.colAlarmHover : Appearance.colors.colAlarm
    readonly property color onColor: Appearance.colors.colOnAlarm

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
        // The badge belongs to the group pill's footprint, not the bar's, and
        // those two only share a centre while the group pill's insets match.
        // Shift onto the group pill's centre along the bar's thickness.
        anchors.verticalCenterOffset: root.vertical ? 0 : Appearance.sizes.barStandalonePillOffset
        anchors.horizontalCenterOffset: root.vertical ? Appearance.sizes.barStandalonePillOffset : 0
        radius: Appearance.rounding.full
        color: root.pillColor
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        // Fade + scale with the whole show/hide so it eases in and out; hover
        // is the colour above, not a dim.
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.7
        transformOrigin: Item.Center
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        implicitWidth: (root.vertical ? iconColumn.implicitWidth : iconRow.implicitWidth) + Appearance.spacing.space100 * 2
        // A badge inside the group pill, not a group pill of its own.
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

    // Hover reads, click acts. The pinned state lives here rather than inside
    // the popup because the popup is a declaration with no surface of its own -
    // the overlay hosts it - so the widget that was clicked is what owns the
    // decision to keep it open.
    property bool controlsPinned: false
    // The bar's one open state while the click-pinned controls are up: the
    // anchor indicator on the popup-facing edge, as long as the pill.
    PopupAnchorIndicator {
        wraps: pill
        edgeItem: root
        edge: BarEdges.popupEdge(Config.options.bar.vertical, Config.options.bar.bottom)
        shown: root.controlsPinned
    }
    cursorShape: Qt.PointingHandCursor
    onClicked: root.controlsPinned = !root.controlsPinned
    // A click anywhere outside the card unpins, which is what the overlay's
    // focus grab reports.
    onShownChanged: if (!shown) root.controlsPinned = false

    PrivacyIndicatorPopup {
        id: privacyPopup
        hoverTarget: root
        pinnedOpen: root.controlsPinned
        onDismissRequested: root.controlsPinned = false
    }
}
