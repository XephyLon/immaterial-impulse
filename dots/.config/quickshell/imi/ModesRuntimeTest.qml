import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * The modes engine inside a real (nested) shell: the presets seed once, a
 * mode starts by hand and is what the pill, the toggle and the history
 * read; it ends and reverts; the last one comes back on toggleLast; an
 * automatic start is refused while automation is off but a manual one is
 * not; a routine template becomes a routine and goes away again. Launched
 * by tests/test_modes_runtime.py with a throwaway XDG home.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    readonly property var keep: Modes

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[ModesRt] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[ModesRt] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    function historyOf(id, event) {
        return Modes.history.filter(h => h.kind === "mode" && h.id === id && h.event === event);
    }

    Timer {
        id: driver
        interval: 250; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 40000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready || !Modes.ready) return;
            switch (harness.step) {
            case 0: {
                // A fresh config: reconcile() seeded the seven presets before
                // `ready`, so they are already here; seeding is idempotent.
                Modes.seedPresets();
                harness.check("the presets seed into the config once",
                    Modes.modes.length === 7 && Config.options.modes.presetsSeeded === true
                    && Modes.modes.some(m => m.id === "focus" && m.preset));
                Modes.seedPresets();
                harness.check("seeding again adds nothing", Modes.modes.length === 7);
                harness.check("nothing is on at start", !Modes.active && Modes.activeMode === null);
                harness.check("an unknown mode does not start", Modes.activate("no-such-mode") === false && !Modes.active);
                harness.check("a manual start turns the mode on",
                    Modes.activate("focus") === true && Modes.active && Modes.activeMode.id === "focus"
                    && Modes.activeSource === "manual" && Modes.activeSince > 0);
                harness.check("the state the pill and the toggle read is persisted",
                    Persistent.states.modes.activeId === "focus" && Persistent.states.modes.lastUsedModeId === "focus");
                harness.check("the start lands in the activity log", harness.historyOf("focus", "start").length === 1);
                harness.check("starting the active mode again is a no-op", Modes.activate("focus") === true && harness.historyOf("focus", "start").length === 1);
                harness.check("ending it clears the state and logs the end",
                    Modes.deactivate("manual") === true && !Modes.active && Persistent.states.modes.activeId === ""
                    && harness.historyOf("focus", "end").length === 1);
                harness.step = 1;
                break;
            }
            case 1: {
                // deactivate re-evaluates on the next tick; give it one.
                harness.check("toggleLast brings the last mode back", Modes.toggleLast() === true && Modes.active && Modes.activeMode.id === "focus");
                harness.check("toggleLast on an active mode ends it", Modes.toggleLast() === true && !Modes.active);
                Config.options.modes.enable = false;
                harness.check("an automatic start is refused while automation is off",
                    Modes.activate("work", "schedule") === false && !Modes.active);
                harness.check("a manual start still works while automation is off",
                    Modes.activate("work", "manual") === true && Modes.active && Modes.activeMode.id === "work");
                Modes.deactivate("manual");
                Config.options.modes.enable = true;
                const routinesBefore = Modes.routines.length;
                const addedId = Modes.addRoutineFromTemplate("break-reminder");
                harness.check("a template becomes a routine", addedId.length > 0 && Modes.routines.length === routinesBefore + 1
                    && Modes.routineById(addedId) !== null);
                Modes.removeRoutine(addedId);
                harness.check("a routine can be removed again", Modes.routines.length === routinesBefore);
                harness.check("the activity log clears", (Modes.clearHistory(), Modes.history.length === 0));
                harness.finish();
                break;
            }
            }
        }
    }
}
