pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins
import "../../common/plugins/bundled/discord-voice" as DiscordPackage

MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    property bool popupOpen: false
    readonly property int avatarLimit: PluginState.option("discord_voice", "maxBarAvatars", 4)
    readonly property var shownParticipants: DiscordVoice.participants.slice(0, avatarLimit)

    implicitWidth: vertical ? 34 : content.implicitWidth + Appearance.spacing.space100 * 2
    implicitHeight: vertical ? content.implicitHeight + Appearance.spacing.space50 * 2 : Appearance.sizes.barHeight
    acceptedButtons: Qt.LeftButton
    hoverEnabled: false
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
    onPopupOpenChanged: {
        if (popupOpen) focusArm.restart();
        else { focusArm.stop(); popupFocus.active = false; popupFocus.windows = []; }
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Appearance.spacing.space50
        MaterialSymbol {
            text: "voice_chat"
            fill: DiscordVoice.inVoice ? 1 : 0
            iconSize: 21
            color: DiscordVoice.inVoice ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }
        Row {
            visible: !root.vertical && root.shownParticipants.length > 0
            spacing: -Appearance.spacing.space50
            Repeater {
                model: root.shownParticipants
                DiscordPackage.ParticipantAvatar {
                    required property var modelData
                    // Bound component behavior does not inject `index` into the
                    // delegate's scope; the overlapping avatar stack needs it to
                    // order itself, so it has to be taken as a required property.
                    required property int index
                    participant: modelData
                    avatarSize: 25
                    z: index
                }
            }
        }
        StyledText {
            visible: !root.vertical && DiscordVoice.inVoice
            text: DiscordVoice.participants.length
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnPrimaryContainer
        }
    }

    Loader {
        id: popupLoader
        active: root.popupOpen
        sourceComponent: DiscordPackage.DiscordVoicePopup {
            pinnedOpen: true
            hoverTarget: root
            onPinnedOpenChanged: if (!pinnedOpen) root.popupOpen = false
        }
    }
    Timer {
        id: focusArm
        interval: 16
        repeat: true
        property int attempts: 0
        onTriggered: {
            const window = popupLoader.item?.item;
            if (!root.popupOpen || attempts++ > 30) { stop(); return; }
            if (!window) return;
            popupFocus.windows = [root.QsWindow?.window, window].filter(item => item);
            popupFocus.active = true;
            stop();
        }
        onRunningChanged: if (running) attempts = 0
    }
    HyprlandFocusGrab {
        id: popupFocus
        active: false
        windows: []
        onCleared: root.popupOpen = false
    }
}
