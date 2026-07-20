import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The bundled plugin is routed through the native bar adapter to keep one
// geometry owner. This fallback still gives installed-package hosts a status glyph.
Item {
    property bool vertical: false
    implicitWidth: 32
    implicitHeight: 32
    MaterialSymbol {
        anchors.centerIn: parent
        text: "voice_chat"
        fill: DiscordVoice.inVoice ? 1 : 0
        color: Appearance.colors.colPrimary
    }
}
