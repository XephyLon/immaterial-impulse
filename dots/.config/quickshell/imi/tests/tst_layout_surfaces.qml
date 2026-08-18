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

    function test_an_empty_state_and_missing_names_answer_undefined() {
        compare(Surfaces.rawPosition({}, Surfaces.LOCK, "DP-1", "clock"), undefined);
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.LOCK, "", "clock"), undefined);
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.LOCK, "DP-1", ""), undefined);
        compare(Surfaces.rawPosition(desktopOnly, Surfaces.DESKTOP, "DP-9", "clock"), undefined);
        verify(!Surfaces.isForked(undefined, "DP-1"));
        verify(!Surfaces.isForked({ lockPositions: [] }, "DP-1"));
    }
}
