import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import "modules/common/functions/edit_mode.js" as EditMode

/*
 * Does the lock's PALETTE follow the Lockscreen tab?
 *
 * Stage 9 switched every layer's SOURCE on `editLockPreview` - wallpaper, WE
 * project, islands, the widget filter - and left the theme keyed on
 * `screenLocked` alone. So the tab drew the lock's wallpaper under the
 * desktop's colours, which is a picture the lock screen never shows.
 *
 * The two things that decide the palette are read here directly: the theme
 * loader's own gate, and the quantizer path Appearance derives transparency
 * from. Neither needs matugen to have run - what is under test is which
 * wallpaper the palette is being taken FROM, not the palette itself.
 */
ShellRoot {
    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 300
        visible: true

        Timer {
            running: true
            interval: 1200
            onTriggered: {
                Config.options.background.lockWall = Quickshell.shellPath("tests/fixtures/colorful_64.png");
                Config.options.background.wallpaperPath = Quickshell.shellPath("tests/fixtures/low_chroma_64.png");
                report.restart();
            }
        }

        Timer {
            id: report
            interval: 800
            onTriggered: {
                console.log("[LOCKLOOK] desktop tab: lockLookActive="
                    + GlobalStates.lockLookActive
                    + " lockThemeActive=" + MaterialThemeLoader.lockThemeActive);
                GlobalStates.editMode = true;
                GlobalStates.editTab = EditMode.LOCKSCREEN_TAB;
                afterTab.restart();
            }
        }

        Timer {
            id: afterTab
            interval: 800
            onTriggered: {
                console.log("[LOCKLOOK] lock tab: lockLookActive="
                    + GlobalStates.lockLookActive
                    + " lockThemeActive=" + MaterialThemeLoader.lockThemeActive);
                GlobalStates.editTab = EditMode.DESKTOP_TAB;
                afterBack.restart();
            }
        }

        Timer {
            id: afterBack
            interval: 800
            onTriggered: {
                console.log("[LOCKLOOK] back: lockLookActive="
                    + GlobalStates.lockLookActive
                    + " lockThemeActive=" + MaterialThemeLoader.lockThemeActive);
                console.log("[LOCKLOOK] done");
                Qt.quit();
            }
        }
    }
}
