import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes

// Live-activity chip for the active mode, in the record indicator's pill
// grammar: the mode's glyph and name on the mode's own container colour.
// Takes no room while nothing is on. Click opens the manager, right-click
// ends the mode; the hover card names who started it and when it ends, and
// carries the two controls for a pointer that is already there.
MouseArea {
    id: root

    property bool vertical: false

    readonly property bool shown: Modes.active
    readonly property var mode: Modes.activeMode
    readonly property string colorKey: root.mode?.color ?? ""
    readonly property color pillColor: ModeUi.container(root.colorKey)
    readonly property color onColor: ModeUi.onContainer(root.colorKey)
    readonly property string icon: root.mode?.icon ?? "tune"
    readonly property string label: root.mode?.name ?? ""

    // Stay visible while collapsing so the pill can fade/scale out instead
    // of vanishing; the width still animates for a smooth bar reflow.
    visible: implicitWidth > 0
    enabled: shown
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.barHeight
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Modes.deactivate("manual");
            return;
        }
        GlobalStates.modesOpen = !GlobalStates.modesOpen;
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        // The pill belongs to the group pill's footprint, not the bar's -
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
        }
    }

    ModeIndicatorPopup {
        hoverTarget: root
    }
}
