import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas
import qs.modules.imi.editMode
import "modules/common/functions/edit_mode.js" as EditMode

/**
 * Drives Edit Mode's desktop with real mouse events, on a real widget canvas
 * carrying the real transform.
 *
 * The question the viewport turns on is whether a gesture still lands where the
 * pointer put it once the canvas is drawn at a scale. Nothing static can answer
 * it: the drag is computed by mapping the pointer through the moving widget
 * into the canvas frame, so the transform is supposed to cancel itself out, and
 * "supposed to" is what d2ebb5aeb ("fix(widgetCanvas): compute the drag by hand
 * - MouseArea.drag cannot track it") already measured as half a gesture lost
 * once.
 *
 * Every gesture below is driven in CANVAS coordinates, which QtTest maps
 * through the transform on the way to the window. So the same drive numbers at
 * two different scales must produce the same stored position and a different
 * screen travel - and a drag that read raw scene deltas would move by the
 * scale's worth less while passing every check that only looks at "did it
 * move".
 *
 * What this cannot see: it is a FloatingWindow, not a layer surface, so nothing
 * about the background surface - its keyboard focus, the blur backdrop's
 * compositor behaviour, the namespace - is visible here. Weston implements no
 * wlr-layer-shell.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p EditModeRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    readonly property string testScreen: "EDIT-MODE-TEST"

    readonly property int screenWidth: 1200
    readonly property int screenHeight: 700

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[EditMode] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // The same derivation the background surface applies, from the same module
    // and the same tokens: a harness that scaled by a number of its own would
    // score a transform the shell never draws.
    readonly property var viewport: EditMode.viewportGeometry({
        screenWidth: harness.screenWidth,
        screenHeight: harness.screenHeight,
        drawerWidth: Appearance.sizes.editModeDrawerWidth,
        margin: Appearance.sizes.editModeMargin,
        edgeMargin: Appearance.sizes.editModeEdgeMargin
    })
    // The drawer's shift, from the REAL scalar: GlobalStates derives
    // editDrawerProgress from the mode and the open flag exactly as the shell
    // runs it, so these steps drive the derivation that ships rather than a
    // number of the harness's own.
    readonly property real drawerShift: EditMode.drawerTravel(harness.viewport)
        * GlobalStates.editDrawerProgress
    readonly property var applied: EditMode.atProgress(harness.viewport,
                                                       GlobalStates.editMode ? 1 : 0,
                                                       harness.drawerShift)

    function manifestFor(id, grid) {
        return {
            id: id,
            name: id,
            grid: grid,
            desktopWidget: { type: "Item" }
        };
    }

    readonly property var resizableManifest: harness.manifestFor("edit-resize-probe", {
        cols: 3, rows: 2,
        sizes: [{ cols: 3, rows: 2 }, { cols: 2, rows: 2 }, { cols: 2, rows: 1 }]
    })
    readonly property var fixedManifest: harness.manifestFor("edit-move-probe", { cols: 2, rows: 1 })

    FloatingWindow {
        visible: true
        implicitWidth: harness.screenWidth
        implicitHeight: harness.screenHeight
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "EditModeDriver"
        }

        WidgetCanvas {
            id: canvas
            width: harness.screenWidth
            height: harness.screenHeight
            editMode: GlobalStates.editMode
            selectionEnabled: true
            // No animation here: the entry curve is the shell's business and a
            // gesture driven mid-flight would score a scale nothing settled at.
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(
                    harness.applied.scale, 0, 0, harness.applied.x,
                    0, harness.applied.scale, 0, harness.applied.y,
                    0, 0, 1, 0,
                    0, 0, 0, 1)
            }

            PluginWidget {
                id: resizableWidget
                manifest: harness.resizableManifest
                screenName: harness.testScreen
                screenWidth: harness.screenWidth
                screenHeight: harness.screenHeight
                scaledScreenWidth: harness.screenWidth
                scaledScreenHeight: harness.screenHeight
                wallpaperScale: 1
            }

            PluginWidget {
                id: movableWidget
                manifest: harness.fixedManifest
                screenName: harness.testScreen
                screenWidth: harness.screenWidth
                screenHeight: harness.screenHeight
                scaledScreenWidth: harness.screenWidth
                scaledScreenHeight: harness.screenHeight
                wallpaperScale: 1
            }

            // The menu's card, driven directly: the window that hosts it on
            // the desktop is a layer surface no harness can build, and the
            // card is where the writes live. Parked at the canvas's far right,
            // clear of every gesture the steps above drive (their canvas
            // coordinates all stay left of x=700); QtTest maps clicks through
            // whatever transform the mode has applied, the same way it maps
            // the widget gestures.
            EditWidgetMenuContent {
                id: menuContent
                x: 920
                y: 8
                width: 260
                height: implicitHeight
                manifest: harness.resizableManifest
            }

            // A widget that can stop existing while its menu is open - the
            // static two above cannot be destroy()ed. The FadeLoader shape a
            // disabled plugin actually goes through.
            Loader {
                id: transientLoader
                active: false
                sourceComponent: PluginWidget {
                    manifest: harness.manifestFor("edit-vanish-probe", { cols: 2, rows: 1 })
                    screenName: harness.testScreen
                    screenWidth: harness.screenWidth
                    screenHeight: harness.screenHeight
                    scaledScreenWidth: harness.screenWidth
                    scaledScreenHeight: harness.screenHeight
                    wallpaperScale: 1
                }
            }
        }
    }

    // The answer to a widget dropped back on the drawer. Built directly, which
    // is the whole reason the write lives in a `QtObject` rather than on the
    // chrome's `PanelWindow`: weston implements no wlr-layer-shell, so a write
    // put on that surface would be a write no harness can reach.
    EditModeDrawerDrop {}

    function placeWidgets() {
        PluginState.setPosition("edit-resize-probe", harness.testScreen,
                                { x: 36, y: 36, placementStrategy: "free" });
        PluginState.setPosition("edit-move-probe", harness.testScreen,
                                { x: 36, y: 396, placementStrategy: "free" });
    }

    // ---- gestures, driven in canvas coordinates --------------------------

    function dragBy(widget, dx, dy) {
        const x = widget.x + widget.width / 2;
        const y = widget.y + widget.height / 2;
        driver.mousePress(canvas, x, y, Qt.LeftButton);
        driver.mouseMove(canvas, x + dx / 2, y + dy / 2, 20, Qt.LeftButton);
        driver.mouseMove(canvas, x + dx, y + dy, 20, Qt.LeftButton);
        driver.mouseRelease(canvas, x + dx, y + dy, Qt.LeftButton);
    }

    // The grip is 16x16 anchored to the widget's bottom-right with the host's
    // own spacing token, so a token change moves the gesture with it.
    function gripCenter(widget) {
        const inset = Appearance.spacing.space100 + 8;
        return { x: widget.x + widget.width - inset, y: widget.y + widget.height - inset };
    }

    function dragGripBy(widget, dx, dy) {
        const point = harness.gripCenter(widget);
        driver.mousePress(canvas, point.x, point.y, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx / 2, point.y + dy / 2, 20, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx, point.y + dy, 20, Qt.LeftButton);
        driver.mouseRelease(canvas, point.x + dx, point.y + dy, Qt.LeftButton);
    }

    // The drawer's reveal, in screen coordinates. On the shell this is the
    // chrome surface's own rect, published across the window boundary; that
    // surface is a `PanelWindow` this harness cannot build, so the harness
    // stands in with the SAME module call rather than a rectangle of its own.
    readonly property var drawerReveal: EditMode.drawerRect(harness.viewport,
        GlobalStates.editMode ? 1 : 0, GlobalStates.editDrawerProgress,
        harness.screenWidth, harness.screenHeight)

    function publishReveal() {
        const published = {};
        published[harness.testScreen] = harness.drawerReveal;
        GlobalStates.editDrawerReveals = published;
    }

    // The hint the drawer paints, sampled while the pointer is still down: it
    // is cleared by the release, so a check taken after the gesture reads ""
    // whether or not the drawer ever lit up.
    property string hintDuringDrag: ""

    // A drag whose RELEASE lands on the drawer's reveal. Driven to a screen
    // point mapped back into canvas coordinates, because that is the frame
    // every other gesture here is driven in and QtTest maps it through the
    // mode's transform on the way to the window.
    function dragOntoDrawer(widget) {
        const reveal = harness.drawerReveal;
        const target = canvas.mapFromItem(null,
            reveal.x + reveal.width / 2, reveal.y + reveal.height / 2);
        const x = widget.x + widget.width / 2;
        const y = widget.y + widget.height / 2;
        driver.mousePress(canvas, x, y, Qt.LeftButton);
        driver.mouseMove(canvas, (x + target.x) / 2, (y + target.y) / 2, 20, Qt.LeftButton);
        driver.mouseMove(canvas, target.x, target.y, 20, Qt.LeftButton);
        harness.hintDuringDrag = GlobalStates.editDrawerDropScreen;
        driver.mouseRelease(canvas, target.x, target.y, Qt.LeftButton);
    }

    function storedPosition(id) { return PluginState.position(id, harness.testScreen); }
    function storedSize(id) { return PluginState.option(id, "__gridSize", ""); }

    function screenRectOf(widget) { return widget.mapToItem(null, 0, 0); }

    property var travelUnscaled: null
    property var travelScaled: null
    property var before: null
    property real scaleBeforeDrawer: 1

    readonly property var steps: [
        // ---- the same gesture, unscaled and scaled ------------------------
        //
        // Scored first and against each other: everything else about the mode
        // is a property, and this is the only thing the viewport can break.
        () => {
            harness.check("the mode is off to begin with", !GlobalStates.editMode
                          && Math.abs(harness.applied.scale - 1) < 1e-9);
            harness.before = harness.screenRectOf(movableWidget);
        },
        () => harness.dragBy(movableWidget, 120, 60),
        () => {
            const after = harness.screenRectOf(movableWidget);
            harness.travelUnscaled = { x: after.x - harness.before.x, y: after.y - harness.before.y };
            const stored = harness.storedPosition("edit-move-probe");
            harness.check("unscaled: the widget lands 120x60 further on, snapped to the lattice",
                          Math.round(stored.x) === 156 && Math.round(stored.y) === 456);
        },

        () => { GlobalStates.editMode = true; harness.placeWidgets(); },
        () => {
            harness.check("the viewport shrinks the canvas without resizing it",
                          harness.applied.scale < 1
                          && canvas.width === harness.screenWidth
                          && canvas.height === harness.screenHeight);
            harness.check("the widget's own box is untouched by the transform",
                          Math.round(movableWidget.width)
                              === Math.round(Appearance.sizes.widgetGridSpanX(2))
                          && Math.round(movableWidget.x) === 36);
            harness.before = harness.screenRectOf(movableWidget);
        },
        () => harness.dragBy(movableWidget, 120, 60),
        () => {
            const after = harness.screenRectOf(movableWidget);
            harness.travelScaled = { x: after.x - harness.before.x, y: after.y - harness.before.y };
            const stored = harness.storedPosition("edit-move-probe");
            // The point of the whole stage: the pointer travelled the same
            // distance ACROSS THE DESKTOP and the widget went with it, so the
            // stored position is identical to the unscaled run.
            harness.check("scaled: the same gesture stores the same position",
                          Math.round(stored.x) === 156 && Math.round(stored.y) === 456);
            // ...while covering less of the screen, which is what proves the
            // transform was actually applied rather than the check being
            // trivially true.
            harness.check("scaled: the same gesture covers less screen",
                          Math.abs(harness.travelScaled.x)
                              < Math.abs(harness.travelUnscaled.x) - 1
                          && Math.abs(harness.travelScaled.y)
                              < Math.abs(harness.travelUnscaled.y) - 1);
        },

        // ---- the drawer: a translation, driven through the real scalars ----
        //
        // Opening the drawer must move the canvas's origin left by exactly
        // drawerTravel and change nothing else about the transform - and a
        // drag taken through the shifted matrix must still land where the
        // pointer put it, which is the half no arithmetic test can answer:
        // the drag cancels the transform by mapping through the moving item,
        // and a translation is one more term it has to cancel.
        () => {
            harness.scaleBeforeDrawer = harness.applied.scale;
            GlobalStates.editDrawerOpen = true;
            harness.placeWidgets();
        },
        () => {
            harness.check("the open drawer translates the canvas and does not resize it",
                          harness.drawerShift > 0
                          && canvas.width === harness.screenWidth
                          && canvas.height === harness.screenHeight
                          && Math.abs(harness.applied.scale - harness.scaleBeforeDrawer) < 1e-9);
            const origin = canvas.mapToItem(null, 0, 0);
            harness.check("...and by exactly the drawer's travel",
                          Math.abs(origin.x - (harness.viewport.x - harness.drawerShift)) < 0.5);
        },
        () => harness.dragBy(movableWidget, 120, 60),
        () => {
            const stored = harness.storedPosition("edit-move-probe");
            harness.check("shifted: the same gesture stores the same position",
                          Math.round(stored.x) === 156 && Math.round(stored.y) === 456);
            GlobalStates.editDrawerOpen = false;
        },
        () => {
            const origin = canvas.mapToItem(null, 0, 0);
            harness.check("closing the drawer puts the desktop back",
                          harness.drawerShift === 0
                          && Math.abs(origin.x - harness.viewport.x) < 0.5);
        },

        // ---- the affordances the mode forces on, and the one it does not --
        //
        // The lattice belongs to the GESTURE in the mode as well as out of it.
        // What the mode overrides is the config switch, so the switch is turned
        // OFF here: what these steps score is then the mode's own behaviour
        // rather than the user's preference leaking into it.
        () => {
            Config.options.background.showGrid = false;
            harness.check("in the mode at rest there is no lattice",
                          !canvas.gridVisible && !canvas.showGrid);
            harness.check("the frost stands down for the mode",
                          resizableWidget.frostSuspended);
        },
        () => {
            // A press is not a drag, and this is the distinction the whole
            // change turns on: every one of a widget's own controls - the
            // resize grip, the right-click, a click that selects - presses
            // without travelling, and a lattice that flashed up under each of
            // them would be worse than one that never went away. 4 canvas
            // pixels is comfortably inside AbstractWidget's drag.threshold at
            // this scale; the drag in the next step is ten times past it.
            const x = movableWidget.x + movableWidget.width / 2;
            const y = movableWidget.y + movableWidget.height / 2;
            driver.mousePress(canvas, x, y, Qt.LeftButton);
            driver.mouseMove(canvas, x + 4, y + 4, 20, Qt.LeftButton);
            harness.check("a press that has not travelled draws none of it",
                          !movableWidget.dragging && !canvas.gridVisible);
            driver.mouseRelease(canvas, x + 4, y + 4, Qt.LeftButton);
        },
        () => {
            const x = movableWidget.x + movableWidget.width / 2;
            const y = movableWidget.y + movableWidget.height / 2;
            driver.mousePress(canvas, x, y, Qt.LeftButton);
            driver.mouseMove(canvas, x + 120, y, 20, Qt.LeftButton);
            harness.check("...and a drag past the threshold brings it up",
                          movableWidget.dragging && canvas.gridVisible);
            driver.mouseRelease(canvas, x + 120, y, Qt.LeftButton);
        },
        () => {
            harness.check("...and the release takes it away again",
                          !canvas.showGrid && !canvas.gridVisible);
            Config.options.background.showGrid = true;
            GlobalStates.editMode = false;
        },
        () => {
            harness.check("and the frost comes back", !resizableWidget.frostSuspended);
            GlobalStates.editMode = true;
        },

        // ---- the global lock, suppressed rather than written --------------
        () => {
            GlobalStates.editMode = false;
            Config.options.background.widgetsLocked = true;
            harness.placeWidgets();
        },
        () => harness.dragBy(movableWidget, 120, 0),
        () => harness.check("locked and not editing: the drag is refused",
                            Math.round(harness.storedPosition("edit-move-probe").x) === 36),
        () => { GlobalStates.editMode = true; },
        () => harness.dragBy(movableWidget, 120, 0),
        () => {
            harness.check("locked and editing: the drag moves the widget",
                          Math.round(harness.storedPosition("edit-move-probe").x) === 156);
            harness.check("...and the stored lock is untouched",
                          Config.options.background.widgetsLocked === true);
        },
        () => {
            PluginState.setOption("edit-move-probe", "positionLocked", true);
            harness.placeWidgets();
        },
        () => harness.dragBy(movableWidget, 120, 0),
        () => {
            harness.check("a widget the user pinned still refuses",
                          Math.round(harness.storedPosition("edit-move-probe").x) === 36);
            PluginState.setOption("edit-move-probe", "positionLocked", false);
            Config.options.background.widgetsLocked = false;
        },

        // ---- the grip, shown by the mode and driven at scale ---------------
        //
        // No hover first: in the mode the grip is already out, so the press
        // reaches it. That is the affordance half.
        //
        // The 160px pull is the frame half, and it is chosen to be
        // discriminating rather than merely large. Shrinking needs the target
        // to come inside the smaller span's edge, which is 144px away
        // (3x2 -> 2x2), so 160 canvas pixels give one span - while the same
        // gesture measured in SCENE pixels is 160 x the mode's scale, which
        // falls short of 144 and gives none. Measured: a 150px pull committed
        // 2x2 under BOTH frames, so the first version of this check was
        // vacuous exactly the way a probe taken at a wall is.
        () => { harness.placeWidgets(); },
        () => harness.dragGripBy(resizableWidget, -160, 0),
        () => {
            harness.check("the grip is out for the mode and resizes at scale",
                          harness.storedSize("edit-resize-probe") === "2x2");
            harness.check("...and the widget did not walk",
                          Math.round(harness.storedPosition("edit-resize-probe").x) === 36
                          && Math.round(harness.storedPosition("edit-resize-probe").y) === 36);
        },

        // ---- and a widget that stops existing mid-drag ---------------------
        //
        // Through `widgetRemoved`, which is the call AbstractWidget's
        // Component.onDestruction makes - a statically declared widget cannot
        // be destroy()ed, and what matters is that the canvas answers that
        // entry point rather than how the widget came to be gone. Nothing else
        // can take the lattice down here: a destroyed widget never reaches
        // onDraggingChanged, so a FadeLoader dropping a plugin from under the
        // pointer (disabling it from Settings mid-drag) used to be invisible
        // while the grid was up for the whole mode and would now leave it up
        // for the rest of the mode.
        () => { harness.placeWidgets(); },
        () => {
            const x = movableWidget.x + movableWidget.width / 2;
            const y = movableWidget.y + movableWidget.height / 2;
            driver.mousePress(canvas, x, y, Qt.LeftButton);
            driver.mouseMove(canvas, x + 120, y, 20, Qt.LeftButton);
            canvas.widgetRemoved(movableWidget);
            harness.check("a widget that stops existing mid-drag takes the lattice with it",
                          !canvas.showGrid);
            driver.mouseRelease(canvas, x + 120, y, Qt.LeftButton);
        },

        // ---- a group drag ends the lattice the same way -------------------
        //
        // Scored separately because only the LEADER reports a drag: a follower
        // is moved imperatively by the canvas and its `dragging` is never true,
        // so "the lattice goes down when the gesture ends" runs off one widget's
        // flag while more than one widget was moving. A follower that somehow
        // did raise it would leave the grid up for the rest of the mode.
        () => { canvas.clearSelection(); harness.placeWidgets(); },
        () => {
            // A marquee from empty canvas across both widgets. Overlap, not
            // containment, is what selectWidgetsInRect takes.
            driver.mousePress(canvas, 8, 8, Qt.LeftButton);
            driver.mouseMove(canvas, 600, 600, 20, Qt.LeftButton);
            driver.mouseRelease(canvas, 600, 600, Qt.LeftButton);
        },
        () => harness.check("a marquee over both widgets selects both",
                            canvas.selectedWidgets.length === 2),
        () => harness.dragBy(movableWidget, 60, 0),
        () => {
            harness.check("a group drag carries the follower",
                          Math.round(harness.storedPosition("edit-resize-probe").x) === 96);
            harness.check("...and the lattice goes down when the group's drag ends",
                          !canvas.showGrid && !canvas.gridVisible);
            canvas.clearSelection();
        },

        // ---- arrow-key nudge: one lattice cell, the group rigid -----------
        //
        // The keys themselves are not driven here. A key event has no explicit
        // target - TestCase sends it to the focused item of ITS OWN window -
        // and the canvas takes its focus from the background LAYER surface,
        // which weston does not implement. What a harness can hold is
        // everything after the key: the step, the group's rigidity, the clamp
        // at the wall, the store write and the undo grain. That the surface
        // receives real compositor keys at all was measured once, in a nested
        // Hyprland, for the undo that shares this handler (spec §11.4 probe 4).
        () => { canvas.clearSelection(); harness.placeWidgets(); },
        () => {
            canvas.applySelection([movableWidget]);
            harness.before = { x: movableWidget.x, y: movableWidget.y };
            canvas.nudgeSelection(1, 0);
        },
        () => {
            harness.check("an arrow moves the widget one lattice cell",
                          movableWidget.x - harness.before.x === canvas.gridSize);
            harness.check("...and the move is in the store, not only on screen",
                          Math.round(harness.storedPosition("edit-move-probe").x)
                              === Math.round(harness.before.x + canvas.gridSize));
        },
        () => {
            // Off the lattice on purpose: the edge snap parks a widget one gap
            // off a neighbour's edge, and a stored position can predate a
            // lattice change. The first press is the one that gets it back on.
            movableWidget.x = harness.before.x + 5;
            movableWidget.commitPosition();
            harness.before = { x: movableWidget.x, y: movableWidget.y };
            canvas.nudgeSelection(1, 0);
        },
        () => harness.check("a press from off the lattice lands back on it",
                            movableWidget.x % canvas.gridSize === 0),
        () => {
            // Both widgets, and the follower is the one against the wall.
            canvas.clearSelection();
            harness.placeWidgets();
            canvas.applySelection([movableWidget, resizableWidget]);
            resizableWidget.moveTargetBy(
                resizableWidget.clampX(Infinity) - resizableWidget.targetX, 0);
            resizableWidget.commitPlacement(0, resizableWidget.targetY);
            harness.before = {
                leader: movableWidget.targetX, follower: resizableWidget.targetX
            };
            canvas.nudgeSelection(1, 0);
        },
        () => {
            harness.check("a member already at the wall does not pass it",
                          resizableWidget.targetX === harness.before.follower);
            // The cluster is rigid: the one with room does not travel on
            // alone, which is the answer a group drag gives at an edge and
            // the reason the delta is shrunk once for every member rather
            // than clamped per widget.
            harness.check("...and the member with room stays with it",
                          movableWidget.targetX === harness.before.leader);
            canvas.clearSelection();
        },
        () => {
            // One burst, one undo entry: a held arrow key delivers a press
            // every ~30ms, and an entry each would fill a fifty-deep stack in
            // under two seconds.
            harness.placeWidgets();
            GlobalStates.editUndoStack = [];
            canvas.applySelection([movableWidget]);
            harness.before = { x: movableWidget.targetX, y: movableWidget.targetY };
            canvas.nudgeSelection(1, 0);
            canvas.nudgeSelection(1, 0);
            canvas.nudgeSelection(1, 0);
            harness.check("three presses travel three cells",
                          movableWidget.targetX - harness.before.x === canvas.gridSize * 3);
            // Asserted in THIS step rather than the next: the batch closes on
            // a 400ms timer (a key repeat has no release to hang it on) and
            // the harness ticks at 700, so by the next step it is already
            // closed and the check would be vacuous.
            harness.check("...a burst mid-flight has not pushed its entry yet",
                          GlobalStates.editUndoStack.length === 0);
        },
        () => {
            harness.check("a settled burst is exactly one undo entry",
                          GlobalStates.editUndoStack.length === 1);
            GlobalStates.editUndo();
        },
        () => {
            harness.check("undoing the burst returns the widget to where it started",
                          Math.round(harness.storedPosition("edit-move-probe").x)
                              === Math.round(harness.before.x));
            harness.check("...all three cells at once, not one press at a time",
                          GlobalStates.editUndoStack.length === 0);
            canvas.clearSelection();
        },

        // ---- leaving mid-drag cancels, it does not commit ------------------
        () => { harness.placeWidgets(); },
        () => {
            const x = movableWidget.x + movableWidget.width / 2;
            const y = movableWidget.y + movableWidget.height / 2;
            driver.mousePress(canvas, x, y, Qt.LeftButton);
            driver.mouseMove(canvas, x + 240, y, 20, Qt.LeftButton);
            harness.check("the drag is in flight", movableWidget.dragging
                          && Math.round(movableWidget.x) > 200);
            GlobalStates.editMode = false;
            // The release still arrives, because the pointer was never let go
            // of - and it must commit nothing.
            driver.mouseRelease(canvas, x + 240, y, Qt.LeftButton);
        },
        // Scored a tick later: the widget travels back on its position
        // Behavior, so the frame the cancel happened on is one this check must
        // not read.
        () => {
            harness.check("leaving the mode puts the widget back",
                          !movableWidget.dragging && Math.round(movableWidget.x) === 36);
            harness.check("...and stores the position the press found",
                          Math.round(harness.storedPosition("edit-move-probe").x) === 36);
            // The gesture flag rather than gridVisible, because the mode has
            // ended and gridVisible has a second reason to be false by now. The
            // question here is whether the cancel reached setDragging at all -
            // a cancel that did not would leave the lattice armed for the next
            // time the mode opens.
            harness.check("...and the cancel takes the lattice with the gesture",
                          !canvas.showGrid);
        },

        // ---- the right-click: the menu in the mode, the lock outside it ----
        //
        // The same click means two things on the two sides of the mode
        // boundary, and both halves are scored so the branch cannot rot in
        // either direction: outside, the one quick gesture for the global lock
        // (spec §4.1's table changes only the in-mode column); inside, the
        // per-widget menu, anchored at the click's SCREEN position - which is
        // the widget mapping through the mode's own transform, the half a
        // hand-multiplied scale gets wrong at every scale but 1.
        () => {
            harness.placeWidgets();
            Config.options.background.widgetsLocked = false;
        },
        () => {
            const x = movableWidget.x + movableWidget.width / 2;
            const y = movableWidget.y + movableWidget.height / 2;
            driver.mouseClick(canvas, x, y, Qt.RightButton);
            harness.check("outside the mode a right-click still toggles the global lock",
                          Config.options.background.widgetsLocked === true
                          && !GlobalStates.editWidgetMenuOpen);
            Config.options.background.widgetsLocked = false;
        },
        () => { GlobalStates.editMode = true; },
        () => {
            const x = movableWidget.x + movableWidget.width / 2;
            const y = movableWidget.y + movableWidget.height / 2;
            driver.mouseClick(canvas, x, y, Qt.RightButton);
            harness.check("in the mode the same click asks for the widget's menu instead",
                          GlobalStates.editWidgetMenuOpen
                          && GlobalStates.editWidgetMenuPluginId === "edit-move-probe"
                          && GlobalStates.editWidgetMenuScreenName === harness.testScreen
                          && Config.options.background.widgetsLocked === false);
            const mapped = canvas.mapToItem(null, x, y);
            harness.check("...anchored through the mode's own transform",
                          Math.abs(GlobalStates.editWidgetMenuX - mapped.x) < 1.5
                          && Math.abs(GlobalStates.editWidgetMenuY - mapped.y) < 1.5);
            GlobalStates.editWidgetMenuOpen = false;
        },

        // ---- a widget destroyed while its menu is open vacates it ----------
        () => {
            PluginState.setPosition("edit-vanish-probe", harness.testScreen,
                                    { x: 396, y: 396, placementStrategy: "free" });
            transientLoader.active = true;
        },
        () => {
            const transient = transientLoader.item;
            driver.mouseClick(canvas, transient.x + transient.width / 2,
                              transient.y + transient.height / 2, Qt.RightButton);
            harness.check("the menu opens for the transient widget",
                          GlobalStates.editWidgetMenuOpen
                          && GlobalStates.editWidgetMenuPluginId === "edit-vanish-probe");
            transientLoader.active = false;
        },
        () => {
            harness.check("a widget destroyed while its menu is open vacates it",
                          !GlobalStates.editWidgetMenuOpen);
        },

        // ---- the menu's rows: Pin, the Size stepper, Remove ----------------
        //
        // Real clicks on the real card, read back from the real stores. The
        // stepper's whole contract is that it INDEXES offeredGridSizes - the
        // manifest's own order, [3x2, 2x2, 2x1] here - and never sees a pixel
        // or a pointer delta, so the checks walk the list to both of its ends
        // and read the stored span after every step.
        () => {
            Config.options.plugins.enabled = ["edit-resize-probe"];
            PluginState.setOption("edit-resize-probe", "positionLocked", false);
            // Seeded, not inherited from the grip section's end state: the
            // stepper checks walk the offered order from its middle.
            PluginState.setOption("edit-resize-probe", "__gridSize", "2x2");
        },
        () => {
            const pin = driver.findChild(menuContent, "editMenuPin");
            driver.mouseClick(pin, pin.width / 2, pin.height / 2, Qt.LeftButton);
            harness.check("the menu's Pin writes the stored positionLocked and the row follows",
                          PluginState.option("edit-resize-probe", "positionLocked", false) === true
                          && menuContent.pinned === true);
        },
        () => {
            const pin = driver.findChild(menuContent, "editMenuPin");
            driver.mouseClick(pin, pin.width / 2, pin.height / 2, Qt.LeftButton);
            harness.check("...and a second click unpins",
                          PluginState.option("edit-resize-probe", "positionLocked", true) === false
                          && menuContent.pinned === false);
        },
        () => {
            const down = driver.findChild(menuContent, "editMenuSizeDown");
            driver.mouseClick(down, down.width / 2, down.height / 2, Qt.LeftButton);
            harness.check("the stepper steps back through the offered order",
                          harness.storedSize("edit-resize-probe") === "3x2");
        },
        () => {
            const up = driver.findChild(menuContent, "editMenuSizeUp");
            driver.mouseClick(up, up.width / 2, up.height / 2, Qt.LeftButton);
            driver.mouseClick(up, up.width / 2, up.height / 2, Qt.LeftButton);
            harness.check("...and forward to the other end",
                          harness.storedSize("edit-resize-probe") === "2x1");
        },
        () => {
            const up = driver.findChild(menuContent, "editMenuSizeUp");
            driver.mouseClick(up, up.width / 2, up.height / 2, Qt.LeftButton);
            harness.check("...and holds at the end of the offered list",
                          harness.storedSize("edit-resize-probe") === "2x1");
        },
        () => {
            const remove = driver.findChild(menuContent, "editMenuRemove");
            driver.mouseClick(remove, remove.width / 2, remove.height / 2, Qt.LeftButton);
            harness.check("Remove takes the widget out of plugins.enabled",
                          Config.options.plugins.enabled.length === 0);
        },

        // ---- the Lockscreen tab: a filter, and Escape climbs off it --------
        //
        // The ladder's desktopTab rung is pure and tst-covered; what only a
        // real key through the real canvas handler can show is the WIRING -
        // that the caller passes the live tab and answers the rung by moving
        // it, rather than falling through to the exit. The key needs the
        // canvas focused, which the shell does on mode entry; the steps above
        // clicked other controls, so it is re-asserted rather than assumed.
        () => {
            GlobalStates.editMode = true;
            GlobalStates.editTab = EditMode.LOCKSCREEN_TAB;
            harness.check("the preview flag follows the mode and the tab",
                          GlobalStates.editLockPreview === true);
        },
        () => {
            canvas.forceActiveFocus();
            driver.keyClick(Qt.Key_Escape);
            harness.check("Escape on the Lockscreen tab returns to Desktop with the mode still on",
                          GlobalStates.editTab === EditMode.DESKTOP_TAB
                          && GlobalStates.editMode === true
                          && GlobalStates.editLockPreview === false);
        },
        () => {
            canvas.forceActiveFocus();
            driver.keyClick(Qt.Key_Escape);
            harness.check("...and the next Escape leaves the mode",
                          GlobalStates.editMode === false);
        },
        () => {
            GlobalStates.editMode = true;
            GlobalStates.editTab = EditMode.LOCKSCREEN_TAB;
            GlobalStates.editMode = false;
            harness.check("leaving the mode resets the tab with the drawer and the menu",
                          GlobalStates.editTab === EditMode.DESKTOP_TAB
                          && GlobalStates.editLockPreview === false);
        },

        // ---- undo (spec §7.3): the last committed mutation, reversed ------
        //
        // Ctrl+Z's key delivery is a compositor question no weston harness
        // can see (probe 4 answered it against a nested Hyprland); what this
        // drives is everything behind the key: the commit paths recording
        // entries, the entries reversing the store AND the drawn widget, and
        // the gate that keeps the mode's history the mode's.
        () => {
            GlobalStates.editMode = true;
            harness.placeWidgets();
        },
        () => {
            // The earlier steps' own commits recorded entries; this section
            // starts from an empty stack so its counts mean something.
            GlobalStates.editUndoStack = [];
            GlobalStates.editUndo();
            harness.check("an empty stack undoes nothing and breaks nothing",
                          GlobalStates.editUndoStack.length === 0
                          && GlobalStates.editMode === true);
        },
        () => {
            harness.dragBy(movableWidget, 96, 0);
            harness.check("a drag committed in the mode records one entry",
                          GlobalStates.editUndoStack.length === 1
                          && Math.round(harness.storedPosition("edit-move-probe").x) === 132);
        },
        () => {
            GlobalStates.editUndo();
            harness.check("undo returns the store to the position the drag found",
                          Math.round(harness.storedPosition("edit-move-probe").x) === 36
                          && GlobalStates.editUndoStack.length === 0);
        },
        () => {
            harness.check("...and the widget is drawn there again",
                          Math.round(movableWidget.x) === 36);
        },
        () => {
            // The gate. A commit with the mode off records nothing: the same
            // gesture commits all day outside the editor, and Ctrl+Z inside
            // it must not reach back past the mode's own affordance.
            GlobalStates.editMode = false;
        },
        () => {
            harness.dragBy(movableWidget, 96, 0);
            harness.check("the same drag outside the mode records nothing",
                          GlobalStates.editUndoStack.length === 0
                          && Math.round(harness.storedPosition("edit-move-probe").x) === 132);
        },
        () => {
            // A span commit, through the one path the grip and the menu's
            // stepper both call, undone back to the stored choice it found.
            GlobalStates.editMode = true;
            PluginState.setOption("edit-resize-probe", "__gridSize", "3x2");
            GlobalStates.editUndoStack = [];
        },
        () => {
            resizableWidget.commitGridSize({ cols: 2, rows: 1 });
            harness.check("a span commit records the old choice",
                          GlobalStates.editUndoStack.length === 1
                          && harness.storedSize("edit-resize-probe") === "2x1");
        },
        () => {
            GlobalStates.editUndo();
            harness.check("undo puts the stored span back",
                          harness.storedSize("edit-resize-probe") === "3x2"
                          && GlobalStates.editUndoStack.length === 0);
        },
        () => {
            // A FIRST-EVER span commit undone leaves the store the way it
            // found it: no stored key, so the read answers the caller's
            // fallback again. A persisted null here would answer null past
            // every later fallback instead.
            PluginState.setOption("edit-move-probe", "__gridSize", null);
            GlobalStates.editUndoStack = [];
        },
        () => {
            movableWidget.commitGridSize({ cols: 2, rows: 1 });
            harness.check("a first-ever span commit stores and records",
                          harness.storedSize("edit-move-probe") === "2x1"
                          && GlobalStates.editUndoStack.length === 1);
        },
        () => {
            GlobalStates.editUndo();
            harness.check("undoing it removes the key instead of storing null",
                          harness.storedSize("edit-move-probe") === ""
                          && PluginState.option("edit-move-probe", "__gridSize", "fallback") === "fallback");
        },
        () => {
            // One gesture, one entry: a group release folds every member's
            // commit into a single composite, and one Ctrl+Z restores the
            // whole cluster - not the leader alone, which is what one entry
            // per member would do with the leader's push landing last.
            harness.placeWidgets();
        },
        () => {
            driver.mousePress(canvas, 8, 8, Qt.LeftButton);
            driver.mouseMove(canvas, 600, 600, 20, Qt.LeftButton);
            driver.mouseRelease(canvas, 600, 600, Qt.LeftButton);
        },
        () => {
            GlobalStates.editUndoStack = [];
            harness.dragBy(movableWidget, 60, 0);
        },
        () => {
            // Its own step: the batch folds on Qt.callLater, a turn after
            // the release chain, so a depth read in the drag's own step
            // still sees the batch open and the stack empty.
            harness.check("a group release records ONE entry for the gesture",
                          GlobalStates.editUndoStack.length === 1
                          && Math.round(harness.storedPosition("edit-move-probe").x) === 96
                          && Math.round(harness.storedPosition("edit-resize-probe").x) === 96);
        },
        () => {
            GlobalStates.editUndo();
            harness.check("...and one undo restores the whole cluster",
                          Math.round(harness.storedPosition("edit-move-probe").x) === 36
                          && Math.round(harness.storedPosition("edit-resize-probe").x) === 36);
            canvas.clearSelection();
            GlobalStates.editMode = false;
        },

        // ---- a widget dragged back INTO the drawer leaves the desktop ------
        //
        // The inverse of §8.3's drag out, and the half nothing static can
        // answer: the decision is made on the background surface from a
        // rectangle published by another window, and the release has to reach
        // the removal INSTEAD of the commit that runs on every other release.
        // Both directions are driven, because "the widget was removed" is also
        // what a release handler that removed on every drop would report.
        () => {
            GlobalStates.editMode = true;
            GlobalStates.editTab = EditMode.DESKTOP_TAB;
            Config.options.plugins.enabled = ["edit-move-probe", "edit-resize-probe"];
            harness.placeWidgets();
            GlobalStates.editDrawerOpen = true;
        },
        () => {
            harness.publishReveal();
            GlobalStates.editUndoStack = [];
        },
        () => {
            harness.check("the drawer's reveal reaches the widget on the other surface",
                          movableWidget.editDrawerReveal !== null
                          && movableWidget.editDrawerReveal.width > 0);
            harness.dragBy(movableWidget, 96, 0);
        },
        () => {
            // The control. A drag ending on the DESKTOP still commits a move,
            // so what the next steps score is the drop POINT and not the mode.
            harness.check("a drag that ends on the desktop still commits a move",
                          Config.options.plugins.enabled.length === 2
                          && Math.round(harness.storedPosition("edit-move-probe").x) === 132);
            harness.hintDuringDrag = "";
            harness.dragOntoDrawer(movableWidget);
        },
        () => {
            harness.check("a drag that ends on the drawer takes the widget off the desktop",
                          Config.options.plugins.enabled.indexOf("edit-move-probe") === -1
                          && Config.options.plugins.enabled.indexOf("edit-resize-probe") !== -1);
            // The store still says where the widget WAS. That is not a detail:
            // it is the whole of how undo puts the widget back at the position
            // it had rather than under the panel it was dropped on.
            harness.check("...and commits no position on the way out",
                          Math.round(harness.storedPosition("edit-move-probe").x) === 132
                          && Math.round(harness.storedPosition("edit-move-probe").y) === 396);
            harness.check("...as exactly one undo entry",
                          GlobalStates.editUndoStack.length === 1);
            // Sampled with the pointer still down, because the release clears
            // it - a check taken after the gesture reads "" whether or not the
            // drawer ever lit up.
            harness.check("...and the drawer was told it was the drop target",
                          harness.hintDuringDrag === harness.testScreen);
            harness.check("...which the release clears again",
                          GlobalStates.editDrawerDropScreen === "");
        },
        () => {
            GlobalStates.editUndo();
            harness.check("undo puts the widget back on the desktop",
                          Config.options.plugins.enabled.indexOf("edit-move-probe") !== -1);
            harness.check("...at the position it had, not at a default",
                          Math.round(harness.storedPosition("edit-move-probe").x) === 132
                          && Math.round(harness.storedPosition("edit-move-probe").y) === 396);
        },
        () => {
            // A closed drawer is a zero-width rect, so the same gesture at the
            // same screen point is a MOVE again. Without this the check above
            // passes on a release handler that removes for the whole mode.
            GlobalStates.editDrawerOpen = false;
            harness.placeWidgets();
        },
        () => {
            harness.publishReveal();
            harness.hintDuringDrag = "";
        },
        () => harness.dragOntoDrawer(movableWidget),
        () => {
            harness.check("with the drawer closed the same drop moves the widget instead",
                          Config.options.plugins.enabled.indexOf("edit-move-probe") !== -1
                          && harness.hintDuringDrag === ""
                          && Math.round(harness.storedPosition("edit-move-probe").x)
                              > 36);
            Config.options.plugins.enabled = [];
            GlobalStates.editMode = false;
        },

        // ---- the lock layout forks on the first Lockscreen-tab move ---------
        //
        // spec §4.3 as amended 2026-08-18: the lock screen's arrangement
        // INHERITS the desktop's until a widget is moved on the Lockscreen
        // tab, which copies the whole screen into a store of its own. What
        // only the real drag path can show: the widget's own drag commit
        // writes the LOCK store when the look is the lock's; every other
        // widget on the screen comes along in the fork; the desktop store is
        // untouched; the widget goes BACK to its desktop position when the
        // tab returns; an undo pushed on the lock tab and popped on the
        // desktop tab still edits the lock store; and the re-link puts the
        // inheritance back.
        () => {
            // The lock has to SHOW the widgets for there to be a lock layout
            // to arrange - a widget the lock hides is at opacity 0 and takes
            // no drag, which is the product's own rule and not this test's.
            // Both halves of "shows": the master gate, and the per-widget
            // choice under it, which inherits the DESKTOP's enabled list - so
            // the probes have to be on that list the way a real placed widget
            // is. This harness builds its PluginWidgets by hand rather than
            // through Background's Repeater, so nothing else puts them there.
            Config.options.lock.showWidgets = true;
            Config.options.plugins.enabled = ["edit-move-probe", "edit-resize-probe"];
            GlobalStates.editMode = true;
        },
        () => {
            harness.check("before any lock edit the screen is not forked",
                          !PluginState.lockLayoutForked(harness.testScreen));
            GlobalStates.editTab = EditMode.LOCKSCREEN_TAB;
        },
        () => {
            harness.check("on the Lockscreen tab the widget still sits at its desktop position",
                          Math.round(movableWidget.x) === 36 && Math.round(movableWidget.y) === 396);
            harness.dragBy(movableWidget, 120, 0);
        },
        () => {
            harness.check("the first lock move forks the screen",
                          PluginState.lockLayoutForked(harness.testScreen));
            harness.check("...the moved widget follows the lock store",
                          Math.round(PluginState.position("edit-move-probe", harness.testScreen,
                                                          PluginState.lockSurface).x) === 156);
            harness.check("...the OTHER widget came along at its own position",
                          Math.round(PluginState.position("edit-resize-probe", harness.testScreen,
                                                          PluginState.lockSurface).x) === 36);
            harness.check("...and the desktop store did not move",
                          Math.round(PluginState.position("edit-move-probe", harness.testScreen,
                                                          PluginState.desktopSurface).x) === 36);
            GlobalStates.editTab = EditMode.DESKTOP_TAB;
        },
        () => {
            harness.check("back on the Desktop tab the widget is at its desktop position again",
                          Math.round(movableWidget.x) === 36);
            // The undo was pushed on the LOCK tab. Popping it here must edit
            // the lock store, not write the lock's old position into the
            // desktop's.
            GlobalStates.editUndo();
        },
        () => {
            harness.check("an undo popped on the other tab restores the LOCK store",
                          Math.round(PluginState.position("edit-move-probe", harness.testScreen,
                                                          PluginState.lockSurface).x) === 36);
            harness.check("...and leaves the desktop store alone",
                          Math.round(PluginState.position("edit-move-probe", harness.testScreen,
                                                          PluginState.desktopSurface).x) === 36
                          && Math.round(movableWidget.x) === 36);
            // The fork itself survives an undo of the move - the screen is
            // still separate, just back at the same numbers.
            harness.check("...the screen stays forked",
                          PluginState.lockLayoutForked(harness.testScreen));
            PluginState.resetLockLayout(harness.testScreen);
        },
        () => {
            harness.check("the re-link removes the fork",
                          !PluginState.lockLayoutForked(harness.testScreen));
            harness.check("...and the lock reads through to the desktop again",
                          PluginState.rawPosition("edit-move-probe", harness.testScreen,
                                                  PluginState.lockSurface) !== undefined
                          && Math.round(PluginState.position("edit-move-probe", harness.testScreen,
                                                             PluginState.lockSurface).x) === 36);
        },

        // ---- the SPAN forks with the position -------------------------------
        //
        // The maintainer's second report: a media widget at 3x2 on the desktop
        // and 1x2 on the lock. Driven through the real grip on the Lockscreen
        // tab: the resize forks the screen and writes the LOCK span; the
        // desktop's __gridSize option is untouched; back on the Desktop tab
        // the widget is drawn at the desktop's span; the undo pushed on the
        // lock tab restores the lock span from the other tab.
        () => {
            // A known desktop span to fork from.
            PluginState.setOption("edit-resize-probe", "__gridSize", "2x2");
        },
        () => {
            harness.check("the desktop span is 2x2 before the lock resize",
                          harness.storedSize("edit-resize-probe") === "2x2"
                          && !PluginState.lockLayoutForked(harness.testScreen));
            GlobalStates.editTab = EditMode.LOCKSCREEN_TAB;
        },
        () => {
            harness.check("on the Lockscreen tab the widget is drawn at the desktop span",
                          resizableWidget.storedGridSize.cols === 2
                          && resizableWidget.storedGridSize.rows === 2);
            // Pull the grip one row up: 2x2 -> 2x1, the next span the probe
            // offers (its list is 3x2 / 2x2 / 2x1).
            harness.dragGripBy(resizableWidget, 0, -160);
        },
        () => {
            harness.check("a lock resize forks the screen",
                          PluginState.lockLayoutForked(harness.testScreen));
            harness.check("...and writes the LOCK span",
                          PluginState.gridSize("edit-resize-probe", harness.testScreen,
                                               PluginState.lockSurface) === "2x1");
            harness.check("...leaving the desktop's __gridSize option at 2x2",
                          PluginState.option("edit-resize-probe", "__gridSize", "") === "2x2");
            harness.check("...and the widget is drawn at 2x1 here",
                          resizableWidget.storedGridSize.rows === 1);
            GlobalStates.editTab = EditMode.DESKTOP_TAB;
        },
        () => {
            harness.check("back on the Desktop tab the widget is drawn at 2x2 again",
                          resizableWidget.storedGridSize.rows === 2);
            GlobalStates.editUndo();
        },
        () => {
            harness.check("the resize's undo, popped on the Desktop tab, restores the LOCK span",
                          PluginState.gridSize("edit-resize-probe", harness.testScreen,
                                               PluginState.lockSurface) === "2x2");
            harness.check("...and the desktop option is still 2x2",
                          PluginState.option("edit-resize-probe", "__gridSize", "") === "2x2");
            PluginState.resetLockLayout(harness.testScreen);
        },

        // ---- and PRESENCE forks the same way -------------------------------
        //
        // The store's arithmetic is tst_layout_surfaces and the drawer-to-
        // surface wiring is the contract's; what only a real widget under the
        // real transform can answer is whether the pick reaches the PIXELS -
        // whether a widget picked off the lock actually stops being drawn
        // there while it keeps being drawn on the desktop, and whether the
        // mirror (a widget the desktop does not show, kept for the lock) is
        // hidden on the desktop rather than merely uninstantiated. The pick
        // itself goes through PluginState rather than the drawer, which lives
        // on a layer surface this harness does not build.
        () => {
            harness.check("before any pick the lock shows what the desktop shows",
                          !PluginState.lockPresenceForked()
                          && movableWidget.visibleWhenLocked
                          && resizableWidget.visibleWhenLocked);
            GlobalStates.editTab = EditMode.LOCKSCREEN_TAB;
        },
        () => {
            harness.check("...and an inherited widget is drawn on the Lockscreen tab",
                          movableWidget.opacity === 1 && movableWidget.visible);
            PluginState.setLockWidgetEnabled("edit-move-probe", false);
        },
        () => {
            harness.check("the first pick forks the choice",
                          PluginState.lockPresenceForked());
            harness.check("...the picked widget leaves the lock screen",
                          movableWidget.opacity === 0 && !movableWidget.visible);
            harness.check("...and the other one stays, at the desktop's answer",
                          resizableWidget.opacity === 1);
            GlobalStates.editTab = EditMode.DESKTOP_TAB;
        },
        () => {
            harness.check("...while the desktop goes on showing it",
                          movableWidget.opacity === 1 && movableWidget.visible);
            // The mirror, which one shared list cannot express: a widget the
            // desktop does not show, kept for the lock screen alone.
            Config.options.plugins.enabled = ["edit-move-probe"];
        },
        () => {
            harness.check("a lock-only widget is hidden on the desktop",
                          resizableWidget.opacity === 0 && !resizableWidget.visible);
            GlobalStates.editTab = EditMode.LOCKSCREEN_TAB;
        },
        () => {
            harness.check("...and drawn on the lock screen",
                          resizableWidget.opacity === 1 && resizableWidget.visible);
            PluginState.resetLockPresence();
        },
        () => {
            harness.check("the re-link puts both widgets back on the desktop's answer",
                          !PluginState.lockPresenceForked()
                          && movableWidget.opacity === 1
                          && resizableWidget.opacity === 0);
            GlobalStates.editTab = EditMode.DESKTOP_TAB;
            GlobalStates.editMode = false;
        }
    ]

    property int stepIndex: 0

    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            Config.options.background.showSnapLines = false;
            if (Math.round(resizableWidget.x) === 36 && Math.round(movableWidget.y) === 396) {
                setup.running = false;
                runner.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    // One step per tick, and the tick outlasts the 500ms position/size
    // animations: every check reads a settled value, and a frame sampled
    // mid-Behavior is a working animation reading as a failed gesture.
    Timer {
        id: runner
        interval: 700
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[EditMode] checks: ${harness.checksRun} failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
