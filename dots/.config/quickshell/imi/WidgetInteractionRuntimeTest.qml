import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/**
 * Builds two real PluginWidgets on a real WidgetCanvas and drives per-widget
 * lock and click-through through actual mouse events.
 *
 * `tests/test_widget_interaction_modes.py` can only grep the bindings, and the
 * qmltestrunner suite cannot instantiate the host at all (it needs Quickshell's
 * types and a canvas parent). Neither can answer the question that matters:
 * does a click over a click-through widget actually reach the thing behind it.
 *
 * The layout mirrors Background.qml exactly - a right-click-only sentinel below
 * the canvas, standing in for the desktop menu's MouseArea - because that is
 * the propagation path the feature exists to restore. Left-clicks would prove
 * less: WidgetCanvas itself accepts them and swallows them either way.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetInteractionRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int desktopMenuHits: 0

    readonly property string testScreen: "RUNTIME-TEST"

    function check(label, ok) {
        console.log(`[WidgetInteraction] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // A widget that ships click-through on, like the bundled visualizer.
    readonly property var shippedClickThrough: ({
        id: "runtime_click_through",
        name: "Runtime Click Through",
        defaultWidth: 160,
        defaultHeight: 100,
        desktopWidget: { type: "Item", clickThrough: true }
    })

    // A widget that ships nothing, to prove the defaults stay neutral.
    readonly property var plainWidget: ({
        id: "runtime_plain",
        name: "Runtime Plain",
        defaultWidth: 160,
        defaultHeight: 100,
        desktopWidget: { type: "Item" }
    })

    // Right-click over a widget, in canvas coordinates.
    function rightClickOver(widget) {
        driver.mouseClick(canvas, widget.x + widget.width / 2,
                          widget.y + widget.height / 2, Qt.RightButton);
    }

    TestCase {
        id: driver
        when: false
        name: "WidgetInteractionDriver"
    }

    FloatingWindow {
        visible: true
        implicitWidth: 640
        implicitHeight: 400
        color: "black"

        // Stands in for Background.qml's desktopRightClickArea: a sibling of
        // the canvas, below it, right-button only. Anything that reaches this
        // would have opened the desktop menu on the real background.
        MouseArea {
            id: desktopMenu
            anchors.fill: parent
            z: -2
            acceptedButtons: Qt.RightButton
            onClicked: harness.desktopMenuHits++
        }

        WidgetCanvas {
            id: canvas
            anchors.fill: parent
            z: 2

            PluginWidget {
                id: clickThroughWidget
                manifest: harness.shippedClickThrough
                screenName: harness.testScreen
                screenWidth: 640
                screenHeight: 400
                scaledScreenWidth: 640
                scaledScreenHeight: 400
                wallpaperScale: 1
            }

            PluginWidget {
                id: plainPluginWidget
                manifest: harness.plainWidget
                screenName: harness.testScreen
                screenWidth: 640
                screenHeight: 400
                scaledScreenWidth: 640
                scaledScreenHeight: 400
                wallpaperScale: 1
            }
        }
    }

    // Both widgets default to the host's generic 100,100, which would stack
    // them on top of each other and make every click ambiguous.
    function placeWidgets() {
        PluginState.setPosition(harness.shippedClickThrough.id, harness.testScreen,
                                { x: 40, y: 40, placementStrategy: "free" });
        PluginState.setPosition(harness.plainWidget.id, harness.testScreen,
                                { x: 360, y: 40, placementStrategy: "free" });
    }

    // PluginState's FileView load lands asynchronously and replaces the whole
    // in-memory state, so anything written before `ready` is thrown away.
    //
    // Waiting for `ready` is still not enough on a config directory with no
    // state file yet: that path writes an empty state, its own `watchChanges`
    // sees the write, and the reload replays the empty file over whatever was
    // set in the meantime. So keep asking until the positions actually stick -
    // and until the position Behavior has finished animating to them. Both
    // widgets otherwise sit on the host's default 100,100, exactly on top of
    // each other, and every click lands on whichever was declared last. That
    // made this harness report a click-through failure that did not exist.
    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            if (Math.round(clickThroughWidget.x) === 40
                    && Math.round(plainPluginWidget.x) === 360) {
                setup.running = false;
                step1.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    Timer {
        id: step1
        interval: 300
        onTriggered: {
            // If these ever overlap again, the propagation checks below stop
            // testing propagation and start testing stacking order.
            harness.check("the two widgets are laid out apart",
                          clickThroughWidget.x + clickThroughWidget.width
                              < plainPluginWidget.x);
            harness.check("manifest clickThrough reaches the host",
                          clickThroughWidget.clickThrough === true);
            harness.check("click-through widget is disabled",
                          clickThroughWidget.enabled === false);
            harness.check("click-through implies not draggable",
                          clickThroughWidget.draggable === false);
            harness.check("a widget that ships nothing stays interactive",
                          plainPluginWidget.enabled === true
                              && plainPluginWidget.draggable === true);

            // The load-bearing check. A right-click over the click-through
            // widget must reach the desktop-menu area beneath the canvas.
            const before = harness.desktopMenuHits;
            harness.rightClickOver(clickThroughWidget);
            harness.check("right-click passes through to the desktop menu",
                          harness.desktopMenuHits === before + 1);

            // And the control: the same click over the plain widget is eaten
            // by the widget itself. Without this the check above would pass on
            // a harness whose sentinel simply covers everything.
            const stillBefore = harness.desktopMenuHits;
            harness.rightClickOver(plainPluginWidget);
            harness.check("an ordinary widget still swallows its own clicks",
                          harness.desktopMenuHits === stillBefore);

            // AbstractWidget maps right-click to the global lock, so that last
            // click just flipped it. Put it back before testing precedence.
            Config.options.background.widgetsLocked = false;
            step2.running = true;
        }
    }

    Timer {
        id: step2
        interval: 400
        onTriggered: {
            // Turning a shipped default off has to work, and the binding has
            // to survive it - if anything ever assigns these properties
            // directly, the PluginState binding dies and this stays false.
            PluginState.setOption(harness.shippedClickThrough.id, "clickThrough", false);
            harness.check("the user can switch a shipped click-through off",
                          clickThroughWidget.clickThrough === false
                              && clickThroughWidget.enabled === true
                              && clickThroughWidget.draggable === true);

            const before = harness.desktopMenuHits;
            harness.rightClickOver(clickThroughWidget);
            harness.check("and it takes its clicks back",
                          harness.desktopMenuHits === before);
            Config.options.background.widgetsLocked = false;
            step3.running = true;
        }
    }

    Timer {
        id: step3
        interval: 400
        onTriggered: {
            // Locked but clickable: the state that justifies two options
            // rather than one.
            PluginState.setOption(harness.plainWidget.id, "positionLocked", true);
            harness.check("a per-widget lock stops dragging on its own",
                          plainPluginWidget.draggable === false);
            harness.check("a locked widget still takes clicks",
                          plainPluginWidget.enabled === true);
            harness.check("locking one widget leaves the others alone",
                          clickThroughWidget.draggable === true);

            // Precedence: the global switch ORs in, it does not override.
            Config.options.background.widgetsLocked = true;
            harness.check("the global lock still locks an unpinned widget",
                          clickThroughWidget.draggable === false);
            Config.options.background.widgetsLocked = false;
            harness.check("unlocking globally does not unpin a pinned widget",
                          plainPluginWidget.draggable === false);
            harness.check("and it does give the unpinned one back",
                          clickThroughWidget.draggable === true);

            console.log(`[WidgetInteraction] failures: ${harness.failures}`);
            Qt.exit(harness.failures === 0 ? 0 : 1);
        }
    }
}
