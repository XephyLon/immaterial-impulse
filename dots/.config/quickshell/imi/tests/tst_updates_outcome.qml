import QtQuick
import QtTest
import "../services/updates_outcome.js" as Outcome

// The upgrade outcome the Updates service reports after a run: the two
// notify-send commands the bar widget used to build, byte for byte.
TestCase {
    name: "UpdatesOutcome"

    function test_up_to_date_carries_no_urgency_flag() {
        verify(Outcome.outcome(0).upToDate);
        compare(Outcome.outcome(0).urgency, "");
        compare(Outcome.command(0, "Updates", "System up to date"),
                ["notify-send", "Updates", "System up to date", "-a", "Shell"]);
    }

    function test_pending_updates_are_a_normal_urgency_cancel_notice() {
        verify(!Outcome.outcome(3).upToDate);
        compare(Outcome.outcome(3).urgency, "normal");
        compare(Outcome.command(3, "Updates", "Update cancelled — 3 updates still pending"),
                ["notify-send", "Updates", "Update cancelled — 3 updates still pending", "-a", "Shell", "-u", "normal"]);
    }
}
