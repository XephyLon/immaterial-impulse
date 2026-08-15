import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.imi.background
import qs.modules.imi.cheatsheet
import qs.modules.imi.bar
import qs.modules.imi.dock
import qs.modules.imi.lock
import qs.modules.imi.mediaControls
import qs.modules.imi.notificationPopup
import qs.modules.imi.onScreenDisplay
import qs.modules.imi.onScreenKeyboard
import qs.modules.imi.overview
import qs.modules.imi.polkit
import qs.modules.imi.settings
import qs.modules.imi.regionSelector
import qs.modules.imi.screenCorners
import qs.modules.imi.screensaver
import qs.modules.imi.screenTranslator
import qs.modules.imi.sessionScreen
import qs.modules.imi.sidebarLeft
import qs.modules.imi.sidebarRight
import qs.modules.imi.overlay
import qs.modules.imi.verticalBar
import qs.modules.imi.wallpaperSelector
import qs.modules.imi.desktopMenu
import qs.modules.imi.dropShelf
import qs.modules.imi.recordingRegion
import qs.modules.imi.screenshotResult

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    // No extraCondition: the vertical bar loads the same widget files, so one
    // overlay serves whichever bar is up.
    PanelLoader { component: BarPopupOverlay {} }
    PanelLoader { component: Background {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: Screensaver {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: Settings {} }
    PanelLoader { component: DesktopMenu {} }
    PanelLoader { component: DropShelfPanel {} }
    PanelLoader { component: ScreenshotResultPanel {} }
    PanelLoader { component: RecordingRegionPanel {} }
}
