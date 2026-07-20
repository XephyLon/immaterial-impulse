import QtTest
import "../modules/common/functions/screenSelection.js" as ScreenSelection

TestCase {
    name: "ScreenSelectionTest"

    readonly property var allNames: ["DP-1", "DP-2", "HDMI-A-1"]

    function test_emptyMeansEveryScreen() {
        compare(ScreenSelection.includes([], "DP-1"), true);
        compare(ScreenSelection.includes(["DP-2"], "DP-1"), false);
        compare(ScreenSelection.includes(["DP-1"], "DP-1"), true);
    }

    function test_uncheckingFromAllSelectsTheRest() {
        // [] is "all", so the first unchecked screen has to expand the sentinel
        // into a concrete list of everyone else.
        const result = ScreenSelection.toggle([], allNames, "DP-2", false);
        compare(result.accepted, true);
        compare(result.list, ["DP-1", "HDMI-A-1"]);
    }

    function test_selectingEveryScreenCollapsesBackToTheSentinel() {
        const result = ScreenSelection.toggle(["DP-1", "DP-2"], allNames, "HDMI-A-1", true);
        compare(result.accepted, true);
        // Not ["DP-1","DP-2","HDMI-A-1"] - the config stores "all" as [].
        compare(result.list, []);
    }

    function test_lastScreenCannotBeUnchecked() {
        // The regression: draining the list yields [], which means "every
        // screen", so the bar would switch back on everywhere instead of off.
        const result = ScreenSelection.toggle(["DP-1"], allNames, "DP-1", false);
        compare(result.accepted, false);
        compare(result.list, ["DP-1"]);
    }

    function test_repeatedTogglesAreIdempotent() {
        // The switches are driven by a Binding, so a delegate can be re-fired
        // with the value it already holds; that must not mutate the list.
        const on = ScreenSelection.toggle(["DP-1"], allNames, "DP-1", true);
        compare(on.accepted, true);
        compare(on.list, ["DP-1"]);
        const off = ScreenSelection.toggle(["DP-1", "DP-2"], allNames, "HDMI-A-1", false);
        compare(off.accepted, true);
        compare(off.list, ["DP-1", "DP-2"]);
    }

    function test_doesNotMutateTheCallersList() {
        const original = ["DP-1", "DP-2"];
        ScreenSelection.toggle(original, allNames, "DP-1", false);
        compare(original, ["DP-1", "DP-2"]);
    }

    function test_singleScreenSetupStaysOn() {
        // With one monitor, [] and ["DP-1"] are the same state; unchecking it
        // must still be refused rather than silently re-enabling.
        const result = ScreenSelection.toggle([], ["DP-1"], "DP-1", false);
        compare(result.accepted, false);
    }
}
