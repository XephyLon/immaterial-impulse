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
    readonly property var applied: EditMode.atProgress(harness.viewport,
                                                       GlobalStates.editMode ? 1 : 0)

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

        // ---- the affordances the mode forces on ---------------------------
        () => {
            Config.options.background.showGrid = false;
            harness.check("the grid is up for the whole mode, not for the drag",
                          canvas.gridVisible && !canvas.showGrid);
            harness.check("the frost stands down for the mode",
                          resizableWidget.frostSuspended);
        },
        () => {
            Config.options.background.showGrid = true;
            GlobalStates.editMode = false;
            harness.check("and the grid goes back to being the drag's",
                          !canvas.gridVisible);
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
        // reaches it. That is both the affordance check and the one that scores
        // the grip's delta in the right frame - it is read in the widget's
        // parent frame, and a scene-space delta here would resize by the
        // scale's worth less than the pointer travelled.
        () => { harness.placeWidgets(); },
        () => harness.dragGripBy(resizableWidget, -150, 0),
        () => {
            harness.check("the grip is out for the mode and resizes at scale",
                          harness.storedSize("edit-resize-probe") === "2x2");
            harness.check("...and the widget did not walk",
                          Math.round(harness.storedPosition("edit-resize-probe").x) === 36
                          && Math.round(harness.storedPosition("edit-resize-probe").y) === 36);
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
