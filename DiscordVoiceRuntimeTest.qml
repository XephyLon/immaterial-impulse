import QtQuick
import Quickshell
import "modules/common/plugins/bundled/discordVoice" as DiscordPlugin
import qs.modules.ii.bar as Bar

ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: content.implicitWidth
        implicitHeight: column.implicitHeight
        color: "transparent"

        Column {
            id: column
            DiscordPlugin.Widget { id: content }
            Bar.DiscordVoicePlugin { vertical: false }
        }
    }
}
