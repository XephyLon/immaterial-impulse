import QtTest
import "../modules/imi/screensaver/screensaver_screens.js" as Saver

// The set of monitors the screensaver is deliberately holding black. Everything
// that reads it - which overlay maps, and whether services/Idle.qml holds an
// idle inhibitor - is a question about this list, so the list is where the
// arithmetic is checked.
TestCase {
    name: "ScreensaverScreensTest"

    function test_a_named_monitor_goes_in_and_comes_back_out() {
        const one = Saver.withScreen([], "DP-1");
        compare(one, ["DP-1"]);
        verify(Saver.isBlanked(one, "DP-1"));
        verify(!Saver.isBlanked(one, "DP-2"));
        compare(Saver.withoutScreen(one, "DP-1"), []);
    }

    function test_the_other_monitors_are_left_alone() {
        // The whole point of the deliberate path: one panel dark, the rest not.
        const one = Saver.withScreen(["DP-1", "HDMI-A-1"], "DP-2");
        compare(one.length, 3);
        const back = Saver.withoutScreen(one, "DP-2");
        compare(back, ["DP-1", "HDMI-A-1"]);
    }

    function test_showing_a_monitor_twice_does_not_double_it() {
        // Two presses of `showMonitor` must not need two `hideMonitor`s, or the
        // inhibitor stays held after the screen has already come back.
        const twice = Saver.withScreen(Saver.withScreen([], "DP-1"), "DP-1");
        compare(twice, ["DP-1"]);
        compare(Saver.withoutScreen(twice, "DP-1"), []);
    }

    function test_an_empty_name_is_not_a_monitor() {
        // Hyprland.focusedMonitor is null for a moment after a hotplug, and the
        // keybind resolves that to "". Blanking a screen called "" would hold
        // the inhibitor against a surface that can never be dismissed.
        compare(Saver.withScreen([], ""), []);
        compare(Saver.toggledScreen([], ""), []);
        verify(!Saver.isBlanked([""], ""));
    }

    function test_toggle_answers_the_state_it_is_given() {
        compare(Saver.toggledScreen([], "DP-1"), ["DP-1"]);
        compare(Saver.toggledScreen(["DP-1"], "DP-1"), []);
        compare(Saver.toggledScreen(["DP-2"], "DP-1"), ["DP-2", "DP-1"]);
    }

    function test_toggle_all_blanks_everything_or_takes_it_all_down() {
        const all = ["DP-1", "DP-2"];
        compare(Saver.toggledAll([], all, false), all);
        compare(Saver.toggledAll(["DP-1"], all, false), []);
    }

    function test_toggle_all_takes_down_an_idle_raised_saver() {
        // An idle-raised saver is on screen while this list is empty. A toggle
        // that only looked at the list would answer a black screen by blanking
        // every screen again, and the user's key would read as doing nothing.
        compare(Saver.toggledAll([], ["DP-1", "DP-2"], true), []);
    }

    function test_an_unplugged_monitor_stops_holding_the_inhibitor() {
        const blanked = ["DP-1", "DP-2"];
        compare(Saver.pruned(blanked, ["DP-1"]), ["DP-1"]);
        compare(Saver.pruned(blanked, []), []);
        // A monitor still present is not pruned, or every hotplug would clear
        // a deliberate blank on an unrelated screen.
        compare(Saver.pruned(blanked, ["DP-1", "DP-2", "HDMI-A-1"]), blanked);
    }

    function test_none_of_it_mutates_the_list_it_was_given() {
        // These feed a GlobalStates property write. Mutating in place would
        // change the value without raising its changed signal, so the overlays
        // and the inhibitor would both keep reading the old set.
        const original = ["DP-1"];
        Saver.withScreen(original, "DP-2");
        Saver.withoutScreen(original, "DP-1");
        Saver.toggledScreen(original, "DP-1");
        Saver.toggledAll(original, ["DP-1", "DP-2"], false);
        Saver.pruned(original, []);
        compare(original, ["DP-1"]);
    }
}
