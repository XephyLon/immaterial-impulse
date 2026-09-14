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
        compare(Warp.parse("   \n").state, "unknown");
    }

    function test_unknown_wording_is_unknown_not_connected() {
        const r = Warp.parse("Status update: Connecting\n");
        compare(r.state, "unknown");
        verify(r.available);
    }
}
