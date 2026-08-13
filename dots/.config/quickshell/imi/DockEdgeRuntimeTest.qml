import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * Drives the dock's pinned-app reorder with real mouse events, at a horizontal
 * edge and at a vertical one.
 *
 * This exists because of the specific way a vertical dock can be broken. The
 * layout is the visible half and the easy half: a column of icons that lays
 * out, spaces correctly and looks finished can still have its reorder
 * completely inert, because every comparison in `DragApps` used to be an x.
 * In a column every slot centre has the SAME x, so the "nearest other slot"
 * loop returns whichever index it reached first and the swap test compares a
 * number against itself. Nothing errors, nothing logs, and the icons simply
 * refuse to move past each other.
 *
 * So the discriminating check here is not "does the column reorder" - it is
 * the pair: a drag ALONG the strip must reorder, and a drag ACROSS it must
 * not. The second is what the old code got wrong in both directions at once
 * (it swapped on any sideways twitch, then swapped back).
 *
 * The horizontal edge is the control. Three "nothing happened" results prove
 * nothing if the harness quietly stopped delivering events, so the run starts
 * by reordering a row.
 *
 * What this CANNOT see: it builds the dock's content tree in a FloatingWindow,
 * not on a layer surface. Weston implements no wlr-layer-shell, so the
 * anchors, the exclusive zone, the reveal push and the compositor's inferred
 * slide direction are all invisible to it - as are the running dots' position,
 * the icon sizing and every other thing that is a look rather than a
 * behaviour. Those are `hyprctl layers -j` plus a pair of eyes.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p DockEdgeRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    readonly property var order: ["alpha", "beta", "gamma"]

    function check(label, ok) {
        console.log(`[DockEdge] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function pinned() {
        return (Config.options.dock.pinnedApps ?? []).slice();
    }

    function sameOrder(a, b) {
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++)
            if (a[i] !== b[i])
                return false;
        return true;
    }

    function resetOrder() {
        Config.options.dock.pinnedApps = harness.order.slice();
    }

    FloatingWindow {
        visible: true
        implicitWidth: 700
        implicitHeight: 700
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "DockEdgeDriver"
        }

        // The strip turns with the dock, exactly as the dock body does: the
        // long axis is the icons', the short one is the dock's thickness.
        Item {
            id: strip
            x: 200
            y: 60
            width: slots.vertical ? 60 : 520
            height: slots.vertical ? 520 : 60

            DragApps {
                id: slots
                btnSize: 46
                btnSpacing: 1
                buttonPadding: 8
            }
        }
    }

    // ---- gestures --------------------------------------------------------
    //
    // Slot i sits i steps ALONG the strip, which is the placement under test,
    // so the gesture is derived from the same two numbers the layout is - a
    // changed btnSize moves the press with it rather than leaving it pointing
    // at the gap between two icons.
    function slotCenter(index) {
        const along = index * (slots.btnSize + slots.btnSpacing) + slots.btnSize / 2;
        return slots.vertical
            ? Qt.point(slots.width / 2, along)
            : Qt.point(along, slots.height / 2);
    }

    function dragSlot(index, dx, dy) {
        const p = harness.slotCenter(index);
        driver.mousePress(slots, p.x, p.y, Qt.LeftButton);
        driver.mouseMove(slots, p.x + dx * 0.35, p.y + dy * 0.35, 20, Qt.LeftButton);
        driver.mouseMove(slots, p.x + dx * 0.7, p.y + dy * 0.7, 20, Qt.LeftButton);
        driver.mouseMove(slots, p.x + dx, p.y + dy, 20, Qt.LeftButton);
        driver.mouseRelease(slots, p.x + dx, p.y + dy, Qt.LeftButton);
    }

    // ---- the checks ------------------------------------------------------

    // A slot is recognised by the property that places it, so a harness that
    // finds nothing is a harness pointed at a tree that no longer places its
    // slots - which is a failure, not an empty pass.
    function slotItem(index) {
        for (const child of slots.children)
            if (child.slotOffset !== undefined && child.index === index)
                return child;
        return null;
    }

    function scoreLayout(label, expectVertical) {
        const first = harness.slotItem(0);
        const second = harness.slotItem(1);
        if (!first || !second) {
            harness.check(`${label}: the slots exist`, false);
            return;
        }
        harness.check(`${label}: the slots stack along the strip`,
                      expectVertical
                          ? (second.y > first.y && second.x === first.x)
                          : (second.x > first.x && second.y === first.y));
    }

    function scoreReordered(label, expected) {
        harness.check(`${label}: ${expected.join(",")}`,
                      harness.sameOrder(harness.pinned(), expected));
    }

    readonly property var steps: [
        // The control, and the proof events are arriving at all.
        () => harness.scoreLayout("a bottom dock", false),
        () => harness.dragSlot(0, 60, 0),
        () => harness.scoreReordered("dragging along a row swaps",
                                     ["beta", "alpha", "gamma"]),

        () => { harness.resetOrder(); Config.options.dock.edge = "left"; },
        () => harness.scoreLayout("a left dock", true),

        // The half a plausible-looking column silently loses.
        () => harness.dragSlot(0, 0, 60),
        () => harness.scoreReordered("dragging along a column swaps",
                                     ["beta", "alpha", "gamma"]),

        // ...and the half the old x-only comparison got wrong in the other
        // direction: with every slot centre sharing an x, a sideways twitch
        // swapped, then swapped back, for as long as the pointer moved.
        () => harness.resetOrder(),
        () => harness.dragSlot(0, 25, 0),
        () => harness.scoreReordered("dragging across a column does not",
                                     harness.order),

        // Back to the shipped default, so a leftover edge cannot make the
        // last check pass for the wrong reason.
        () => { harness.resetOrder(); Config.options.dock.edge = "bottom"; },
        () => harness.scoreLayout("back at the bottom", false),
        () => harness.dragSlot(1, -60, 0),
        () => harness.scoreReordered("and a row still swaps after the round trip",
                                     ["beta", "alpha", "gamma"])
    ]

    property int stepIndex: 0

    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!Config.ready)
                return;
            Config.options.dock.edge = "bottom";
            if (!harness.sameOrder(harness.pinned(), harness.order)) {
                harness.resetOrder();
                return;
            }
            setup.running = false;
            runner.running = true;
        }
    }

    // One step per tick. The slots carry a Behavior on x and y, so a check
    // sharing a frame with the release it scores would read a position the
    // animation is still travelling through - and an edge change reflows the
    // whole strip, which is a layout pass rather than a property write.
    Timer {
        id: runner
        interval: 600
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[DockEdge] failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
