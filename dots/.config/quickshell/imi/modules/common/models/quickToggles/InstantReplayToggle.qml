import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Instant replay")

    toggled: ScreenRecord.replaying
    icon: "replay"
    mainAction: () => {
        ScreenRecord.toggleReplay()
    }
    // Long-press / right-click saves a clip of the last moments.
    altAction: () => {
        ScreenRecord.saveReplay()
    }
    tooltipText: ScreenRecord.replaying
        ? Translation.tr("Buffering - press Alt+F10 or long-press to save a clip")
        : Translation.tr("Keep the last moments in a buffer")
}
