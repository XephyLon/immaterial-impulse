import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.panels.lock
import qs.modules.imi.lock
import "modules/common/functions/edit_mode.js" as EditMode
import "modules/common/functions/lock_islands.js" as LockIslands

/**
 * Drives the lock islands' reorder with real mouse events, on the real
 * LockSurface with the real preview context, committing against the real
 * `Config.options.lock.islands.*` lists.
 *
 * What only real events can show here: the press lands on the edit overlay's
 * eater, `ReorderDragArea`'s handler takes over past the threshold, the drop
 * maps through `dropTarget` over centres that carry HOLES (an invisible slot
 * - the fingerprint icon with no prints enrolled, the battery pair on a
 * desktop - and the dragged one), and the commit merges back through
 * `storedOrder` without eating an id a newer version stored. The password
 * slot is the negative: it loads no overlay at all, so the same gesture over
 * it must move nothing.
 *
 * Weston implements no wlr-layer-shell, so nothing about the real session
 * lock or the background surface is visible here - this drives the surface's
 * content tree in a plain window, exactly the shape of BarEditRuntimeTest.
 *
 * Run against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p LockIslandReorderRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[LockIslands] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function slot(name) {
        return driver.findChild(surface, "islandSlot_" + name);
    }

    // A stepped drag in SURFACE coordinates, so QtTest maps each event the
    // same way a pointer would arrive.
    function dragBetween(from, to) {
        driver.mousePress(surface, from.x, from.y, Qt.LeftButton);
        driver.mouseMove(surface, from.x + (to.x - from.x) * 0.3,
                         from.y + (to.y - from.y) * 0.3, 20, Qt.LeftButton);
        driver.mouseMove(surface, from.x + (to.x - from.x) * 0.7,
                         from.y + (to.y - from.y) * 0.7, 20, Qt.LeftButton);
        driver.mouseMove(surface, to.x, to.y, 20, Qt.LeftButton);
        driver.mouseRelease(surface, to.x, to.y, Qt.LeftButton);
    }

    function centreOf(item) {
        return item.mapToItem(surface, item.width / 2, item.height / 2);
    }

    FloatingWindow {
        visible: true
        implicitWidth: 1400
        implicitHeight: 600
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "LockIslandDriver"
        }

        LockSurface {
            id: surface
            anchors.fill: parent
            interactive: false
            context: LockPreviewContext {}
        }
    }

    property var steps: [
        // ---- the overlays arm with the mode --------------------------------
        () => {
            GlobalStates.editMode = true;
        },
        () => {
            harness.check("a movable slot grows its overlay and the field does not",
                          driver.findChild(harness.slot("sleep"), "lockIslandEditItem") !== null
                          && driver.findChild(harness.slot("password"), "lockIslandEditItem") === null);
        },

        // ---- a drag along the right island moves, with move semantics ------
        () => {
            const from = harness.centreOf(harness.slot("sleep"));
            const past = harness.centreOf(harness.slot("reboot"));
            harness.dragBetween(from, Qt.point(past.x + 30, past.y));
        },
        () => {
            const stored = Config.options.lock.islands.right;
            harness.check("sleep lands after reboot and the two between shift one",
                          JSON.stringify([...stored])
                          === JSON.stringify(["battery", "power", "reboot", "sleep"]));
        },

        // ---- the rendered order follows the store --------------------------
        () => {
            harness.check("the island redraws in the committed order",
                          JSON.stringify([...surface.rightOrder])
                          === JSON.stringify(["battery", "power", "reboot", "sleep"]));
        },

        // ---- the password slot takes no drag -------------------------------
        () => {
            const before = JSON.stringify([...surface.mainOrder]);
            const from = harness.centreOf(harness.slot("password"));
            const to = harness.centreOf(harness.slot("confirm"));
            harness.dragBetween(from, Qt.point(to.x + 30, to.y));
            harness.check("dragging the password field moves nothing",
                          JSON.stringify([...surface.mainOrder]) === before);
        },

        // ---- its neighbours still reorder around it ------------------------
        () => {
            const from = harness.centreOf(harness.slot("confirm"));
            const to = harness.centreOf(harness.slot("password"));
            harness.dragBetween(from, Qt.point(to.x - 60, to.y));
        },
        () => {
            harness.check("confirm moves in front of the field it cannot displace",
                          JSON.stringify([...surface.mainOrder])
                          === JSON.stringify(["fingerprint", "confirm", "password"]));
        },

        // ---- an id a newer shell stored survives a reorder here ------------
        () => {
            Config.options.lock.islands.left = ["media", "someFutureItem",
                "username", "keyboardLayout", "fcitx"];
        },
        () => {
            const from = harness.centreOf(harness.slot("keyboardLayout"));
            const to = harness.centreOf(harness.slot("username"));
            harness.dragBetween(from, Qt.point(to.x - 20, to.y));
        },
        () => {
            const stored = [...Config.options.lock.islands.left];
            harness.check("the unknown id keeps its presence through the commit",
                          stored.includes("someFutureItem"));
            harness.check("...and the known ids carry the move",
                          stored.indexOf("keyboardLayout") < stored.indexOf("username"));
        },

        // ---- Escape's cancel abandons the gesture --------------------------
        //
        // This drives the LISTENER by emitting the signal directly - there is
        // no WidgetCanvas in this harness, so the ladder's emit gate (the
        // cancelGesture branch reaching editLockDragActive) is pinned by
        // test_lock_islands_contract.py rather than exercised here. Do not
        // read this step as evidence the ladder works end to end.
        () => {
            harness.lockLeftBefore = JSON.stringify([...Config.options.lock.islands.left]);
            const from = harness.centreOf(harness.slot("username"));
            driver.mousePress(surface, from.x, from.y, Qt.LeftButton);
            driver.mouseMove(surface, from.x + 60, from.y, 20, Qt.LeftButton);
            harness.check("a drag in flight raises the ladder's flag",
                          GlobalStates.editLockDragActive === true);
            GlobalStates.editReorderCancel();
            harness.check("the cancel stands the flag down before the release",
                          GlobalStates.editLockDragActive === false);
            driver.mouseRelease(surface, from.x + 60, from.y, Qt.LeftButton);
        },
        () => {
            harness.check("the abandoned drag committed nothing",
                          JSON.stringify([...Config.options.lock.islands.left])
                          === harness.lockLeftBefore);
        },

        // ---- the mode's exit mid-drag commits nothing either ---------------
        () => {
            const from = harness.centreOf(harness.slot("username"));
            driver.mousePress(surface, from.x, from.y, Qt.LeftButton);
            driver.mouseMove(surface, from.x + 60, from.y, 20, Qt.LeftButton);
            GlobalStates.editMode = false;
            harness.check("the exit clears the drag's flag",
                          GlobalStates.editLockDragActive === false);
            driver.mouseRelease(surface, from.x + 60, from.y, Qt.LeftButton);
        },
        () => {
            harness.check("a release after the exit stores no order",
                          JSON.stringify([...Config.options.lock.islands.left])
                          === harness.lockLeftBefore);
        }
    ]

    property string lockLeftBefore: ""
    property int stepIndex: 0

    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!Config.ready)
                return;
            setup.running = false;
            runner.running = true;
        }
    }

    Timer {
        id: runner
        interval: 500
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[LockIslands] checks: ${harness.checksRun} failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
