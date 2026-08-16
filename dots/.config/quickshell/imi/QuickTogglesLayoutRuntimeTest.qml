import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.imi.sidebarRight.quickToggles

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
                            console.log(`[QuickToggles] checks: ${harness.checksRun} failures: ${harness.failures}`);
                            Qt.exit(harness.failures === 0 ? 0 : 1);
                        });
                    });
                });
            });
        }
    }
}
