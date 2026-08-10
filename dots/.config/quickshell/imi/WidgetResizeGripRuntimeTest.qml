import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/**
 * Drives the grid resize grip with real mouse events, on real `PluginWidget`s.
 *
 * The qmltestrunner suite cannot instantiate the host at all (Quickshell's
 * plugin does not load there), and `tests/test_widget_grip_lock.py` can only
 * grep the bindings. Neither answers the question this feature turns on:
 * whether a press on the corner resizes the widget or *walks* it, since
 * `AbstractWidget`'s drag-to-move is the root MouseArea the grip sits inside.
 * Only real events can, so the widget's position is scored on every gesture,
 * not only its span.
 *
 * Every check is scored on `PluginState`'s stored `__gridSize` and on the
 * widget's own x/y, never on the animated width - a half-finished resize
 * cannot read as a success that way, and there is no Behavior to wait on.
 *
 * Two manifests, because most of the assertions are about what does *not*
 * happen: one offering three spans and one offering a single one. The
 * single-span widget is the control that keeps "nothing moved, nothing
 * resized" from being satisfied by a harness that stopped delivering events -
 * dragging its corner has to move it.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetResizeGripRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    readonly property string testScreen: "RESIZE-TEST"

    function check(label, ok) {
        console.log(`[WidgetResizeGrip] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // Synthetic manifests: no shipped plugin offers more than one span yet, and
    // the grip is the host's regardless of what is loaded into it. An `Item`
    // node draws nothing and takes no input, so every event the harness sends
    // is answered by the host or by nothing.
    function manifestFor(id, grid) {
        return {
            id: id,
            name: id,
            grid: grid,
            desktopWidget: { type: "Item" }
        };
    }

    readonly property var resizableManifest: harness.manifestFor("resize-probe", {
        cols: 3, rows: 2,
        sizes: [{ cols: 3, rows: 2 }, { cols: 2, rows: 2 }, { cols: 2, rows: 1 }]
    })
    readonly property var fixedManifest: harness.manifestFor("fixed-probe", { cols: 3, rows: 2 })

    FloatingWindow {
        visible: true
        implicitWidth: 1200
        implicitHeight: 700
        color: "black"

        // Inside the window, unlike the other widget harnesses: a key event has
        // no explicit target the way a mouse event does - TestCase sends it to
        // the focused item of *its own* window - so a driver parented outside
        // any window cannot deliver the Escape this scores.
        TestCase {
            id: driver
            when: false
            name: "WidgetResizeGripDriver"
        }

        WidgetCanvas {
            id: canvas
            anchors.fill: parent

            PluginWidget {
                id: resizableWidget
                manifest: harness.resizableManifest
                screenName: harness.testScreen
                screenWidth: 1200
                screenHeight: 700
                scaledScreenWidth: 1200
                scaledScreenHeight: 700
                wallpaperScale: 1
            }

            PluginWidget {
                id: fixedWidget
                manifest: harness.fixedManifest
                screenName: harness.testScreen
                screenWidth: 1200
                screenHeight: 700
                scaledScreenWidth: 1200
                scaledScreenHeight: 700
                wallpaperScale: 1
            }
        }
    }

    // Both default to the host's generic 100,100, which would stack them and
    // send every click to whichever was declared last.
    function placeWidgets() {
        PluginState.setPosition("resize-probe", harness.testScreen,
                                { x: 40, y: 40, placementStrategy: "free" });
        PluginState.setPosition("fixed-probe", harness.testScreen,
                                { x: 640, y: 400, placementStrategy: "free" });
    }

    // ---- gestures -------------------------------------------------------
    //
    // The grip is 16x16 anchored to the widget's bottom-right with the same
    // Appearance token the host anchors it with, so a spacing change moves the
    // gesture too instead of leaving it pointing at bare card.
    function gripCenter(widget) {
        const inset = Appearance.spacing.space100 + 8;
        return { x: widget.x + widget.width - inset, y: widget.y + widget.height - inset };
    }

    property var pendingGrip: null

    function hoverGrip(widget) {
        harness.pendingGrip = harness.gripCenter(widget);
        driver.mouseMove(canvas, harness.pendingGrip.x, harness.pendingGrip.y);
    }

    function dragPending(dx, dy) {
        const point = harness.pendingGrip;
        driver.mousePress(canvas, point.x, point.y, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx / 2, point.y + dy / 2, 20, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx, point.y + dy, 20, Qt.LeftButton);
        driver.mouseRelease(canvas, point.x + dx, point.y + dy, Qt.LeftButton);
    }

    function dragPendingWithEscape(dx, dy) {
        const point = harness.pendingGrip;
        driver.mousePress(canvas, point.x, point.y, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx, point.y + dy, 20, Qt.LeftButton);
        driver.keyClick(Qt.Key_Escape);
        driver.mouseRelease(canvas, point.x + dx, point.y + dy, Qt.LeftButton);
    }

    function storedSize(id) { return PluginState.option(id, "__gridSize", ""); }

    function snapshot() {
        return {
            resizableSize: harness.storedSize("resize-probe"),
            resizableX: Math.round(resizableWidget.x),
            resizableY: Math.round(resizableWidget.y),
            fixedSize: harness.storedSize("fixed-probe"),
            fixedX: Math.round(fixedWidget.x),
            fixedY: Math.round(fixedWidget.y)
        };
    }

    property var before: null

    function remember() { harness.before = harness.snapshot(); }

    // ---- the checks -----------------------------------------------------

    function scoreResize(label, expected) {
        const after = harness.snapshot();
        harness.check(`${label}: stores ${expected}`, after.resizableSize === expected);
        harness.check(`${label}: the widget stays put`,
                      after.resizableX === harness.before.resizableX
                      && after.resizableY === harness.before.resizableY);
        harness.check(`${label}: the widget is the span it stored`,
                      Math.round(resizableWidget.width)
                          === Math.round(Appearance.sizes.widgetGridSpanX(parseInt(expected[0])))
                      && Math.round(resizableWidget.height)
                          === Math.round(Appearance.sizes.widgetGridSpanY(parseInt(expected[2]))));
    }

    function scoreCancelled(label) {
        const after = harness.snapshot();
        harness.check(`${label}: stores nothing new`,
                      after.resizableSize === harness.before.resizableSize);
        harness.check(`${label}: the widget stays put`,
                      after.resizableX === harness.before.resizableX
                      && after.resizableY === harness.before.resizableY);
        harness.check(`${label}: the widget is back at its stored span`,
                      Math.round(resizableWidget.width)
                          === Math.round(Appearance.sizes.widgetGridSpanX(2)));
    }

    // The control. A widget offering one span has no grip, so the same gesture
    // on the same corner is a plain drag-to-move - which is also what the
    // resizable widget must never do.
    function scoreMoved(label) {
        const after = harness.snapshot();
        harness.check(`${label}: stores no span`, after.fixedSize === "");
        harness.check(`${label}: the widget moved instead`,
                      after.fixedX !== harness.before.fixedX
                      || after.fixedY !== harness.before.fixedY);
    }

    function scoreLocked(label) {
        const after = harness.snapshot();
        harness.check(`${label}: stores nothing new`,
                      after.resizableSize === harness.before.resizableSize);
        harness.check(`${label}: the widget stays put`,
                      after.resizableX === harness.before.resizableX
                      && after.resizableY === harness.before.resizableY);
    }

    readonly property var steps: [
        // Shrink 3x2 -> 2x2: 144px in from the right edge, the whole distance
        // between those two spans.
        () => harness.remember(),
        () => harness.hoverGrip(resizableWidget),
        () => harness.dragPending(-144, 0),
        () => harness.scoreResize("shrink to 2x2", "2x2"),

        // ...and 2x2 -> 2x1, which only moves vertically.
        () => harness.remember(),
        () => harness.hoverGrip(resizableWidget),
        () => harness.dragPending(0, -120),
        () => harness.scoreResize("shrink to 2x1", "2x1"),

        // Back out to the largest span, so the cancel below has somewhere to go.
        () => harness.remember(),
        () => harness.hoverGrip(resizableWidget),
        () => harness.dragPending(144, 120),
        () => harness.scoreResize("grow back to 3x2", "3x2"),

        () => harness.remember(),
        () => harness.hoverGrip(resizableWidget),
        () => harness.dragPending(-144, 0),
        () => harness.scoreResize("shrink to 2x2 again", "2x2"),

        // Escape mid-drag: the release that follows commits nothing and the
        // widget is back at the span it started the drag from.
        () => harness.remember(),
        () => harness.hoverGrip(resizableWidget),
        () => harness.dragPendingWithEscape(0, -120),
        () => harness.scoreCancelled("escape cancels"),

        // The control, and the proof the harness is still delivering events.
        () => harness.remember(),
        () => harness.hoverGrip(fixedWidget),
        () => harness.dragPending(-144, 0),
        () => harness.scoreMoved("a single-span widget has no grip"),

        // Pinned per widget: the grip is disarmed, and so is the drag.
        () => { harness.remember(); PluginState.setOption("resize-probe", "positionLocked", true); },
        () => harness.hoverGrip(resizableWidget),
        () => harness.dragPending(0, -120),
        () => harness.scoreLocked("a pinned widget does not resize"),

        // Unlocked again: three "nothing happened" phases prove nothing if the
        // harness quietly stopped delivering events partway.
        () => { harness.remember(); PluginState.setOption("resize-probe", "positionLocked", false); },
        () => harness.hoverGrip(resizableWidget),
        () => harness.dragPending(0, -120),
        () => harness.scoreResize("unlocked again", "2x1")
    ]

    property int stepIndex: 0

    // PluginState's FileView load lands asynchronously and replaces the whole
    // in-memory state, so anything written before it arrives is discarded.
    // Keep asking until the positions stick and the position Behavior has
    // finished animating to them.
    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            if (Math.round(resizableWidget.x) === 40 && Math.round(fixedWidget.x) === 640) {
                setup.running = false;
                runner.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    // One step per tick: the grip only becomes visible once the hover has
    // animated its opacity off zero, so the hover and the press it enables
    // cannot share a frame.
    Timer {
        id: runner
        interval: 400
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[WidgetResizeGrip] failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
