import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.imi.sidebarRight.quickToggles
import "modules/common/functions/layout_ops.js" as LayoutOps

/**
 * Drives the real Android quick toggle panel through the layout edits the edit
 * mode performs, and checks that every rendered button still shows its own
 * toggle.
 *
 * The bug this exists for is not visible from the config: the stored layout is
 * correct throughout, and only the rendered delegate is wrong. DelegateChooser
 * picks a component when a delegate is created and never re-picks for one that
 * survives a model update, so a row entry that changes in place keeps the
 * previous toggle's component - its QuickToggleModel, icon, name and action -
 * while carrying the new entry's data. Restarting the shell "fixes" it, which
 * is what makes it easy to mistake for a persistence problem.
 *
 * Every edit reflows the rows, because rows are packed by toggle size, so the
 * cases that matter are the ones that move an entry across a row boundary. A
 * same-row reorder diffs as a move and was never broken - checking only that is
 * how the first fix passed while the panel stayed scrambled.
 *
 * It also drives the half a keyed model added: a reorder must MOVE the tile's
 * delegate rather than rebuild it, and the tile must be seen travelling to its
 * new slot rather than arriving there. A settled position is what a snap and an
 * animation agree on, so the sample is taken mid-flight.
 *
 * The reorder is spelled the way a drop spells it - an in-place splice of the
 * live `Config` array (26b625905) - because that is the path the panel is
 * observed through, and an edit that reassigns the array would exercise a
 * trigger the user never takes.
 *
 * Launched by tests/test_quick_toggles_layout_runtime.py against a throwaway
 * XDG_CONFIG_HOME. Never point it at a real config dir - it rewrites the toggle
 * layout.
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property var expectedIcon: ({})

    function check(label, ok, detail) {
        harness.checksRun++;
        console.log(`[QuickToggles] ${label}: ${ok ? "ok" : "FAIL"}${ok ? "" : " - " + detail}`);
        if (!ok) harness.failures++;
    }

    // Every button the panel currently renders, as "type:icon".
    function rendered() {
        let seen = [];
        function walk(item) {
            if (!item) return;
            if (item.buttonData !== undefined && item.toggleModel !== undefined)
                seen.push(item.buttonData?.type + ":" + item.buttonIcon);
            for (let i = 0; i < item.children.length; i++) walk(item.children[i]);
        }
        walk(panel);
        return seen;
    }

    // A button whose icon is not the icon its own type had at startup is
    // rendering another toggle's component.
    function verify(label) {
        const shown = harness.rendered();
        const wrong = shown.filter(entry => {
            const parts = entry.split(":");
            return harness.expectedIcon[parts[0]] && harness.expectedIcon[parts[0]] !== parts[1];
        });
        harness.check(label, wrong.length === 0,
                      `these buttons kept another toggle's component: ${wrong.join(" ")} (all: ${shown.join(" ")})`);
    }

    function editToggles(fn) {
        const cfg = Config.options.sidebar.quickToggles.android;
        const next = cfg.toggles.map(entry => Object.assign({}, entry));
        fn(next);
        cfg.toggles = next;
    }

    function typeIndex(list, type) { return list.findIndex(entry => entry.type === type); }

    // The rendered tile for a toggle type, as the object rather than as a
    // description of it: whether a reorder kept the delegate is a question
    // about identity, and every readable property survives a rebuild.
    function tileFor(type) {
        let found = null;
        function walk(item) {
            if (!item || found) return;
            if (item.buttonData !== undefined && item.toggleModel !== undefined
                && item.buttonData?.type === type) {
                found = item;
                return;
            }
            for (let i = 0; i < item.children.length; i++) walk(item.children[i]);
        }
        walk(panel);
        return found;
    }

    property var movedTile: null
    property real movedFromX: 0
    property real movedMidX: 0

    Item {
        width: 500
        height: 400
        AndroidQuickPanel { id: panel; width: 500 }
    }

    Timer {
        interval: 2500
        running: true
        repeat: false
        onTriggered: {
            harness.rendered().forEach(entry => {
                const parts = entry.split(":");
                harness.expectedIcon[parts[0]] = parts[1];
            });
            harness.check("the panel rendered some toggles",
                          Object.keys(harness.expectedIcon).length > 0, "nothing rendered");
            harness.verify("every toggle starts with its own icon");

            // Cross-row swap of differently sized toggles: reflows the rows, so
            // the entry lands at an index another toggle occupied.
            harness.editToggles(list => {
                const a = harness.typeIndex(list, "idleInhibitor");
                const b = harness.typeIndex(list, "nightLight");
                const tmp = list[a]; list[a] = list[b]; list[b] = tmp;
            });
            Qt.callLater(() => {
                harness.verify("a reflowing cross-row swap keeps every icon");

                harness.editToggles(list => { list[harness.typeIndex(list, "network")].size = 1; });
                Qt.callLater(() => {
                    harness.verify("resizing a toggle keeps every icon");

                    harness.editToggles(list => list.splice(harness.typeIndex(list, "mic"), 1));
                    Qt.callLater(() => {
                        harness.verify("removing a toggle keeps every icon");

                        harness.editToggles(list => list.push({ type: "mic", size: 2 }));
                        Qt.callLater(() => {
                            harness.verify("adding a toggle back keeps every icon");
                            harness.startReorder();
                        });
                    });
                });
            });
        }
    }

    // The drop's own commit: the dragged toggle travels to the slot it was
    // dropped on and the ones it passed shift back one.
    function startReorder() {
        harness.movedTile = harness.tileFor("nightLight");
        harness.movedFromX = harness.movedTile ? harness.movedTile.x : -1;
        harness.check("the toggle to be moved is not already in the first slot",
                      harness.movedFromX > 0, `it starts at x ${harness.movedFromX}`);
        const list = Config.options.sidebar.quickToggles.android.toggles;
        LayoutOps.moveInPlace(list, harness.typeIndex(list, "nightLight"), 0);
        Qt.callLater(() => {
            harness.verify("a reorder keeps every icon");
            harness.check("a reorder moves the delegate instead of rebuilding it",
                          harness.movedTile !== null && harness.tileFor("nightLight") === harness.movedTile,
                          "the tile at that toggle's new position is a different object");
            midFlight.start();
        });
    }

    Timer {
        id: midFlight
        interval: 80
        onTriggered: {
            harness.movedMidX = harness.movedTile ? harness.movedTile.x : -1;
            settled.start();
        }
    }

    Timer {
        id: settled
        interval: 600
        onTriggered: {
            const finalX = harness.movedTile ? harness.movedTile.x : -1;
            harness.check("the moved tile ends up in the first slot", finalX === 0,
                          `it settled at x ${finalX}`);
            // A settled position is the same number whether the tile animated
            // or teleported, so the check that can tell them apart is this one.
            harness.check("the moved tile travels to its new slot instead of snapping",
                          harness.movedMidX > finalX && harness.movedMidX < harness.movedFromX,
                          `80ms in it was at x ${harness.movedMidX}, between ${finalX} and ${harness.movedFromX}`);
            console.log(`[QuickToggles] checks: ${harness.checksRun} failures: ${harness.failures}`);
            Qt.exit(harness.failures === 0 ? 0 : 1);
        }
    }
}
