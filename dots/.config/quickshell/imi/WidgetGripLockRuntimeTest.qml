import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/**
 * Drives the resize/toggle grips of the three bundled widgets that draw one,
 * with real mouse events, against every reason the host can be locked.
 *
 * `tests/test_widget_grip_lock.py` can only grep the bindings, and the
 * qmltestrunner suite cannot instantiate the host at all. Neither answers the
 * question that matters: a grip that stops being *drawn* is not necessarily a
 * grip that stops *resizing*, and the bug this exists for was exactly that
 * asymmetry - a per-widget lock held for dragging and not for the grip.
 *
 * Every grip persists its result through `PluginState.setOption`, so each
 * gesture is scored on the stored option rather than on the widget's animated
 * size - no waiting on a Behavior, and no way for a half-finished resize to
 * read as a success.
 *
 * The last phase unlocks everything and repeats the same gestures. Without it
 * every "nothing changed" result above would also be satisfied by a harness
 * that had simply stopped delivering events.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetGripLockRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    readonly property string testScreen: "GRIP-TEST"
    readonly property string bundledRoot: Quickshell.shellPath("modules/common/plugins/bundled")

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[WidgetGripLock] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function manifestFor(id, name, w, h) {
        return {
            id: id,
            name: name,
            defaultWidth: w,
            defaultHeight: h,
            _basePath: `${harness.bundledRoot}/${id}`,
            desktopWidget: { component: "Widget.qml", blur: false }
        };
    }

    readonly property var customImageManifest: harness.manifestFor("custom-image", "Custom Image", 80, 80)
    readonly property var calendarManifest: harness.manifestFor("calendar", "Calendar", 132, 108)
    readonly property var worldClockManifest: harness.manifestFor("world-clock", "World Clock", 276, 108)

    TestCase {
        id: driver
        when: false
        name: "WidgetGripLockDriver"
    }

    FloatingWindow {
        visible: true
        implicitWidth: 1000
        implicitHeight: 420
        color: "black"

        WidgetCanvas {
            id: canvas
            anchors.fill: parent

            PluginWidget {
                id: customImageWidget
                manifest: harness.customImageManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 420
                scaledScreenWidth: 1000
                scaledScreenHeight: 420
                wallpaperScale: 1
            }

            PluginWidget {
                id: calendarWidget
                manifest: harness.calendarManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 420
                scaledScreenWidth: 1000
                scaledScreenHeight: 420
                wallpaperScale: 1
            }

            PluginWidget {
                id: worldClockWidget
                manifest: harness.worldClockManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 420
                scaledScreenWidth: 1000
                scaledScreenHeight: 420
                wallpaperScale: 1
            }
        }
    }

    // The three widgets default to the host's generic 100,100, which would
    // stack them and make every click land on whichever was declared last.
    function placeWidgets() {
        PluginState.setPosition("custom-image", harness.testScreen,
                                { x: 20, y: 20, placementStrategy: "free" });
        PluginState.setPosition("calendar", harness.testScreen,
                                { x: 340, y: 20, placementStrategy: "free" });
        PluginState.setPosition("world-clock", harness.testScreen,
                                { x: 660, y: 20, placementStrategy: "free" });
    }

    // ---- gestures -------------------------------------------------------
    //
    // Grip coordinates are derived from the live widget rect and the same
    // Appearance tokens the widgets anchor with, so they follow a spacing or
    // scale change instead of going quietly stale. A grip is 16x16.
    function gripCenter(widget, margin, fromLeft) {
        return {
            x: widget.x + (fromLeft ? margin + 8 : widget.width - margin - 8),
            y: widget.y + widget.height - margin - 8
        };
    }

    property var pendingGrip: null

    function hoverGrip(point) {
        harness.pendingGrip = point;
        driver.mouseMove(canvas, point.x, point.y);
    }

    function dragPending(dx, dy) {
        const point = harness.pendingGrip;
        driver.mousePress(canvas, point.x, point.y, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx / 2, point.y + dy / 2, 20, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx, point.y + dy, 20, Qt.LeftButton);
        driver.mouseRelease(canvas, point.x + dx, point.y + dy, Qt.LeftButton);
    }

    function clickPending() {
        driver.mouseClick(canvas, harness.pendingGrip.x, harness.pendingGrip.y, Qt.LeftButton);
    }

    function customImageGrip() {
        return harness.gripCenter(customImageWidget, Appearance.spacing.space100, false);
    }
    function calendarGrip() {
        return harness.gripCenter(calendarWidget, Appearance.spacing.space50, false);
    }
    function worldClockGrip() {
        return harness.gripCenter(worldClockWidget, Appearance.spacing.space50, false);
    }

    function imageSize() { return PluginState.option("custom-image", "size", 200); }
    function calendarMode() { return PluginState.option("calendar", "sizeMode", "2x2"); }
    function worldClockMode() { return PluginState.option("world-clock", "sizeMode", "2x2"); }

    // Drag the calendar grip towards whichever mode it is not in, so a phase
    // that is supposed to change something always has somewhere to go.
    function calendarDragDx() {
        return harness.calendarMode() === "1x1" ? 190 : -190;
    }

    function snapshot() {
        return { image: harness.imageSize(), calendar: harness.calendarMode(),
                 worldClock: harness.worldClockMode() };
    }

    function scorePhase(label, before, expectChange) {
        const after = harness.snapshot();
        const verb = expectChange ? "resizes" : "is dead";
        harness.check(`${label}: the custom-image grip ${verb}`,
                      (after.image !== before.image) === expectChange);
        harness.check(`${label}: the calendar grip ${verb}`,
                      (after.calendar !== before.calendar) === expectChange);
        harness.check(`${label}: the world-clock grip ${verb}`,
                      (after.worldClock !== before.worldClock) === expectChange);
    }

    function setLock(key, value) {
        for (const id of ["custom-image", "calendar", "world-clock"])
            PluginState.setOption(id, key, value);
    }

    // ---- phases ---------------------------------------------------------

    property var phaseBefore: null

    function gestureSteps() {
        return [
            () => harness.hoverGrip(harness.customImageGrip()),
            () => harness.dragPending(40, 40),
            () => harness.hoverGrip(harness.calendarGrip()),
            () => harness.dragPending(harness.calendarDragDx(), 0),
            () => harness.hoverGrip(harness.worldClockGrip()),
            () => harness.clickPending()
        ];
    }

    function phase(label, arm, expectChange) {
        return [arm, () => { harness.phaseBefore = harness.snapshot(); }]
            .concat(harness.gestureSteps())
            .concat([() => harness.scorePhase(label, harness.phaseBefore, expectChange)]);
    }

    readonly property var steps: harness
        // Nothing locked: the control. If this phase reports a dead grip the
        // coordinates are wrong and every later result is meaningless.
        .phase("unlocked", () => {}, true)
        // The bug. Locked for this widget alone, click-through off, global
        // switch off - the exact state in which the grip used to survive.
        .concat(harness.phase("per-widget locked",
                              () => harness.setLock("positionLocked", true), false))
        // The behaviour that already worked, kept honest.
        .concat(harness.phase("globally locked", () => {
            harness.setLock("positionLocked", false);
            Config.options.background.widgetsLocked = true;
        }, false))
        // Click-through does not reach a grip on its own, contrary to what
        // "`enabled` cascades down the item tree" suggests: `enabled: false` is
        // set on AbstractBackgroundWidget, and MouseArea's `enabled` is its own
        // property, not the Item one - it stops that MouseArea handling events
        // and leaves everything under it live. So this phase reddens without
        // the fix too, and the resolved lock is what actually kills the grip.
        .concat(harness.phase("click-through", () => {
            Config.options.background.widgetsLocked = false;
            harness.setLock("clickThrough", true);
        }, false))
        // Everything off again. Three phases of "nothing happened" prove
        // nothing at all if the harness stopped delivering events partway.
        .concat(harness.phase("unlocked again",
                              () => harness.setLock("clickThrough", false), true))

    property int stepIndex: 0

    // PluginState's FileView load lands asynchronously and replaces the whole
    // in-memory state, so anything written before it arrives is discarded - and
    // on a config directory with no state file yet, the empty file it writes is
    // then watched back in over whatever was set meanwhile. Keep asking until
    // the positions stick and the position Behavior has finished animating to
    // them, or the widgets overlap and every gesture lands on the wrong one.
    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            if (Math.round(customImageWidget.x) === 20
                    && Math.round(calendarWidget.x) === 340
                    && Math.round(worldClockWidget.x) === 660) {
                setup.running = false;
                runner.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    // One step per tick rather than one phase per tick: a grip only becomes
    // visible once the hover has animated its opacity off zero, so the hover
    // and the press it enables cannot share a frame.
    Timer {
        id: runner
        interval: 400
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[WidgetGripLock] checks: ${harness.checksRun} failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
