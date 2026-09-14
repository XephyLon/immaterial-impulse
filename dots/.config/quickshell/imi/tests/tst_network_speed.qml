import QtQuick
import QtTest
import "../modules/imi/bar/network_speed.js" as Net

// The network-speed widget's logic, testable without the bar: the
// /proc/net/dev parser, the sample-to-rate state machine, the rate label.
TestCase {
    name: "NetworkSpeed"

    readonly property string procNetDev:
        "Inter-|   Receive                                                |  Transmit\n" +
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n" +
        "    lo: 1000000  100    0    0    0     0          0         0  1000000  100    0    0    0     0       0          0\n" +
        "  wlan0: 5000  40    0    0    0     0          0         0  2000  30    0    0    0     0       0          0\n" +
        "  eth0: 3000  20    0    0    0     0          0         0  1000  10    0    0    0     0       0          0\n" +
        "  bogus: not numbers here\n"

    function test_parser_sums_every_interface_but_loopback() {
        const t = Net.parseProcNetDev(procNetDev);
        compare(t.rx, 8000);
        compare(t.tx, 3000);
        compare(Net.parseProcNetDev("").rx, 0);
        compare(Net.parseProcNetDev(null).tx, 0);
    }

    function test_first_sample_is_a_baseline_and_the_second_a_rate() {
        let s = Net.initialState();
        s = Net.advance(s, 8000, 3000, 1000);
        compare(s.downloadBytesPerSecond, 0);
        compare(s.downloadedBytes, 0);
        s = Net.advance(s, 8000 + 2048, 3000 + 512, 3000);   // 2 s later
        compare(s.downloadBytesPerSecond, 1024);
        compare(s.uploadBytesPerSecond, 256);
        compare(s.downloadedBytes, 2048);
        compare(s.uploadedBytes, 512);
    }

    function test_a_counter_reset_is_no_traffic_not_a_negative_burst() {
        let s = Net.initialState();
        s = Net.advance(s, 8000, 3000, 1000);
        s = Net.advance(s, 100, 50, 2000);
        compare(s.downloadBytesPerSecond, 0);
        compare(s.uploadBytesPerSecond, 0);
        compare(s.downloadedBytes, 0);
        // and the baseline moved to the new counters
        s = Net.advance(s, 1124, 50, 3000);
        compare(s.downloadBytesPerSecond, 1024);
    }

    function test_same_timestamp_changes_nothing() {
        let s = Net.initialState();
        s = Net.advance(s, 8000, 3000, 1000);
        const again = Net.advance(s, 9000, 3000, 1000);
        compare(again.downloadBytesPerSecond, 0);
        compare(again.downloadedBytes, 0);
    }

    function test_rate_labels() {
        compare(Net.formatRate(0, false), "0 B/s");
        compare(Net.formatRate(512, false), "512 B/s");
        compare(Net.formatRate(1536, false), "1.5 KB/s");
        compare(Net.formatRate(1536, true), "1.5K");
        compare(Net.formatRate(150 * 1024, false), "150 KB/s");
        compare(Net.formatRate(3.2 * 1024 * 1024 * 1024, true), "3.2G");
        compare(Net.formatRate(-5, false), "0 B/s");
        compare(Net.formatRate("nope", true), "0B");
    }
}
