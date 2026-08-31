import qs.modules.common
import "modules/common/functions/bar_popup_slot.js" as BarPopupSlot
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "modules/common/functions/edit_mode.js" as EditMode
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    // A path here opens the fullscreen image viewer on it; "" closes it.
    property string aiImageViewerSource: ""
    // Which tab the left sidebar shows next time it opens, as the tab's
    // untranslated id rather than its index: every name in the tab bar is a
    // Translation.tr(...) call, so a deep link resolved against the label
    // stops working the moment the user changes language, and an index goes
    // stale the day a tab is inserted - the settings deep-link's own two
    // failures (1c674c8f5 ("fix(settings): address a settings deep link by
    // page id, not by its label")). Empty means "whichever tab was last
    // shown"; SidebarLeftContent consumes it on open and clears it, the way
    // GlobalStates.settingsPage is consumed.
    property string sidebarLeftTab: ""
    // The icon of the left sidebar's CURRENT page, published live by
    // SidebarLeftContent so the bar button's glyph can follow the page.
    property string sidebarLeftTabIcon: ""
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
    // The bar hover popup whose target widget is currently hovered. Adjacent
    // bar popups are separate layer-shell surfaces, so a lingering one can
    // paint over a newly opened neighbour.
    //
    // The RULES for who gets it live here, beside the slot, rather than in the
    // popup type. They used to sit in StyledPopup, which meant a shared widget
    // in modules/common/widgets arbitrated a global resource between its own
    // instances - it read this slot, wrote it, gated on `editMode`, and
    // watched for another popup taking over. A component in the shared folder
    // is meant to be presentational; that one was running a protocol.
    //
    // Now a popup only ASKS. It declares what it wants and is told; the two
    // functions below are the whole protocol, and the popup keeps no rule of
    // its own except what its own hover state means.
    property var activeBarPopup: null

    // Grant the card to `popup`, or refuse. Returns whether it now holds it.
    // The decision itself is in bar_popup_slot.js, which the QML unit suite
    // drives directly - this singleton is substituted by a double there, so a
    // rule written inline here would be tested through a copy of itself.
    function claimBarPopup(popup): bool {
        if (!popup) return false;
        const occupant = root.activeBarPopup;
        const verdict = BarPopupSlot.resolveClaim({
            editMode: root.editMode,
            isOccupant: occupant === popup,
            occupantPresent: occupant !== null && occupant !== undefined,
            occupantPinned: occupant?.pinnedOpen ?? false,
            candidatePinned: popup.pinnedOpen ?? false,
        });
        if (verdict === BarPopupSlot.REFUSE) return false;
        if (verdict === BarPopupSlot.ALREADY) return true;

        // Tell the outgoing holder before the swap, so a neighbour that was
        // only lingering on its hover grace collapses on the frame the pointer
        // lands on the new widget rather than 180ms later.
        if (occupant && occupant.releaseHoverHold)
            occupant.releaseHoverHold();
        root.activeBarPopup = popup;
        return true;
    }

    // Vacate, if `popup` is the one holding it. Called by a popup being
    // destroyed under its own card - a tray that empties, a plugin disabled -
    // which would otherwise strand the card at its last size with a live input
    // mask, and by the overlay once a card has finished exiting.
    function releaseBarPopup(popup) {
        if (root.activeBarPopup === popup)
            root.vacateBarPopup();
    }

    // Empty the slot, telling whoever held it first.
    //
    // Every path that empties it goes through here, which is the half the old
    // arrangement got for free and this one has to be deliberate about: each
    // popup used to watch the slot and drop its own hover grace on ANY change,
    // so a card exiting and Edit Mode opening both collapsed a lingering
    // neighbour. With the watching gone, the notification has to come from the
    // place that does the emptying.
    function vacateBarPopup() {
        const occupant = root.activeBarPopup;
        root.activeBarPopup = null;
        if (occupant && occupant.releaseHoverHold)
            occupant.releaseHoverHold();
    }
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

    // The mode's tab (spec §1.4): a FILTER on what the viewport draws, never a
    // mode of its own - one `editMode`, one entry, one exit ladder, and this
    // string beside it saying which of the desktop's two faces the viewport is
    // showing. Session state for the same reason the mode is, and reset on
    // exit (below) so the next entry opens on the Desktop tab rather than
    // mid-preview. The strings are edit_mode.js's constants - the ladder's
    // `desktopTab` rung fires on the same values, so a second spelling here
    // would be a tab Escape cannot leave.
    property string editTab: EditMode.DESKTOP_TAB
    // The ONE derivation of "the viewport is showing the lock screen". The
    // wallpaper, the blur, the widget filter, the islands host, both bars and
    // the dock all ask this question, and each comparing the tab itself would
    // be that many answers to it - the contract holds every other file to
    // reading this property.
    readonly property bool editLockPreview: root.editMode
        && root.editTab === EditMode.LOCKSCREEN_TAB

    // "The lock's LOOK is on screen" - the real lock session OR the tab that
    // filters the viewport into it. Separate from `editLockPreview` because
    // the two questions have different consumers: the wallpaper, the islands
    // and the widget filter ask which SOURCE to draw, and answer it per layer;
    // the palette and the wallpaper's quantizer ask which THEME the picture is
    // in, and there is only one of those for the whole shell.
    //
    // Stated here rather than spelled out at each site for the reason above:
    // the theme sites keyed on `screenLocked` alone, so the tab switched every
    // layer's source to the lock's and left the colours the desktop's - the
    // preview showed the lock's wallpaper under the desktop's palette, which
    // is a picture the lock screen never shows.
    readonly property bool lockLookActive: root.screenLocked || root.editLockPreview

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

    // The drawer's REVEAL, in screen coordinates, keyed by screen name and
    // published by each chrome surface. The two halves of the drawer's drag
    // live on different layer surfaces - the panel and its rectangle are on
    // `quickshell:editMode`, the widget being carried back into it and the
    // pointer deciding where the drop lands are on the background surface -
    // and a layer surface cannot read another window's items. So the rect is
    // published rather than derived a second time on the desktop's side, the
    // shape `clockDepthViewports` above already uses; the entry is removed
    // when a chrome surface goes, so the map's contents are always "the
    // screens whose drawer exists".
    property var editDrawerReveals: ({})
    // The screen whose drawer a dragged desktop widget is currently over, ""
    // for none - what the drawer paints its own row-press tint from. It has to
    // come from here for the same reason: the widget being carried passes
    // UNDER the chrome surface, so it cannot say on its own behalf that the
    // release will remove rather than move.
    property string editDrawerDropScreen: ""
    // ...and the drop itself, announced for the chrome side to answer. A
    // signal rather than a property pair, because dropping the same widget on
    // the drawer twice is two gestures and a property that did not change
    // announces nothing.
    signal editWidgetDroppedOnDrawer(string pluginId)

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

    // A bar-widget reorder in flight (stage 8's in-place drag). Here rather
    // than on either bar because the exit ladder is answered on the
    // BACKGROUND surface's WidgetCanvas: the keyboard and the pointer are on
    // two different layer surfaces during this gesture, and the ladder's
    // `gestureInFlight` has to see the drag to cancel it instead of exiting
    // the mode. `editReorderCancel` is the return path - the canvas raises it,
    // whichever slot holds the grab abandons, and the release still coming
    // lands on nothing.
    property bool editBarDragActive: false
    // A lock-island reorder in flight (stage 9b's drag inside the Lockscreen
    // tab's preview). A flag of its own beside the bar's rather than a shared
    // one: the two gestures live on different surfaces and are cleared by
    // different teardowns, and one flag cleared by whichever ends first would
    // strand the other in the ladder. `editReorderCancel` is shared - the
    // ladder's cancel does not care which reorder is in flight, and each
    // overlay only answers it while its own drag is.
    property bool editLockDragActive: false
    signal editReorderCancel()

    // The undo stack (spec §7.3): in memory, session-scoped, bounded, one
    // entry per COMMITTED mutation - a drag's release, a span commit, a
    // reorder drop, an add, a remove - and ONE stack across all surfaces,
    // because the user's notion of "the last thing I did" does not partition
    // by surface. Each entry is a closure over the store write that reverses
    // the mutation, captured at the call site that committed it; the
    // arithmetic (LIFO, the ~50 bound, copy-on-write) is edit_mode.js's so a
    // test can reach it. §7.4's restart argument holds with no code: the
    // stack only ever offered to reverse committed changes, and it is gone
    // with the process while the changes are on disk.
    //
    // Recording is gated on the mode: the same gestures commit all day with
    // the mode off, and a Ctrl+Z inside the mode reversing a drag made hours
    // before it would be undo reaching further back than the editor whose
    // affordance it is. The stack survives leaving and re-entering the mode
    // within a session - session-scoped is the spec's word, and clearing on
    // exit would make Done destroy the very history "I did not mean that"
    // asks for.
    property var editUndoStack: []
    // One GESTURE can commit several mutations - a group drag's release runs
    // commitPosition once per member, followers first, leader last - and "the
    // last thing I did" is the whole gesture: with one entry per member the
    // leader's sits on top and the first Ctrl+Z would move the leader alone,
    // deforming the cluster the user moved as a unit. While a batch is open,
    // pushes collect; closing it folds them into ONE composite entry that
    // replays every collected closure. The canvas opens it at a group
    // release and closes it with Qt.callLater, because the leader's own
    // commit runs later in the same signal chain and has to fall inside.
    property var editUndoBatch: null
    function editUndoBeginBatch() {
        if (root.editUndoBatch === null) root.editUndoBatch = [];
    }
    function editUndoEndBatch() {
        const entries = root.editUndoBatch;
        root.editUndoBatch = null;
        if (entries === null || entries.length === 0) return;
        if (entries.length === 1) {
            root.editUndoStack = EditMode.undoPush(root.editUndoStack, entries[0]);
            return;
        }
        // BACKWARDS. A batch of one gesture's commits is a sequence, and
        // reversing a sequence means walking it from the end: three arrow-key
        // steps on one widget push "back to 36", "back to 48", "back to 60",
        // and replaying those in order leaves it at 60 - the last entry wins
        // and the undo appears to move the widget forward. The group drag that
        // introduced batches never showed it, because its entries are one per
        // widget and independent, so any order looks right.
        root.editUndoStack = EditMode.undoPush(root.editUndoStack, () => {
            for (let index = entries.length - 1; index >= 0; index--) entries[index]();
        });
    }
    function editUndoPush(entry) {
        if (!root.editMode) return;
        if (root.editUndoBatch !== null) {
            root.editUndoBatch.push(entry);
            return;
        }
        root.editUndoStack = EditMode.undoPush(root.editUndoStack, entry);
    }
    function editUndo() {
        const popped = EditMode.undoPop(root.editUndoStack);
        root.editUndoStack = popped.stack;
        if (popped.entry !== null) popped.entry();
    }

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
        if (root.editMode) {
            root.clockDepthSelectOpen = false;
            // New claims are refused for the length of the mode (see
            // claimBarPopup); this is the popup already holding the card when
            // the mode opens, whose card would otherwise sit over the bar being
            // edited.
            root.vacateBarPopup();
            // ...and the same argument, one layer up. Both sidebars are
            // `WlrLayer.Top` and the mode's chrome is `Overlay`, so an open
            // right sidebar is painted over by the widget drawer that shares
            // its edge - reported as the drawer drawing through the sidebar.
            // Neither sidebar is EDITABLE in the mode: its surfaces have no
            // drawer section, no remove badge, no reorder the mode drives, and
            // no key in lint_edit_mode_scope.py's allowlist. So it is a panel
            // covering the thing being edited, and the answer is the one the
            // bar popup above already gets.
            //
            // Not a layer change, on either side: dropping the chrome under
            // the sidebar leaves the drawer half unusable while it is open,
            // and the mode already spends its one layer trick on
            // `EditModeChromeSurface.underneath` - which exists because
            // REMOVING the chrome popped it out of existence, and is aimed at
            // a special workspace covering the whole desktop rather than at a
            // panel on one edge of it.
            root.sidebarLeftOpen = false;
            root.sidebarRightOpen = false;
        }
        // The open flag does not outlive the mode: a drawer left latched open
        // would greet the NEXT entry mid-slide, with the desktop already
        // shifted on the first frame of a shrink that is supposed to be
        // concentric. The widget menu goes with it for the same reason - it is
        // the mode's affordance, and one left open would greet the next entry
        // pointing at wherever a widget used to be.
        else {
            root.editDrawerOpen = false;
            root.editWidgetMenuOpen = false;
            // The tab too: it is a filter on a viewport that no longer exists,
            // and one left latched would greet the next entry already showing
            // the lock screen's inputs.
            root.editTab = EditMode.DESKTOP_TAB;
            // The overlays holding a bar drag are torn down with the mode, so
            // no end-of-drag handler is guaranteed to run - clear the flag
            // here or a drag cut short by Done leaves the ladder believing a
            // gesture is still in flight.
            root.editBarDragActive = false;
            root.editLockDragActive = false;
            // The drop hint is the mode's too - a drag cut short by Done never
            // reaches the widget's own release, and a latched screen name
            // would light the next entry's drawer for a gesture nobody made.
            root.editDrawerDropScreen = "";
        }
    }
    onClockDepthSelectOpenChanged: if (root.clockDepthSelectOpen) root.editMode = false

    // ...and closing them on entry is only half of it: the corners, the bar's
    // buttons and the IPC handlers can all open a sidebar again while the mode
    // is on. The refusal lives on the flag rather than at those call sites for
    // the reason `StyledPopup.claimSlot` gives for refusing there - it is the
    // one gate every path already shares, and a rule spelled at six call sites
    // is a rule the seventh does not carry.
    onSidebarLeftOpenChanged: {
        if (root.sidebarLeftOpen && root.editMode)
            root.sidebarLeftOpen = false;
    }

    onSidebarRightOpenChanged: {
        // Before the notification sweep, not after: a refused open must not
        // count as the user having read what it would have shown them.
        if (root.sidebarRightOpen && root.editMode) {
            root.sidebarRightOpen = false;
            return;
        }
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
