import QtTest
import "../modules/common/plugins/layout_surfaces.js" as Surfaces

// Two widget layouts in one store, and the fork-on-first-edit rule between
// them (spec §4.3 as amended 2026-08-18). Every decision - what the lock reads
// before and after the fork, what a lock write copies, what a desktop write
// leaves alone, what re-linking removes - is pinned here bare, because the
// alternative is a running PluginState with a file behind it.
TestCase {
    name: "LayoutSurfacesTest"

    readonly property var desktopOnly: ({
        desktopPositions: {
            "DP-1": {
                clock: { x: 100, y: 200, placementStrategy: "free" },
                weather: { x: 500, y: 200, placementStrategy: "free" }
            },
            "DP-2": {
                clock: { x: 10, y: 20, placementStrategy: "free" }
            }
        },
        pluginOptions: {
            weather: { __gridSize: "3x2", blurEnabled: true }
        }
    })

    function test_the_lock_store_is_named_and_everything_else_is_the_desktop() {
        compare(Surfaces.storeKey(Surfaces.LOCK), "lockPositions");
        compare(Surfaces.storeKey(Surfaces.DESKTOP), "desktopPositions");
        compare(Surfaces.storeKey(undefined), "desktopPositions");
        compare(Surfaces.storeKey("anything"), "desktopPositions");
    }

    function test_an_unforked_screen_reads_the_desktop_on_both_surfaces() {
        verify(!Surfaces.isForked(desktopOnly, "DP-1"));
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.DESKTOP, "DP-1", "clock").x, 100);
        // The inheritance: the lock shows the desktop's layout.
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.LOCK, "DP-1", "clock").x, 100);
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.LOCK, "DP-1", "weather").x, 500);
    }

    function test_the_first_lock_write_forks_the_whole_screen() {
        const next = Surfaces.withPosition(desktopOnly, Surfaces.LOCK, "DP-1", "clock",
            { x: 900, y: 900, placementStrategy: "free" });
        verify(Surfaces.isForked(next, "DP-1"));
        // The moved widget follows the lock store...
        compare(Surfaces.rawPosition(next, Surfaces.LOCK, "DP-1", "clock").x, 900);
        // ...and so does every OTHER widget on that screen, at the position it
        // had - the fork is a snapshot, not a one-widget overlay.
        compare(Surfaces.rawPosition(next, Surfaces.LOCK, "DP-1", "weather").x, 500);
        // The desktop is untouched.
        compare(Surfaces.rawPosition(next, Surfaces.DESKTOP, "DP-1", "clock").x, 100);
        // The other screen is untouched and unforked.
        verify(!Surfaces.isForked(next, "DP-2"));
        compare(Surfaces.rawPosition(next, Surfaces.LOCK, "DP-2", "clock").x, 10);
    }

    function test_after_the_fork_the_two_surfaces_are_independent() {
        let state = Surfaces.withPosition(desktopOnly, Surfaces.LOCK, "DP-1", "clock",
            { x: 900, y: 900, placementStrategy: "free" });
        // A desktop move afterwards does not reach the lock.
        state = Surfaces.withPosition(state, Surfaces.DESKTOP, "DP-1", "clock",
            { x: 1, y: 1, placementStrategy: "free" });
        compare(Surfaces.rawPosition(state, Surfaces.DESKTOP, "DP-1", "clock").x, 1);
        compare(Surfaces.rawPosition(state, Surfaces.LOCK, "DP-1", "clock").x, 900);
        // A widget added to the desktop after the fork is absent from the
        // lock rather than leaking in at the desktop's position.
        state = Surfaces.withPosition(state, Surfaces.DESKTOP, "DP-1", "media",
            { x: 50, y: 50, placementStrategy: "free" });
        compare(Surfaces.rawPosition(state, Surfaces.DESKTOP, "DP-1", "media").x, 50);
        compare(Surfaces.rawPosition(state, Surfaces.LOCK, "DP-1", "media"), undefined);
    }

    function test_relinking_removes_the_screen_and_reads_through_again() {
        let state = Surfaces.withPosition(desktopOnly, Surfaces.LOCK, "DP-1", "clock",
            { x: 900, y: 900, placementStrategy: "free" });
        state = Surfaces.withPosition(state, Surfaces.LOCK, "DP-2", "clock",
            { x: 700, y: 700, placementStrategy: "free" });
        const relinked = Surfaces.withoutLockLayout(state, "DP-1");
        verify(!Surfaces.isForked(relinked, "DP-1"));
        compare(Surfaces.rawPosition(relinked, Surfaces.LOCK, "DP-1", "clock").x, 100);
        // The other screen's fork survives.
        verify(Surfaces.isForked(relinked, "DP-2"));
        compare(Surfaces.rawPosition(relinked, Surfaces.LOCK, "DP-2", "clock").x, 700);
    }

    function test_relinking_an_unforked_screen_is_a_no_op_by_identity() {
        const same = Surfaces.withoutLockLayout(desktopOnly, "DP-1");
        verify(same === desktopOnly);
    }

    function test_writes_never_mutate_the_state_they_were_given() {
        const before = JSON.stringify(desktopOnly);
        Surfaces.withPosition(desktopOnly, Surfaces.LOCK, "DP-1", "clock",
            { x: 900, y: 900, placementStrategy: "free" });
        Surfaces.withPosition(desktopOnly, Surfaces.DESKTOP, "DP-1", "clock",
            { x: 1, y: 1, placementStrategy: "free" });
        compare(JSON.stringify(desktopOnly), before);
    }

    // ---- the span forks with the position ------------------------------

    function test_the_span_inherits_the_desktop_option_until_forked() {
        compare(Surfaces.rawGridSize(desktopOnly, Surfaces.DESKTOP, "DP-1", "weather"), "3x2");
        compare(Surfaces.rawGridSize(desktopOnly, Surfaces.LOCK, "DP-1", "weather"), "3x2");
        compare(Surfaces.rawGridSize(desktopOnly, Surfaces.LOCK, "DP-1", "clock"), undefined);
    }

    function test_the_fork_snapshot_carries_each_widgets_span() {
        const next = Surfaces.withPosition(desktopOnly, Surfaces.LOCK, "DP-1", "clock",
            { x: 900, y: 900, placementStrategy: "free" });
        // The forked record for weather carries the span it had.
        compare(next.lockPositions["DP-1"].weather.gridSize, "3x2");
        compare(Surfaces.rawGridSize(next, Surfaces.LOCK, "DP-1", "weather"), "3x2");
        // A desktop resize afterwards does not reach the lock...
        const resized = Surfaces.withGridSize(next, Surfaces.DESKTOP, "DP-1", "weather", "1x2");
        compare(Surfaces.rawGridSize(resized, Surfaces.DESKTOP, "DP-1", "weather"), "1x2");
        compare(Surfaces.rawGridSize(resized, Surfaces.LOCK, "DP-1", "weather"), "3x2");
        // ...and a lock resize does not reach the desktop - the report.
        const lockResized = Surfaces.withGridSize(resized, Surfaces.LOCK, "DP-1", "weather", "2x2");
        compare(Surfaces.rawGridSize(lockResized, Surfaces.LOCK, "DP-1", "weather"), "2x2");
        compare(Surfaces.rawGridSize(lockResized, Surfaces.DESKTOP, "DP-1", "weather"), "1x2");
        compare(lockResized.pluginOptions.weather.__gridSize, "1x2");
    }

    function test_a_lock_resize_on_an_unforked_screen_forks_it() {
        const next = Surfaces.withGridSize(desktopOnly, Surfaces.LOCK, "DP-1", "weather", "1x2");
        verify(Surfaces.isForked(next, "DP-1"));
        compare(Surfaces.rawGridSize(next, Surfaces.LOCK, "DP-1", "weather"), "1x2");
        // The fork snapshot still copied everything else on the screen.
        compare(Surfaces.rawPosition(next, Surfaces.LOCK, "DP-1", "clock").x, 100);
        // The desktop's span is what it was.
        compare(Surfaces.rawGridSize(next, Surfaces.DESKTOP, "DP-1", "weather"), "3x2");
    }

    function test_a_lock_move_keeps_the_records_span() {
        let state = Surfaces.withGridSize(desktopOnly, Surfaces.LOCK, "DP-1", "weather", "1x2");
        state = Surfaces.withPosition(state, Surfaces.LOCK, "DP-1", "weather",
            { x: 5, y: 5, placementStrategy: "free" });
        compare(Surfaces.rawPosition(state, Surfaces.LOCK, "DP-1", "weather").x, 5);
        compare(Surfaces.rawGridSize(state, Surfaces.LOCK, "DP-1", "weather"), "1x2");
    }

    function test_a_forked_record_without_a_span_reads_through_to_the_desktop() {
        // A fork made by an older shell, or a preset from one: records carry
        // no gridSize. The lock still inherits rather than dropping to the
        // manifest default.
        const older = {
            desktopPositions: desktopOnly.desktopPositions,
            lockPositions: { "DP-1": { weather: { x: 1, y: 1, placementStrategy: "free" } } },
            pluginOptions: desktopOnly.pluginOptions
        };
        compare(Surfaces.rawGridSize(older, Surfaces.LOCK, "DP-1", "weather"), "3x2");
    }

    function test_null_removes_a_span_on_either_surface() {
        let state = Surfaces.withGridSize(desktopOnly, Surfaces.LOCK, "DP-1", "weather", "1x2");
        state = Surfaces.withGridSize(state, Surfaces.LOCK, "DP-1", "weather", null);
        // Removed from the lock record -> reads through to the desktop's 3x2.
        compare(Surfaces.rawGridSize(state, Surfaces.LOCK, "DP-1", "weather"), "3x2");
        state = Surfaces.withGridSize(state, Surfaces.DESKTOP, "DP-1", "weather", null);
        compare(Surfaces.rawGridSize(state, Surfaces.DESKTOP, "DP-1", "weather"), undefined);
        verify(!("__gridSize" in state.pluginOptions.weather));
        // The other option on the plugin survives.
        compare(state.pluginOptions.weather.blurEnabled, true);
    }

    // ---- presence forks the same way -----------------------------------

    readonly property var desktopEnabled: ["clock", "weather", "media"]

    function test_presence_inherits_the_desktop_until_something_is_picked() {
        verify(!Surfaces.isPresenceForked(desktopOnly));
        verify(Surfaces.lockPresent(desktopOnly, desktopEnabled, "clock"));
        verify(Surfaces.lockPresent(desktopOnly, desktopEnabled, "media"));
        // A widget the desktop does not show is not on the lock either, while
        // the two are linked.
        verify(!Surfaces.lockPresent(desktopOnly, desktopEnabled, "notes"));
    }

    function test_the_first_pick_forks_and_keeps_everything_else() {
        const next = Surfaces.withLockPresence(desktopOnly, desktopEnabled, "media", false);
        verify(Surfaces.isPresenceForked(next));
        // The picked widget is off the lock...
        verify(!Surfaces.lockPresent(next, desktopEnabled, "media"));
        // ...and every other widget came along at the desktop's answer, so the
        // fork is a snapshot rather than an empty lock screen.
        verify(Surfaces.lockPresent(next, desktopEnabled, "clock"));
        verify(Surfaces.lockPresent(next, desktopEnabled, "weather"));
    }

    function test_after_the_fork_the_two_sets_are_independent_both_ways() {
        let state = Surfaces.withLockPresence(desktopOnly, desktopEnabled, "media", false);
        // A widget enabled on the desktop afterwards does not appear on the
        // lock - the lock's set is its own now.
        const grownDesktop = ["clock", "weather", "media", "notes"];
        verify(!Surfaces.lockPresent(state, grownDesktop, "notes"));
        // And the other direction, which one shared list cannot express: a
        // widget the desktop does not show, picked for the lock alone.
        state = Surfaces.withLockPresence(state, grownDesktop, "calendar", true);
        verify(Surfaces.lockPresent(state, grownDesktop, "calendar"));
        verify(!Surfaces.containsId(grownDesktop, "calendar"));
    }

    function test_an_empty_forked_map_is_a_lock_screen_with_no_widgets() {
        // Not the same state as "following", which is what makes absence
        // spelled null rather than {}.
        let state = Surfaces.withLockPresence(desktopOnly, [], "clock", true);
        state = Surfaces.withLockPresence(state, [], "clock", false);
        verify(Surfaces.isPresenceForked(state));
        verify(!Surfaces.lockPresent(state, desktopEnabled, "clock"));
    }

    function test_relinking_presence_reads_the_desktop_through_again() {
        const state = Surfaces.withLockPresence(desktopOnly, desktopEnabled, "media", false);
        const relinked = Surfaces.withoutLockPresence(state);
        verify(!Surfaces.isPresenceForked(relinked));
        verify(Surfaces.lockPresent(relinked, desktopEnabled, "media"));
    }

    function test_relinking_an_unpicked_store_is_a_no_op_by_identity() {
        verify(Surfaces.withoutLockPresence(desktopOnly) === desktopOnly);
    }

    function test_presence_writes_never_mutate_the_state_they_were_given() {
        const before = JSON.stringify(desktopOnly);
        Surfaces.withLockPresence(desktopOnly, desktopEnabled, "media", false);
        Surfaces.withoutLockPresence(desktopOnly);
        compare(JSON.stringify(desktopOnly), before);
    }

    function test_presence_and_layout_fork_apart_from_each_other() {
        // Two questions, two stores: picking a widget off the lock must not
        // fork the layout, and moving one must not fork the choice.
        const picked = Surfaces.withLockPresence(desktopOnly, desktopEnabled, "media", false);
        verify(!Surfaces.isForked(picked, "DP-1"));
        const moved = Surfaces.withPosition(desktopOnly, Surfaces.LOCK, "DP-1", "clock",
            { x: 900, y: 900, placementStrategy: "free" });
        verify(!Surfaces.isPresenceForked(moved));
    }

    function test_a_presence_map_is_told_apart_from_a_list() {
        // A `list<string>` that crossed a QML boundary answers `typeof
        // "object"` and fails `Array.isArray` (109e6d897), so the shape check
        // is the length rather than the brand - a stored list must not read
        // as a forked map.
        verify(!Surfaces.isPresenceForked({ lockPresence: [] }));
        verify(!Surfaces.isPresenceForked({ lockPresence: ["clock"] }));
        verify(!Surfaces.isPresenceForked({ lockPresence: null }));
        verify(!Surfaces.isPresenceForked({}));
        verify(Surfaces.isPresenceForked({ lockPresence: {} }));
    }

    function test_membership_does_not_rely_on_array_methods() {
        // The desktop's set arrives as a QML list; index and length are all
        // this may assume of it.
        const sequenceLike = { length: 2, 0: "clock", 1: "weather" };
        verify(Surfaces.containsId(sequenceLike, "weather"));
        verify(!Surfaces.containsId(sequenceLike, "media"));
        verify(!Surfaces.containsId(undefined, "clock"));
        verify(Surfaces.lockPresent({}, sequenceLike, "clock"));
        verify(!Surfaces.lockPresent({}, sequenceLike, ""));
    }

    function test_an_empty_state_and_missing_names_answer_undefined() {
        compare(Surfaces.rawPosition({}, Surfaces.LOCK, "DP-1", "clock"), undefined);
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.LOCK, "", "clock"), undefined);
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.LOCK, "DP-1", ""), undefined);
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.DESKTOP, "DP-9", "clock"), undefined);
        verify(!Surfaces.isForked(undefined, "DP-1"));
        verify(!Surfaces.isForked({ lockPositions: [] }, "DP-1"));
    }

    // ---- options, forked per KEY -------------------------------------------

    readonly property var optionsState: ({
        pluginOptions: { monitor: { vertical: false, blurEnabled: true, positionLocked: true } },
        lockOptions: { monitor: { vertical: true } }
    })

    function test_a_lock_option_reads_its_own_key_and_inherits_the_rest() {
        compare(Surfaces.rawOption(optionsState, Surfaces.LOCK, "monitor", "vertical"), true);
        compare(Surfaces.rawOption(optionsState, Surfaces.LOCK, "monitor", "blurEnabled"), true);
        compare(Surfaces.rawOption(optionsState, Surfaces.DESKTOP, "monitor", "vertical"), false);
        compare(Surfaces.rawOption(optionsState, Surfaces.LOCK, "monitor", "missing"), undefined);
        compare(Surfaces.rawOption(optionsState, Surfaces.LOCK, "other", "vertical"), undefined);
        compare(Surfaces.rawOption({}, Surfaces.LOCK, "monitor", "vertical"), undefined);
        compare(Surfaces.rawOption(optionsState, Surfaces.LOCK, "", "vertical"), undefined);
    }

    function test_a_shared_key_never_forks() {
        verify(Surfaces.isSharedOptionKey("positionLocked"));
        verify(Surfaces.isSharedOptionKey("clickThrough"));
        verify(Surfaces.isSharedOptionKey("__gridSize"));
        verify(!Surfaces.isSharedOptionKey("vertical"));
        verify(!Surfaces.isSharedOptionKey("blurEnabled"));
        const pinned = Surfaces.withOption(optionsState, Surfaces.LOCK, "monitor", "positionLocked", false);
        compare(pinned.pluginOptions.monitor.positionLocked, false);
        compare(pinned.lockOptions.monitor.positionLocked, undefined);
        // A lock map that somehow carries one (an older file, a hand edit)
        // is ignored: the desktop's answer is the only answer.
        const stray = { pluginOptions: { m: { positionLocked: true } }, lockOptions: { m: { positionLocked: false } } };
        compare(Surfaces.rawOption(stray, Surfaces.LOCK, "m", "positionLocked"), true);
    }

    function test_a_lock_write_lands_in_the_overlay_and_leaves_the_desktop_alone() {
        const next = Surfaces.withOption(optionsState, Surfaces.LOCK, "monitor", "blurEnabled", false);
        compare(next.lockOptions.monitor.blurEnabled, false);
        compare(next.pluginOptions.monitor.blurEnabled, true);
        compare(next.lockOptions.monitor.vertical, true);
        verify(next !== optionsState);
        compare(optionsState.lockOptions.monitor.blurEnabled, undefined);
        const desktop = Surfaces.withOption(optionsState, Surfaces.DESKTOP, "monitor", "blurEnabled", false);
        compare(desktop.pluginOptions.monitor.blurEnabled, false);
        compare(desktop.lockOptions.monitor.blurEnabled, undefined);
        const fresh = Surfaces.withOption({}, Surfaces.LOCK, "clock", "style", "pixel");
        compare(fresh.lockOptions.clock.style, "pixel");
        compare(fresh.pluginOptions, undefined);
    }

    function test_null_re_inherits_on_the_lock_and_removes_on_the_desktop() {
        const re = Surfaces.withOption(optionsState, Surfaces.LOCK, "monitor", "vertical", null);
        compare(Surfaces.rawOption(re, Surfaces.LOCK, "monitor", "vertical"), false);
        verify(!Surfaces.isOptionsForked(re, "monitor"));
        const gone = Surfaces.withOption(optionsState, Surfaces.DESKTOP, "monitor", "vertical", null);
        compare(gone.pluginOptions.monitor.vertical, undefined);
        compare(Surfaces.rawOption(gone, Surfaces.LOCK, "monitor", "vertical"), true);
    }

    function test_forked_options_are_answered_and_reset_per_plugin() {
        verify(Surfaces.isOptionsForked(optionsState, "monitor"));
        verify(!Surfaces.isOptionsForked(optionsState, "other"));
        verify(!Surfaces.isOptionsForked({ lockOptions: { m: {} } }, "m"));
        verify(!Surfaces.isOptionsForked({ lockOptions: ["m"] }, "m"));
        verify(!Surfaces.isOptionsForked(undefined, "m"));
        const reset = Surfaces.withoutLockOptions(optionsState, "monitor");
        compare(Surfaces.rawOption(reset, Surfaces.LOCK, "monitor", "vertical"), false);
        compare(reset.pluginOptions.monitor.vertical, false);
        compare(optionsState.lockOptions.monitor.vertical, true);
        verify(Surfaces.withoutLockOptions(optionsState, "other") === optionsState);
        const empty = {};
        verify(Surfaces.withoutLockOptions(empty, "monitor") === empty);
    }
}
