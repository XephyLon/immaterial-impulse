pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    required property var participant
    property real avatarSize: 44
    property bool showName: false
    property bool speaking: participant?.speaking === true

    implicitWidth: root.showName ? Math.max(root.avatarSize, nameText.implicitWidth) : root.avatarSize
    implicitHeight: root.avatarSize + (root.showName ? nameText.implicitHeight + Appearance.spacing.space25 : 0)

    Rectangle {
        id: ring
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.avatarSize
        height: root.avatarSize
        radius: Appearance.rounding.full
        color: root.speaking ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        scale: root.speaking ? 1.06 : 1

        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

        Image {
            id: avatar
            anchors.fill: parent
            anchors.margins: root.speaking
                ? Appearance.spacing.space50 : Appearance.spacing.space25
            source: DiscordVoice.avatarUrl(root.participant, 128)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Rectangle {
            id: avatarMask
            anchors.fill: avatar
            radius: width / 2
            visible: false
        }
        OpacityMask {
            anchors.fill: avatar
            source: avatar
            maskSource: avatarMask
            visible: avatar.status === Image.Ready
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: avatar.status !== Image.Ready
            text: "person"
            iconSize: root.avatarSize * 0.52
            color: Appearance.colors.colOnLayer2
        }

        Rectangle {
            visible: root.participant?.mute || root.participant?.deaf
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 17
            height: 17
            radius: Appearance.rounding.full
            color: Appearance.colors.colErrorContainer
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.participant?.deaf ? "headset_off" : "mic_off"
                iconSize: 11
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }

    StyledText {
        id: nameText
        visible: root.showName
        anchors.top: ring.bottom
        anchors.topMargin: Appearance.spacing.space25
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(100, implicitWidth)
        text: root.participant?.nick || root.participant?.username || "Unknown"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer1
    }
}
