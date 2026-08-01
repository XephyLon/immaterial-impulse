pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.modules.imi.overlay.crosshair
import qs.modules.imi.overlay.volumeMixer
import qs.modules.imi.overlay.floatingImage
import qs.modules.imi.overlay.fpsLimiter
import qs.modules.imi.overlay.recorder
import qs.modules.imi.overlay.resources
import qs.modules.imi.overlay.notes
import qs.modules.imi.overlay.discordVoice

DelegateChooser {
    id: root
    role: "identifier"

    DelegateChoice { roleValue: "crosshair"; Crosshair {} }
    DelegateChoice { roleValue: "floatingImage"; FloatingImage {} }
    DelegateChoice { roleValue: "fpsLimiter"; FpsLimiter {} }
    DelegateChoice { roleValue: "recorder"; Recorder {} }
    DelegateChoice { roleValue: "resources"; Resources {} }
    DelegateChoice { roleValue: "notes"; Notes {} }
    DelegateChoice { roleValue: "volumeMixer"; VolumeMixer {} }
    DelegateChoice { roleValue: "discordVoice"; DiscordVoiceOverlay {} }
}
