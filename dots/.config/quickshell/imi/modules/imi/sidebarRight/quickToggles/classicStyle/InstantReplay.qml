import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    toggled: ScreenRecord.replaying
    buttonIcon: "replay"
    onClicked: {
        ScreenRecord.toggleReplay()
    }
    StyledToolTip {
        text: ScreenRecord.replaying
            ? Translation.tr("Instant replay: buffering (Alt+F10 saves a clip)")
            : Translation.tr("Instant replay")
    }
}
