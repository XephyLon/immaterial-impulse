pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins

Rectangle {
    id: root
    readonly property int avatarLimit: PluginState.option("discord_voice", "maxOverlayAvatars", 8)
    readonly property var visibleParticipants: DiscordVoice.participants.slice(0, avatarLimit)

    implicitWidth: 344
    implicitHeight: 154
    width: implicitWidth
    height: implicitHeight
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    border.width: Appearance.borderWidth.standard
    border.color: Appearance.colors.colLayer0Border

    function beginAuthorization() {
        // SUPER+G owns exclusive keyboard focus. Release it before Discord
        // creates its consent dialog or the dialog can remain hidden behind us.
        DiscordVoice.authorizeAfterFocusRelease();
        GlobalStates.overlayOpen = false;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space75
            Rectangle {
                implicitWidth: 38; implicitHeight: 38
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "voice_chat"
                    color: Appearance.colors.colOnPrimaryContainer
                    iconSize: 22
                    fill: DiscordVoice.inVoice ? 1 : 0
                }
            }
            ColumnLayout {
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: DiscordVoice.channel?.name || (DiscordVoice.status === "auth_required"
                        ? "Connect Discord" : "No voice channel")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    text: DiscordVoice.inVoice
                        ? `${DiscordVoice.participants.length} participant${DiscordVoice.participants.length === 1 ? "" : "s"}`
                        : (DiscordVoice.errorMessage || "Discord voice overlay")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitWidth: 38; implicitHeight: 38
                buttonRadius: Appearance.rounding.full
                colBackground: DiscordVoice.muted ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2
                onClicked: DiscordVoice.setMuted(!DiscordVoice.muted)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: DiscordVoice.muted ? "mic_off" : "mic"
                    iconSize: 20
                    color: DiscordVoice.muted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                }
            }
        }

        Row {
            visible: root.visibleParticipants.length > 0
            Layout.alignment: Qt.AlignHCenter
            spacing: Appearance.spacing.space75
            Repeater {
                model: root.visibleParticipants
                ParticipantAvatar { required property var modelData; participant: modelData; avatarSize: 52; showName: true }
            }
        }

        RippleButton {
            visible: DiscordVoice.status === "auth_required" || DiscordVoice.status === "authorizing"
            enabled: DiscordVoice.status !== "authorizing"
            Layout.fillWidth: true
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            onClicked: root.beginAuthorization()
            StyledText {
                anchors.centerIn: parent
                text: DiscordVoice.status === "authorizing" ? "Waiting for Discord…" : "Authorize Discord"
                color: Appearance.colors.colOnPrimary
                font.weight: Font.DemiBold
            }
        }
    }
}
