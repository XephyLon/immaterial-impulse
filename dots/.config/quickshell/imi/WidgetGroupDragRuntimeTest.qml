import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/**
 * Drives marquee multi-select and group drag with real mouse events.
 *
 * `tests/test_widget_group_selection.py` can only grep the bindings, and the
 * qmltestrunner suite cannot instantiate the host at all. Neither answers the
 * questions that matter: does a marquee actually pick the widgets under it and
 * only those, does dragging one selected widget move the others by the same
 * delta without deforming the cluster at a screen edge, and does every member
 * end the gesture with a live x/y binding and a persisted position.
 *
 * Five widgets cover the selection filter's whole truth table: two plain ones
 * (the group), a click-through one and a per-widget-locked one inside the
 * marquee (both must be passed over), and a plain one outside it. Every
 * position in this file is a multiple of 12 so the leader's lattice snap never
 * introduces an off-by-a-cell into an offset assertion.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetGroupDragRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    readonly property string testScreen: "GROUP-TEST"

    function check(label, ok) {
        console.log(`[WidgetGroupDrag] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[WidgetGroupDrag] failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    function manifestFor(id, extra) {
        return {
            id: id,
            name: id,
            defaultWidth: 160,
            defaultHeight: 100,
            desktopWidget: Object.assign({ type: "Item" }, extra || {})
        };
    }

    readonly property var alphaManifest: harness.manifestFor("runtime_group_alpha")
    readonly property var betaManifest: harness.manifestFor("runtime_group_beta")
    // Ships click-through, like the bundled visualizer: inside every marquee,
    // selectable by none of them.
    readonly property var ghostManifest: harness.manifestFor("runtime_group_ghost", { clickThrough: true })
    // Pinned per-widget: the other unselectable, for the other reason.
    readonly property var pinnedManifest: harness.manifestFor("runtime_group_pinned", { locked: true })
    readonly property var distantManifest: harness.manifestFor("runtime_group_distant")

    function isSelected(widget) {
        return canvas.selectedWidgets.indexOf(widget) !== -1;
    }

    function at(widget, x, y) {
        return Math.round(widget.x) === x && Math.round(widget.y) === y;
    }

    // A drag with a midpoint, so the move crosses the drag threshold before it
    // lands - same shape as WidgetGripLockRuntimeTest's dragPending.
    function dragOnCanvas(x1, y1, x2, y2) {
        driver.mousePress(canvas, x1, y1, Qt.LeftButton);
        driver.mouseMove(canvas, (x1 + x2) / 2, (y1 + y2) / 2, 20, Qt.LeftButton);
        driver.mouseMove(canvas, x2, y2, 20, Qt.LeftButton);
        driver.mouseRelease(canvas, x2, y2, Qt.LeftButton);
    }

    function dragWidgetBy(widget, dx, dy) {
        const cx = widget.x + widget.width / 2;
        const cy = widget.y + widget.height / 2;
        harness.dragOnCanvas(cx, cy, cx + dx, cy + dy);
    }

    // The whole cluster: alpha, beta, ghost and pinned - and not distant.
    function marqueeCluster() {
        harness.dragOnCanvas(12, 12, 432, 396);
    }

    FloatingWindow {
        visible: true
        implicitWidth: 1000
        implicitHeight: 560
        color: "black"

        // Inside the window, unlike the sibling harnesses: keyClick has no
        // item argument to resolve a window from, so a TestCase parked on the
        // ShellRoot fails it with "window not shown". The mouse functions
        // resolve their window from the item and work from either place.
        TestCase {
            id: driver
            when: false
            name: "WidgetGroupDragDriver"
        }

        WidgetCanvas {
            id: canvas
            anchors.fill: parent
            selectionEnabled: true

            PluginWidget {
                id: alphaWidget
                manifest: harness.alphaManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1
            }

            PluginWidget {
                id: betaWidget
                manifest: harness.betaManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1
            }

            PluginWidget {
                id: ghostWidget
                manifest: harness.ghostManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1
            }

            PluginWidget {
                id: pinnedWidget
                manifest: harness.pinnedManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1
            }

            PluginWidget {
                id: distantWidget
                manifest: harness.distantManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1
            }
        }
    }

    // All five default to the host's generic 100,100, which would stack them
    // and make every gesture ambiguous.
    function placeWidgets() {
        PluginState.setPosition("runtime_group_alpha", harness.testScreen,
                                { x: 48, y: 48, placementStrategy: "free" });
        PluginState.setPosition("runtime_group_beta", harness.testScreen,
                                { x: 240, y: 48, placementStrategy: "free" });
        PluginState.setPosition("runtime_group_ghost", harness.testScreen,
                                { x: 48, y: 240, placementStrategy: "free" });
        PluginState.setPosition("runtime_group_pinned", harness.testScreen,
                                { x: 240, y: 240, placementStrategy: "free" });
        PluginState.setPosition("runtime_group_distant", harness.testScreen,
                                { x: 600, y: 300, placementStrategy: "free" });
    }

    // PluginState's FileView load lands asynchronously and replaces the whole
    // in-memory state, so anything written before it arrives is discarded -
    // and on a config directory with no state file yet, the empty file it
    // writes is then watched back in over whatever was set meanwhile. Keep
    // asking until the positions stick and the position Behavior has finished
    // animating to them.
    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            if (harness.at(alphaWidget, 48, 48)
                    && harness.at(betaWidget, 240, 48)
                    && harness.at(ghostWidget, 48, 240)
                    && harness.at(pinnedWidget, 240, 240)
                    && harness.at(distantWidget, 600, 300)) {
                setup.running = false;
                step1.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    // ---- marquee selection ----------------------------------------------

    Timer {
        id: step1
        interval: 300
        onTriggered: {
            harness.marqueeCluster();
            step2.running = true;
        }
    }

    Timer {
        id: step2
        interval: 400
        onTriggered: {
            harness.check("the marquee picks both plain widgets",
                          harness.isSelected(alphaWidget)
                              && harness.isSelected(betaWidget));
            harness.check("a click-through widget under the marquee is passed over",
                          !harness.isSelected(ghostWidget));
            harness.check("a per-widget-locked widget under it is passed over too",
                          !harness.isSelected(pinnedWidget));
            harness.check("a widget outside the marquee is not selected",
                          !harness.isSelected(distantWidget));
            harness.check("the selection is exactly the two",
                          canvas.selectedWidgets.length === 2);
            harness.check("a selected widget knows it",
                          alphaWidget.selected === true
                              && ghostWidget.selected === false);

            // Group drag: +96,+48 keeps the leader on the lattice, so the
            // offset assertions below cannot be muddied by the snap.
            harness.dragWidgetBy(alphaWidget, 96, 48);
            step3.running = true;
        }
    }

    // ---- group drag ------------------------------------------------------

    Timer {
        id: step3
        interval: 400
        onTriggered: {
            harness.check("the dragged widget lands where it was taken",
                          harness.at(alphaWidget, 144, 96));
            harness.check("the other selected widget moves by the same delta",
                          harness.at(betaWidget, 336, 96));
            harness.check("unselected widgets do not move",
                          harness.at(ghostWidget, 48, 240)
                              && harness.at(pinnedWidget, 240, 240)
                              && harness.at(distantWidget, 600, 300));
            harness.check("the selection survives the drag",
                          canvas.selectedWidgets.length === 2);

            const alphaSaved = PluginState.position("runtime_group_alpha", harness.testScreen);
            const betaSaved = PluginState.position("runtime_group_beta", harness.testScreen);
            harness.check("the leader's new position is persisted",
                          alphaSaved.x === 144 && alphaSaved.y === 96);
            harness.check("the follower's new position is persisted too",
                          betaSaved.x === 336 && betaSaved.y === 96);

            // Clamp: alpha is the leftmost member at x 144, so a hard-left
            // drag must stop the whole group after exactly -144.
            harness.dragWidgetBy(alphaWidget, -200, 0);
            step4.running = true;
        }
    }

    Timer {
        id: step4
        interval: 400
        onTriggered: {
            harness.check("the group stops when its first member hits the edge",
                          harness.at(alphaWidget, 0, 96));
            harness.check("the cluster does not deform at the edge",
                          harness.at(betaWidget, 192, 96));

            const betaSaved = PluginState.position("runtime_group_beta", harness.testScreen);
            harness.check("the clamped positions are persisted",
                          betaSaved.x === 192 && betaSaved.y === 96);

            driver.keyClick(Qt.Key_Escape);
            step5.running = true;
        }
    }

    // ---- deselection -----------------------------------------------------

    Timer {
        id: step5
        interval: 400
        onTriggered: {
            harness.check("escape clears the selection",
                          canvas.selectedWidgets.length === 0
                              && alphaWidget.selected === false);

            // With the group disarmed, the same gesture moves one widget.
            harness.dragWidgetBy(alphaWidget, 48, 48);
            step6.running = true;
        }
    }

    Timer {
        id: step6
        interval: 400
        onTriggered: {
            harness.check("after deselect a drag moves the dragged widget alone",
                          harness.at(alphaWidget, 48, 144)
                              && harness.at(betaWidget, 192, 96));

            harness.marqueeCluster();
            step7.running = true;
        }
    }

    Timer {
        id: step7
        interval: 400
        onTriggered: {
            harness.check("a second marquee selects the pair again",
                          canvas.selectedWidgets.length === 2);

            // A plain click on empty desktop is the other way out.
            driver.mouseClick(canvas, 900, 500, Qt.LeftButton);
            step8.running = true;
        }
    }

    Timer {
        id: step8
        interval: 400
        onTriggered: {
            harness.check("clicking empty desktop clears the selection",
                          canvas.selectedWidgets.length === 0);

            harness.marqueeCluster();
            step9.running = true;
        }
    }

    Timer {
        id: step9
        interval: 400
        onTriggered: {
            harness.check("the pair is selected once more",
                          canvas.selectedWidgets.length === 2);

            // Grabbing a widget outside the selection is also a click-away:
            // it deselects, and only the grabbed widget moves.
            harness.dragWidgetBy(distantWidget, 24, 0);
            step10.running = true;
        }
    }

    Timer {
        id: step10
        interval: 400
        onTriggered: {
            harness.check("dragging an unselected widget clears the selection",
                          canvas.selectedWidgets.length === 0);
            harness.check("and moves that widget alone",
                          harness.at(distantWidget, 624, 300)
                              && harness.at(alphaWidget, 48, 144)
                              && harness.at(betaWidget, 192, 96));

            harness.marqueeCluster();
            step11.running = true;
        }
    }

    // ---- the global lock -------------------------------------------------

    Timer {
        id: step11
        interval: 400
        onTriggered: {
            harness.check("selected again before locking",
                          canvas.selectedWidgets.length === 2);
            Config.options.background.widgetsLocked = true;
            harness.check("locking the desktop clears the selection",
                          canvas.selectedWidgets.length === 0);

            harness.marqueeCluster();
            step12.running = true;
        }
    }

    Timer {
        id: step12
        interval: 400
        onTriggered: {
            harness.check("a marquee on a locked desktop selects nothing",
                          canvas.selectedWidgets.length === 0);
            Config.options.background.widgetsLocked = false;

            // The PR's dead-binding trap, on a real follower: after a group
            // move, an external position change (a preset apply) must still
            // reach the widget - a broken binding leaves it frozen instead.
            PluginState.setPosition("runtime_group_beta", harness.testScreen,
                                    { x: 480, y: 300, placementStrategy: "free" });
            step13.running = true;
        }
    }

    // 900, not 400: unlike a drag step this move rides the position Behavior
    // (elementMove, 500ms) - checking at 400ms reads the animation midpoint
    // and fails a binding that is perfectly alive.
    Timer {
        id: step13
        interval: 900
        onTriggered: {
            harness.check("a follower still follows external position changes",
                          harness.at(betaWidget, 480, 300));
            harness.finish();
        }
    }
}
