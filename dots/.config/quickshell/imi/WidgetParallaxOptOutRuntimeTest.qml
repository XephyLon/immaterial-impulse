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
 * Position Behaviors are switched off (`animateXPos`/`animateYPos`) so a score
 * reads a settled coordinate rather than a frame of an animation. The
 * cancellation is a binding, not a transition - the animation is the same one
 * every widget already has.
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
                animateXPos: false
                animateYPos: false
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

        () => harness.pan(0, 0),
        () => {
            harness.check("pan released: the follower comes back",
                          harness.screenX(followWidget) === 120 && harness.screenY(followWidget) === 120);
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
