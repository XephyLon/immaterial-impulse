pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

StyledPopup {
    id: root

    onActiveChanged: if (active) {
        panel.opacity = 0;
        panel.scale = 0.94;
        enter.restart();
    }

    ColumnLayout {
        id: panel
        implicitWidth: 360
        spacing: Appearance.spacing.space150
        transformOrigin: Item.Top

        ParallelAnimation {
            id: enter
            NumberAnimation { target: panel; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: panel; property: "scale"; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutBack }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            MaterialShapeWrappedMaterialSymbol {
                text: "voice_chat"
                shape: MaterialShape.Shape.Cookie7Sided
                implicitSize: 44
                iconSize: 23
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: DiscordVoice.channel?.name || "Discord Voice"
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    text: DiscordVoice.inVoice
                        ? `${DiscordVoice.participants.length} connected`
                        : (DiscordVoice.errorMessage || "Not connected to voice")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                onClicked: root.pinnedOpen = false
                MaterialSymbol { anchors.centerIn: parent; text: "close"; color: Appearance.colors.colOnLayer1 }
            }
        }

        Flow {
            visible: DiscordVoice.participants.length > 0
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            Repeater {
                model: DiscordVoice.participants
                ParticipantAvatar { required property var modelData; participant: modelData; avatarSize: 52; showName: true }
            }
        }

        Rectangle {
            visible: DiscordVoice.participants.length === 0
            Layout.fillWidth: true
            implicitHeight: 92
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2
            Column {
                anchors.centerIn: parent
                spacing: Appearance.spacing.space25
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: DiscordVoice.status === "auth_required" ? "Discord authorization required" : "Join a Discord voice channel"
                    color: Appearance.colors.colOnLayer2
                    font.weight: Font.DemiBold
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: DiscordVoice.status === "unavailable" ? "Start Discord, then reconnect" : "Participants will appear here"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            RippleButton {
                visible: DiscordVoice.status === "auth_required" || DiscordVoice.status === "authorizing"
                enabled: DiscordVoice.status !== "authorizing"
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: DiscordVoice.authorize()
                StyledText {
                    anchors.centerIn: parent
                    text: DiscordVoice.status === "authorizing" ? "Waiting for Discord…" : "Authorize Discord"
                    color: Appearance.colors.colOnPrimary
                    font.weight: Font.DemiBold
                }
            }
            RippleButton {
                visible: DiscordVoice.status !== "auth_required" && !DiscordVoice.inVoice
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                onClicked: DiscordVoice.connect()
                StyledText { anchors.centerIn: parent; text: "Reconnect"; color: Appearance.colors.colOnSecondaryContainer; font.weight: Font.DemiBold }
            }
            RippleButton {
                visible: DiscordVoice.inVoice
                Layout.fillWidth: true
                implicitHeight: 44
                toggled: DiscordVoice.muted
                buttonRadius: Appearance.rounding.full
                onClicked: DiscordVoice.setMuted(!DiscordVoice.muted)
                Row {
                    anchors.centerIn: parent; spacing: Appearance.spacing.space50
                    MaterialSymbol { text: DiscordVoice.muted ? "mic_off" : "mic"; color: DiscordVoice.muted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                    StyledText { text: DiscordVoice.muted ? "Unmute" : "Mute"; color: DiscordVoice.muted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                }
            }
            RippleButton {
                visible: DiscordVoice.inVoice
                Layout.fillWidth: true
                implicitHeight: 44
                toggled: DiscordVoice.deafened
                buttonRadius: Appearance.rounding.full
                onClicked: DiscordVoice.setDeafened(!DiscordVoice.deafened)
                Row {
                    anchors.centerIn: parent; spacing: Appearance.spacing.space50
                    MaterialSymbol { text: DiscordVoice.deafened ? "headset_off" : "headphones"; color: DiscordVoice.deafened ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                    StyledText { text: DiscordVoice.deafened ? "Undeafen" : "Deafen"; color: DiscordVoice.deafened ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                }
            }
        }
    }
}
