import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/**
 * Drives the `followParallax` opt-out on real `PluginWidget`s.
 *
 * The desktop's widget parallax is the canvas's own `x`/`y` (Background.qml),
 * so every widget on it travels whether or not it wants to. Opting out is a
 * cancellation rather than a smaller offset, and the arithmetic is unit-tested
 * in `tst_parallax.qml` - what needs a real host is the pair of consequences
 * that arithmetic has for a widget's *stored* position:
 *
 *   - the widget must hold its place on screen (canvas.x + widget.x) while the
 *     canvas pans, which nothing but a live tree can show;
 *   - dragging it while the canvas is panned must store where it was PLACED,
 *     not where it was drawn. Storing the drawn coordinate folds the pan into
 *     the saved position, so the widget walks by a whole pan every time it is
 *     moved - and it walks silently, because it looks right until the pan
 *     changes.
 *
 * The following widget is the control throughout: three "it did not move"
 * checks prove nothing if the harness stopped delivering events.
 *
 * The follower's position Behaviors are switched off (`animateXPos`/
 * `animateYPos`) so a score reads a settled coordinate rather than a frame of
 * an animation. The opted-out widget's are deliberately left alone: the host
 * turns them off itself (`animatePosition: followParallax`), and that IS the
 * fix the last block scores. Setting them here would hide it - which is what
 * the first version of this harness did, on both widgets, and it is why the
 * opt-out shipped doing nothing at all on a real desktop.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetParallaxOptOutRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    readonly property string testScreen: "PARALLAX-TEST"

    function check(label, ok) {
        console.log(`[WidgetParallax] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // Synthetic manifests, because the opt-out is the host's regardless of what
    // is loaded into it. An `Item` node draws nothing and takes no input, so
    // every event the harness sends is answered by the host or by nothing; the
    // `grid` gives each probe a body big enough to press.
    function manifestFor(id, follows) {
        return {
            id: id,
            name: id,
            grid: { cols: 2, rows: 1 },
            desktopWidget: follows ? { type: "Item" }
                                   : { type: "Item", followParallax: false }
        };
    }

    readonly property var followManifest: harness.manifestFor("follow-probe", true)
    readonly property var holdManifest: harness.manifestFor("hold-probe", false)

    FloatingWindow {
        visible: true
        implicitWidth: 1200
        implicitHeight: 700
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "WidgetParallaxDriver"
        }

        WidgetCanvas {
            id: canvas
            width: 1200
            height: 700

            // Background.qml animates the pan, and that turns out to be the
            // whole difference between an opt-out that works and one that does
            // not - so the harness can offer both. Off for the settled checks,
            // which want an instant pan; on for the last block, which is about
            // what happens *during* one.
            property bool animatePan: false
            Behavior on x {
                enabled: canvas.animatePan
                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: canvas.animatePan
                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
            }

            PluginWidget {
                id: followWidget
                manifest: harness.followManifest
                screenName: harness.testScreen
                screenWidth: 1200
                screenHeight: 700
                scaledScreenWidth: 1200
                scaledScreenHeight: 700
                wallpaperScale: 1
                animateXPos: false
                animateYPos: false
            }

            PluginWidget {
                id: holdWidget
                manifest: harness.holdManifest
                screenName: harness.testScreen
                screenWidth: 1200
                screenHeight: 700
                scaledScreenWidth: 1200
                scaledScreenHeight: 700
                wallpaperScale: 1
            }
        }
    }

    function placeWidgets() {
        PluginState.setPosition("follow-probe", harness.testScreen,
                                { x: 120, y: 120, placementStrategy: "free" });
        PluginState.setPosition("hold-probe", harness.testScreen,
                                { x: 600, y: 360, placementStrategy: "free" });
    }

    // What the user sees: the canvas carries the pan, so a widget's place on
    // screen is the sum. This is the only coordinate the opt-out promises
    // anything about.
    function screenX(widget) { return Math.round(canvas.x + widget.x); }
    function screenY(widget) { return Math.round(canvas.y + widget.y); }

    function pan(dx, dy) {
        canvas.x = dx;
        canvas.y = dy;
    }

    function storedX(id) { return Math.round(PluginState.position(id, harness.testScreen).x); }
    function storedY(id) { return Math.round(PluginState.position(id, harness.testScreen).y); }
    // Unrounded, for the one check that is about the fraction itself.
    function rawStoredX(id) { return PluginState.position(id, harness.testScreen).x; }
    function rawStoredY(id) { return PluginState.position(id, harness.testScreen).y; }

    // Snapped to the shared 12px lattice by AbstractWidget, so every gesture
    // here is a whole number of steps and the expected result is exact.
    function dragWidget(widget, dx, dy) {
        const x = widget.x + widget.width / 2;
        const y = widget.y + widget.height / 2;
        driver.mouseMove(canvas, x, y);
        driver.mousePress(canvas, x, y, Qt.LeftButton);
        driver.mouseMove(canvas, x + dx / 2, y + dy / 2, 20, Qt.LeftButton);
        driver.mouseMove(canvas, x + dx, y + dy, 20, Qt.LeftButton);
        driver.mouseRelease(canvas, x + dx, y + dy, Qt.LeftButton);
    }

    // A press and release that never moves. It runs the same commitPosition
    // path a drag does - `onReleased` does not ask whether anything was
    // dragged - so it must be a no-op on the store.
    function clickWidget(widget) {
        const x = widget.x + widget.width / 2;
        const y = widget.y + widget.height / 2;
        driver.mouseMove(canvas, x, y);
        driver.mousePress(canvas, x, y, Qt.LeftButton);
        driver.mouseRelease(canvas, x, y, Qt.LeftButton);
    }

    readonly property var steps: [
        () => {
            harness.check("unpanned: the follower is where it was placed",
                          harness.screenX(followWidget) === 120 && harness.screenY(followWidget) === 120);
            harness.check("unpanned: the opted-out widget is where it was placed",
                          harness.screenX(holdWidget) === 600 && harness.screenY(holdWidget) === 360);
            harness.check("unpanned: nothing is cancelling anything",
                          Math.round(holdWidget.x) === 600 && Math.round(holdWidget.y) === 360);
        },

        () => harness.pan(-180, -60),
        () => {
            // The control. Without this, "the other one held still" is also
            // what a canvas that never moved would report.
            harness.check("panned: the follower travels with the canvas",
                          harness.screenX(followWidget) === -60 && harness.screenY(followWidget) === 60);
            harness.check("panned: the opted-out widget holds its screen place",
                          harness.screenX(holdWidget) === 600 && harness.screenY(holdWidget) === 360);
            harness.check("panned: it holds it by cancelling, not by not moving",
                          Math.round(holdWidget.x) === 780 && Math.round(holdWidget.y) === 420);
        },

        // Dragged while the canvas is panned: the drag is in canvas
        // coordinates and the store is in placement coordinates, and the gap
        // between them is exactly the cancellation.
        () => harness.dragWidget(holdWidget, 48, 24),
        () => {
            harness.check("dragged while panned: stores the placement, not the drawn position",
                          harness.storedX("hold-probe") === 648
                          && harness.storedY("hold-probe") === 384);
            harness.check("dragged while panned: lands where the pointer left it",
                          harness.screenX(holdWidget) === 648 && harness.screenY(holdWidget) === 384);
        },

        // The drift check, and the reason commitPosition subtracts: a widget
        // that stored its drawn coordinate would now be one pan further along,
        // every time.
        () => harness.dragWidget(holdWidget, 48, 24),
        () => {
            harness.check("dragged twice: each drag moves it by the drag alone",
                          harness.storedX("hold-probe") === 696
                          && harness.storedY("hold-probe") === 408);
        },

        // The same round trip for the widget that does follow, because the
        // store has to mean one thing for both. A follower's drag needs no
        // conversion at all, so the two land on the same number from opposite
        // directions - which is the property, not a coincidence.
        () => harness.dragWidget(followWidget, 48, 24),
        () => {
            harness.check("follower dragged while panned: stores its placement too",
                          harness.storedX("follow-probe") === 168
                          && harness.storedY("follow-probe") === 144);
            harness.check("follower dragged while panned: lands where the pointer left it",
                          harness.screenX(followWidget) === -12
                          && harness.screenY(followWidget) === 84);
        },

        // Reload, with the pan still on. `applyPersistedPosition` is what runs
        // when the shell comes back up (and on every external state change), so
        // driving it directly is the closest a live harness gets to a restart -
        // and it is where the clamp lives, which is the half that decides
        // whether a stored coordinate is honoured or quietly replaced.
        () => {
            followWidget.applyPersistedPosition();
            holdWidget.applyPersistedPosition();
        },
        () => {
            harness.check("reloaded while panned: the follower is where it was dropped",
                          harness.screenX(followWidget) === -12
                          && harness.screenY(followWidget) === 84);
            harness.check("reloaded while panned: the opted-out widget is where it was dropped",
                          harness.screenX(holdWidget) === 696
                          && harness.screenY(holdWidget) === 408);
        },

        () => harness.pan(0, 0),
        () => {
            harness.check("pan released: the follower comes back",
                          harness.screenX(followWidget) === 168 && harness.screenY(followWidget) === 144);
            harness.check("pan released: the opted-out widget has not moved at all",
                          harness.screenX(holdWidget) === 696 && harness.screenY(holdWidget) === 408);
        },

        // Turning it back on from the settings row: the widget rejoins the pan
        // from where it is, without its stored position changing.
        () => { PluginState.setOption("hold-probe", "followParallax", true); },
        () => harness.pan(-180, -60),
        () => {
            harness.check("opt-in again: it travels with the canvas",
                          harness.screenX(holdWidget) === 516 && harness.screenY(holdWidget) === 348);
            harness.check("opt-in again: its stored position is untouched",
                          harness.storedX("hold-probe") === 696
                          && harness.storedY("hold-probe") === 408);
        },

        // --- The pan takes 600ms, and that is where the opt-out died --------
        //
        // Everything above pans by assignment, which settles the canvas within
        // one frame. Background.qml animates it, so an opted-out widget's x/y
        // binding re-evaluates on every frame of a 600ms transition - and a
        // Behavior handed a target that moves every frame restarts every frame
        // and never ticks. The widget then holds its OLD canvas coordinate for
        // the whole pan, which is to say it travels the full pan on screen,
        // and any release taken during it saves that stale coordinate.
        () => { PluginState.setOption("hold-probe", "followParallax", false); },
        () => harness.pan(0, 0),
        () => {
            harness.check("re-opted-out at rest: still where it was left",
                          harness.screenX(holdWidget) === 696 && harness.screenY(holdWidget) === 408);
            canvas.animatePan = true;
            harness.pan(-240, -120);
        },
        () => {
            // The instrument first: every check under it would also pass
            // against a canvas that had already finished panning.
            harness.check("mid-pan: the pan is genuinely in flight",
                          canvas.x < -1 && canvas.x > -239
                          && canvas.y < -1 && canvas.y > -119);
            harness.check("mid-pan: the follower is travelling",
                          harness.screenX(followWidget) === Math.round(canvas.x) + 168
                          && harness.screenX(followWidget) !== 168);
            harness.check("mid-pan: the opted-out widget has not moved on screen",
                          harness.screenX(holdWidget) === 696
                          && harness.screenY(holdWidget) === 408);
            // Not a drag. `onReleased` commits regardless, so a click landing
            // in this window used to walk the stored position by one pan -
            // repeatedly, which is how a real store reached x: -852.
            harness.clickWidget(holdWidget);
            harness.check("mid-pan: a click does not rewrite the placement",
                          harness.storedX("hold-probe") === 696
                          && harness.storedY("hold-probe") === 408);
        },
        () => {},
        () => {},
        () => {
            harness.check("pan settled: the opted-out widget never moved at all",
                          harness.screenX(holdWidget) === 696
                          && harness.screenY(holdWidget) === 408);
            harness.check("pan settled: the follower arrived",
                          harness.screenX(followWidget) === -72
                          && harness.screenY(followWidget) === 24);
        },

        // --- The lattice belongs to the frame the position is stored in -----
        //
        // A real canvas offset is not a round number: 5120px wide at 107% zoom
        // with a 1.2 widget factor is 215.04000000000033. Snapping the drawn
        // coordinate puts the widget on the lattice where it is drawn and off
        // it where it is saved - which is a stored x of 95.04000000000033, and
        // a widget that no longer lines up with its neighbours at rest.
        () => { canvas.animatePan = false; harness.pan(-215.04000000000033, -60.5); },
        // The gesture is deliberately NOT a whole number of lattice steps: a
        // drag of 48 from a placement of 696 lands on the lattice whether or
        // not anything snapped, which is a check that cannot fail.
        () => harness.dragWidget(holdWidget, 50, 26),
        () => {
            harness.check("dragged at a fractional pan: the placement is on the lattice",
                          harness.rawStoredX("hold-probe") % 12 === 0
                          && harness.rawStoredY("hold-probe") % 12 === 0);
            harness.check("dragged at a fractional pan: lands on the nearest lattice cell",
                          harness.screenX(holdWidget) === 744
                          && harness.screenY(holdWidget) === 432);
        },

        // --- A stored position the screen will not honour -------------------
        //
        // The author's `visualizer` sat at `x: -852` on a 5120px screen: the
        // drag is unclamped, only the load clamped, so the store kept a number
        // the widget was drawn nowhere near - permanently, and silently.
        () => { canvas.animatePan = false; harness.pan(0, 0);
                PluginState.setPosition("hold-probe", harness.testScreen,
                                        { x: -852, y: 1200, placementStrategy: "free" }); },
        () => {
            harness.check("an unreachable stored position is clamped on screen",
                          harness.screenX(holdWidget) === 0
                          && harness.screenY(holdWidget) === 700 - Math.round(holdWidget.height));
            harness.check("...and the store is left holding what the screen refused",
                          harness.storedX("hold-probe") === -852);
            holdWidget.repairUnreachableStoredPosition();
        },
        () => {
            harness.check("repaired: the store agrees with where the widget is drawn",
                          harness.storedX("hold-probe") === 0
                          && harness.storedY("hold-probe") === 700 - Math.round(holdWidget.height));
            harness.check("repaired: nothing moved - it is not a reset to the default",
                          harness.screenX(holdWidget) === 0
                          && harness.screenY(holdWidget) === 700 - Math.round(holdWidget.height));
        },

        // A drag that ends outside the screen is stored clamped, so the two
        // cannot come apart again.
        () => harness.dragWidget(holdWidget, -600, 0),
        () => {
            harness.check("dragged off the left edge: the store holds the edge, not the overshoot",
                          harness.storedX("hold-probe") === 0
                          && harness.screenX(holdWidget) === 0);
        }
    ]

    property int stepIndex: 0

    // PluginState's FileView load lands asynchronously and replaces the whole
    // in-memory state, so anything written before it arrives is discarded.
    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            if (Math.round(followWidget.x) === 120 && Math.round(holdWidget.x) === 600) {
                setup.running = false;
                runner.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    Timer {
        id: runner
        interval: 300
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[WidgetParallax] failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex]();
            harness.stepIndex++;
        }
    }
}
