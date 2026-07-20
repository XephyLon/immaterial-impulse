pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.overlay
import "../../../common/plugins/bundled/discordVoice" as DiscordPackage

StyledOverlayWidget {
    id: root
    title: "Discord Voice"
    showCenterButton: true
    minimumWidth: 344
    minimumHeight: 154

    contentItem: DiscordPackage.Widget {
        anchors.fill: parent
    }
}
