import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

/**
 * Builds four real PluginWidgets on a real WidgetCanvas and drives per-widget
 * lock and click-through through actual mouse events.
 *
 * `tests/test_widget_interaction_modes.py` can only grep the bindings, and the
 * qmltestrunner suite cannot instantiate the host at all (it needs Quickshell's
 * types and a canvas parent). Neither can answer the question that matters:
 * does a click over a click-through widget actually reach the thing behind it,
 * and - the half this harness was missing - does it stop reaching the controls
 * the widget draws for itself.
 *
 * The layout mirrors Background.qml exactly - a right-click-only sentinel below
 * the canvas, standing in for the desktop menu's MouseArea - because that is
 * the propagation path the feature exists to restore. Left-clicks would prove
 * less: WidgetCanvas itself accepts them and swallows them either way. The two
 * content cases are the exception and click left on purpose: their whole point
 * is a control inside the widget, and that is what a user clicks it with.
 *
 * Run it against a throwaway config - it writes the note store:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetInteractionRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int desktopMenuHits: 0
    // Clicks that reached a MouseArea the widget declares for itself.
    property int contentAreaHits: 0

    readonly property string testScreen: "RUNTIME-TEST"
    readonly property string bundledRoot: Quickshell.shellPath("modules/common/plugins/bundled")

    function check(label, ok) {
        console.log(`[WidgetInteraction] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[WidgetInteraction] failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
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

    // The synthetic half of the content case: a widget that ships click-through
    // and declares a MouseArea of its own inside the host.
    readonly property var contentWidget: ({
        id: "runtime_content",
        name: "Runtime Content",
        defaultWidth: 160,
        defaultHeight: 100,
        desktopWidget: { type: "Item", clickThrough: true }
    })

    // The real half. The bundled notes widget draws a per-note delete button
    // that calls straight into the Notes singleton, so "did the widget's own
    // control fire" is observable from outside the widget with no instrumentation.
    readonly property var notesManifest: ({
        id: "notes",
        name: "Notes",
        grid: { cols: 2, rows: 2 },
        _basePath: `${harness.bundledRoot}/notes`,
        desktopWidget: { component: "Widget.qml", blur: false, clickThrough: true }
    })

    // Right-click over a widget, in canvas coordinates.
    function rightClickOver(widget) {
        driver.mouseClick(canvas, widget.x + widget.width / 2,
                          widget.y + widget.height / 2, Qt.RightButton);
    }

    function leftClickOver(widget) {
        driver.mouseClick(canvas, widget.x + widget.width / 2,
                          widget.y + widget.height / 2, Qt.LeftButton);
    }

    // Clicks the centre of `item` in canvas coordinates. Ids inside a loaded
    // Widget.qml are not reachable from here, so the bundled widgets carry
    // objectNames for exactly this.
    function clickItem(item) {
        const point = item.mapToItem(canvas, item.width / 2, item.height / 2);
        driver.mouseClick(canvas, point.x, point.y, Qt.LeftButton);
    }

    function findByName(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = harness.findByName(item.children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    TestCase {
        id: driver
        when: false
        name: "WidgetInteractionDriver"
    }

    FloatingWindow {
        visible: true
        implicitWidth: 1000
        implicitHeight: 560
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
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1
            }

            PluginWidget {
                id: plainPluginWidget
                manifest: harness.plainWidget
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1
            }

            // A MouseArea declared as the host's own child is what every
            // ported widget's controls amount to once the plugin tree is
            // flattened - and what `MouseArea.enabled` on the host does not
            // reach. Left *and* right so a right-click that this swallows is
            // visibly a swallowed one, not a button it never accepted.
            PluginWidget {
                id: contentPluginWidget
                manifest: harness.contentWidget
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
                wallpaperScale: 1

                MouseArea {
                    id: contentArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: harness.contentAreaHits++
                }
            }

            PluginWidget {
                id: notesPluginWidget
                manifest: harness.notesManifest
                screenName: harness.testScreen
                screenWidth: 1000
                screenHeight: 560
                scaledScreenWidth: 1000
                scaledScreenHeight: 560
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
        PluginState.setPosition(harness.contentWidget.id, harness.testScreen,
                                { x: 40, y: 300, placementStrategy: "free" });
        PluginState.setPosition(harness.notesManifest.id, harness.testScreen,
                                { x: 640, y: 40, placementStrategy: "free" });
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
            if (!PluginState.ready || !Config.ready || !Notes.ready)
                return;
            Config.options.background.widgetsLocked = false;
            if (Math.round(clickThroughWidget.x) === 40
                    && Math.round(plainPluginWidget.x) === 360
                    && Math.round(contentPluginWidget.y) === 300
                    && Math.round(notesPluginWidget.x) === 640) {
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
            step4.running = true;
        }
    }

    // The half `MouseArea.enabled` on the host never covered: a control the
    // widget draws for itself. Disabling the host stops the *host* handling
    // events; it does not disable the items under it, so this MouseArea kept
    // taking clicks with click-through on.
    Timer {
        id: step4
        interval: 400
        onTriggered: {
            harness.check("the content widget ships click-through on",
                          contentPluginWidget.clickThrough === true);

            const menuBefore = harness.desktopMenuHits;
            const contentBefore = harness.contentAreaHits;
            harness.rightClickOver(contentPluginWidget);
            harness.check("a click-through widget's own MouseArea takes nothing",
                          harness.contentAreaHits === contentBefore);
            harness.check("and the click still reaches the desktop menu",
                          harness.desktopMenuHits === menuBefore + 1);

            Config.options.background.widgetsLocked = false;
            step5.running = true;
        }
    }

    // The control. Without it "took nothing" is equally satisfied by a widget
    // that was never under the pointer, or a harness that stopped delivering.
    Timer {
        id: step5
        interval: 400
        onTriggered: {
            PluginState.setOption(harness.contentWidget.id, "clickThrough", false);
            const menuBefore = harness.desktopMenuHits;
            const contentBefore = harness.contentAreaHits;
            harness.leftClickOver(contentPluginWidget);
            harness.check("with click-through off the same control fires",
                          harness.contentAreaHits === contentBefore + 1);
            harness.check("and the desktop menu sees nothing",
                          harness.desktopMenuHits === menuBefore);

            // Pinned but still clickable is the state the two separate flags
            // exist for, so the gate has to be click-through and not the
            // resolved lock - which would deaden every locked widget's
            // controls as a side effect of pinning it.
            PluginState.setOption(harness.contentWidget.id, "positionLocked", true);
            step6.running = true;
        }
    }

    Timer {
        id: step6
        interval: 400
        onTriggered: {
            harness.check("a pinned widget is not draggable",
                          contentPluginWidget.draggable === false);
            const contentBefore = harness.contentAreaHits;
            harness.leftClickOver(contentPluginWidget);
            harness.check("but its own controls still work",
                          harness.contentAreaHits === contentBefore + 1);

            PluginState.setOption(harness.contentWidget.id, "positionLocked", false);

            // A real widget with a real control, not a synthetic MouseArea: the
            // bundled notes widget's per-note delete button calls straight into
            // the Notes singleton, so the outcome is observable from out here.
            Notes.addNote("runtime click-through note");
            step7.running = true;
        }
    }

    Timer {
        id: step7
        interval: 600
        onTriggered: {
            harness.check("the notes widget ships click-through for this run",
                          notesPluginWidget.clickThrough === true);
            harness.check("the store has the note to delete",
                          Notes.list.length === 1);

            const deleteButton = harness.findByName(notesPluginWidget, "deleteNoteButton");
            harness.check("the notes widget draws a per-note delete button",
                          deleteButton !== null);
            if (!deleteButton) {
                harness.finish();
                return;
            }
            harness.clickItem(deleteButton);
            step8.running = true;
        }
    }

    Timer {
        id: step8
        interval: 500
        onTriggered: {
            harness.check("a real widget's own button is dead under click-through",
                          Notes.list.length === 1);

            // On a build where the click above went through, the note is gone
            // and the control below would fail for the wrong reason - the real
            // failure is already recorded, so put a note back and keep going.
            if (Notes.list.length === 0)
                Notes.addNote("runtime click-through note");
            PluginState.setOption(harness.notesManifest.id, "clickThrough", false);
            step9.running = true;
        }
    }

    // The control, on the real widget: the same button, the same coordinates,
    // click-through off. Without it "dead" is also what a mis-aimed click and
    // a widget that never rendered its list would report.
    Timer {
        id: step9
        interval: 600
        onTriggered: {
            harness.check("switching click-through off gives the widget back",
                          notesPluginWidget.clickThrough === false);
            const deleteButton = harness.findByName(notesPluginWidget, "deleteNoteButton");
            harness.check("the delete button is still there to click",
                          deleteButton !== null);
            if (!deleteButton) {
                harness.finish();
                return;
            }
            harness.clickItem(deleteButton);
            step10.running = true;
        }
    }

    Timer {
        id: step10
        interval: 500
        onTriggered: {
            harness.check("and the same button on the same widget now deletes",
                          Notes.list.length === 0);
            harness.finish();
        }
    }
}
