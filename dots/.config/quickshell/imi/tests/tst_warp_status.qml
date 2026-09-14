import QtQuick
import QtTest
import "../modules/common/models/quickToggles/warp_status.js" as Warp

// The WARP toggle's reading of `warp-cli status`, without warp-cli.
TestCase {
    name: "WarpStatus"

    function test_connected_and_disconnected() {
        compare(Warp.parse("Status update: Connected\n").state, "connected");
        compare(Warp.parse("Status update: Disconnected\nReason: Manual Disconnection\n").state, "disconnected");
        verify(Warp.parse("Status update: Connected").available);
    }

    function test_unregistered_wins_over_the_rest() {
        const r = Warp.parse("Unable to connect to the CloudflareWARP daemon. Maybe the daemon is not running?");
        compare(r.state, "unregistered");
        verify(r.available, "the CLI answered, so the toggle is available");
    }

    function test_no_output_means_no_cli() {
        compare(Warp.parse("").available, false);
        compare(Warp.parse(null).available, false);
        // Any output at all is the CLI answering (the toggle's old rule).
        const blank = Warp.parse("   \n");
        verify(blank.available); compare(blank.state, "unknown");
    }

    function test_the_words_do_not_shadow_each_other() {
        // "Disconnected" does not contain "Connected", so the plain order holds.
        compare(Warp.parse("Disconnected").state, "disconnected");
        compare(Warp.parse("Connected").state, "connected");
    }

    function test_unknown_wording_is_unknown_not_connected() {
        const r = Warp.parse("Status update: Connecting\n");
        compare(r.state, "unknown");
        verify(r.available);
    }
}
