import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    property var action
    property var selectionMode

    property string description: switch (root.action) {
    case RegionSelection.SnipAction.Copy:
    case RegionSelection.SnipAction.Edit:
        return Translation.tr("Copy region (LMB) or annotate (RMB)");
    case RegionSelection.SnipAction.Search:
        return Translation.tr("Search with Google Lens");
    case RegionSelection.SnipAction.CharRecognition:
        return Translation.tr("Recognize text");
    case RegionSelection.SnipAction.Record:
    case RegionSelection.SnipAction.RecordWithSound:
        return Translation.tr("Record region");
    }
    property string materialSymbol: switch (root.action) {
    case RegionSelection.SnipAction.Copy:
    case RegionSelection.SnipAction.Edit:
        return "content_cut";
    case RegionSelection.SnipAction.Search:
        return "image_search";
    case RegionSelection.SnipAction.CharRecognition:
        return "document_scanner";
    case RegionSelection.SnipAction.Record:
    case RegionSelection.SnipAction.RecordWithSound:
        return "videocam";
    default:
        return "";
    }

    property bool showDescription: true
    function hideDescription() {
        root.showDescription = false
    }
    Timer {
        id: descTimeout
        interval: 1000
        running: true
        onTriggered: {
            root.hideDescription()
        }
    }
    onActionChanged: {
        root.showDescription = true
        descTimeout.restart()
    }

    // Entering and leaving, on the shell's expressive tiers: the spatial curve
    // carries the scale (it overshoots slightly, so the marker arrives rather
    // than appears) and the effects curve carries the fade, which is the same
    // pairing the widget trees use for travel and fade. Scaled from the
    // cursor's own corner, so it grows out of the pointer instead of the
    // middle of the screen.
    property bool shown: true
    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.7
    visible: opacity > 0.01
    transformOrigin: Item.TopLeft
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    property int margins: Appearance.spacing.space100
    implicitWidth: content.implicitWidth + margins * 2
    implicitHeight: content.implicitHeight + margins * 2

    Rectangle {
        id: content
        anchors.centerIn: parent

        property real padding: Appearance.spacing.space100
        implicitHeight: 38
        implicitWidth: root.showDescription ? contentRow.implicitWidth + padding * 2 : implicitHeight
        clip: true

        topLeftRadius: 6
        bottomLeftRadius: implicitHeight - topLeftRadius
        bottomRightRadius: bottomLeftRadius
        topRightRadius: bottomLeftRadius

        color: Appearance.colors.colPrimary

        Behavior on topLeftRadius {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Row {
            id: contentRow
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: content.padding
            }
            spacing: Appearance.spacing.space150

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                iconSize: 22
                color: Appearance.colors.colOnPrimary
                animateChange: true
                text: root.materialSymbol
            }

            FadeLoader {
                id: descriptionLoader
                anchors.verticalCenter: parent.verticalCenter
                shown: root.showDescription
                sourceComponent: StyledText {
                    color: Appearance.colors.colOnPrimary
                    text: root.description
                    anchors.right: parent.right
                    anchors.rightMargin: Appearance.spacing.space100
                }
            }
        }
    }
}
