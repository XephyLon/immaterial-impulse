import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas
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
        margin: Appearance.sizes.editModeMargin
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
        }
    }

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
