import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool sysTrayOverflowOpen: false
    // The idle path: hypridle's listener blanks every screen, and the ladder
    // behind it (lock, DPMS, suspend) is meant to keep running underneath.
    property bool screensaverActive: false
    // The deliberate path: monitor names the user blacked out on purpose. Kept
    // apart from the flag above because only this one holds an idle inhibitor
    // (services/Idle.qml) - blanking a panel to work on another must not walk
    // the session into a lock, and going idle still must.
    property var screensaverScreens: []
    property bool osdBrightnessOpen: false
    property bool settingsOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool settingsHeldForRegionSelector: false
    // Picking the wallpaper's subject on the desktop itself, at full size, over
    // the real widgets - rather than on a 300px thumbnail in the wallpaper
    // selector, where a click landing on a shoulder is several hundred pixels
    // off by the time the mask is judged at screen size.
    property bool clockDepthSelectOpen: false
    // Per screen name: where the wallpaper's whole box sits in that screen's
    // coordinates, plus the source the wallpaper item is actually drawing.
    // Published by Background.qml while the selector above is armed, because the
    // selection surface is a different window and cannot read that item. It
    // draws its cutout into this box and measures its clicks against the same
    // rectangle, so the pixels it judges are the pixels the depth layer masks.
    property var clockDepthViewports: ({})
    // True while a copy snip's crop/clipboard pipeline runs; cancel paths
    // must not dismiss (and thereby kill) the in-flight process.
    property bool snipCopyInFlight: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property string settingsPage: ""
    property Item currentPageInstance: null
    property bool desktopWidgetKeyboardFocus: false
    property bool desktopMenuOpen: false
    property var desktopMenuScreen: null
    property real desktopMenuX: 0
    property real desktopMenuY: 0
    property string wallpaperSelectorTarget: "wallpaper"
    // The bar hover popup (StyledPopup) whose target widget is currently
    // hovered. Adjacent bar popups are separate layer-shell surfaces, so a
    // lingering one can paint over a newly opened neighbour; each popup watches
    // this so the previous one closes at once instead of overlapping the new one.
    property var activeBarPopup: null
    // Edit Mode: the desktop shrinks into a viewport and every affordance it
    // normally hides comes out (docs/superpowers/specs/2026-08-16-edit-mode-design.md).
    //
    // Here and not in `Config.options` deliberately: a persisted edit mode is a
    // shell that comes back from a restart with the desktop shrunk, and every
    // change the mode makes is written through to its own store as it happens,
    // so the mode itself has nothing to remember. It is also what makes a
    // hot-reload mid-edit correct with no code - the mode is gone, the edits
    // are on disk.
    //
    // Global rather than per monitor: the bar and dock layouts it will edit are
    // themselves global, and a per-monitor mode would have to explain why
    // moving a bar chip on one screen changed another.
    property bool editMode: false
    // The entry and exit, as one animated scalar that every surface the mode
    // draws on reads. It lives here rather than beside the transform it feeds
    // because the desktop and the chrome that frames it are on two different
    // layer surfaces, in two different scene graphs, and both derive their
    // geometry from this number: a second Behavior on the other surface would
    // be two values that have to agree, and the frames where they do not are
    // the ones where the chrome frames a rectangle the desktop is not at.
    //
    // Interpolating one scalar rather than animating a scale and an offset
    // separately is also what keeps the desktop's corner travelling in a
    // straight line - there is no frame in which the scale has arrived and the
    // inset has not.
    //
    // `elementMove`, taken whole, and deliberately not `elementMoveEnter` /
    // `elementMoveExit`: those two carry `alwaysRunToEnd`, so a mode toggled
    // twice inside its own duration would finish arriving before it started
    // leaving.
    property real editProgress: root.editMode ? 1 : 0
    Behavior on editProgress {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // The drawer - Edit Mode's catalogue of desktop widgets. Session state for
    // the same reason the mode is, and beside it for the same reason the
    // progress is: the desktop it translates and the panel that slides in are
    // on two different layer surfaces, and both build their geometry out of
    // this pair.
    property bool editDrawerOpen: false
    // The drawer's own animated scalar, second BESIDE `editProgress` and never
    // a second animation OF it: this one carries the slide and the desktop's
    // sideways travel, that one carries the shrink. `&& editMode` rather than
    // the open flag alone so the exit closes the drawer even if nothing wrote
    // the flag back - both scalars then run down together on the same tier,
    // and edit_mode.js multiplies the shift by the mode's own t anyway, so the
    // frame at progress 0 is the untransformed desktop whatever this holds.
    property real editDrawerProgress: root.editMode && root.editDrawerOpen ? 1 : 0
    Behavior on editDrawerProgress {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // The per-widget context menu - Edit Mode's right-click on a widget
    // (spec §4.1: Remove / Pin / Size). Session state like the mode itself,
    // and shaped like the desktop menu's quad: which screen, where on it, and
    // - the one field the desktop menu does not need - which widget it is
    // about. The point is in SCREEN coordinates, mapped by the widget through
    // its own transform chain on the way here, so the menu window needs no
    // knowledge of the mode's viewport arithmetic.
    property bool editWidgetMenuOpen: false
    property string editWidgetMenuScreenName: ""
    property real editWidgetMenuX: 0
    property real editWidgetMenuY: 0
    property string editWidgetMenuPluginId: ""

    property bool dropShelfOpen: false
    property real dropShelfX: 0
    property real dropShelfY: 0
    property bool dropShelfAnchorBelow: false // Shelf hangs below the anchor point (bar reveal) instead of above it

    // Anything that takes the screen away ends the mode, because the desktop it
    // shrinks is no longer the thing on screen. The lock is the one that
    // matters: the background surface is promoted to Overlay and repurposed as
    // the lock backdrop while locked, so a shrunk desktop would be the lock
    // screen's wallpaper.
    onScreenLockedChanged: if (root.screenLocked) root.editMode = false
    onOverviewOpenChanged: if (root.overviewOpen) root.editMode = false
    onSessionOpenChanged: if (root.sessionOpen) root.editMode = false

    // Edit Mode and subject picking are both full-screen modes over the same
    // desktop, and each shrinks or covers what the other needs at full size:
    // picking must click the wallpaper at the size it is masked at, which a
    // shrunk desktop is not, and Edit Mode's affordances would sit under the
    // picker's surface. They land from separate branches, so the exclusion is
    // stated once here rather than as a gate inside either mode - a mode that
    // gated on the other's key would read `undefined` on the base that does not
    // declare it yet and take its fallback forever.
    onEditModeChanged: {
        if (root.editMode) root.clockDepthSelectOpen = false;
        // The open flag does not outlive the mode: a drawer left latched open
        // would greet the NEXT entry mid-slide, with the desktop already
        // shifted on the first frame of a shrink that is supposed to be
        // concentric. The widget menu goes with it for the same reason - it is
        // the mode's affordance, and one left open would greet the next entry
        // pointing at wherever a widget used to be.
        else {
            root.editDrawerOpen = false;
            root.editWidgetMenuOpen = false;
        }
    }
    onClockDepthSelectOpenChanged: if (root.clockDepthSelectOpen) root.editMode = false

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"
        onPressed: { root.superDown = true }
        onReleased: { root.superDown = false }
    }

    IpcHandler {
        target: "background"
        function toggleCenteredWallpaper(): void {
            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
        }
    }

     GlobalShortcut {
        name: "centeredWallpaperToggle"
        description: "Toggles centered wallpaper"
        onPressed: {
            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
        }
    }
}
