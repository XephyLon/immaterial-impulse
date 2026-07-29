import QtQuick
import QtTest
import testservices

// Behavioral tests for the pure logic in services/OpenRgb.qml, driven
// through the logic-only double in tests/imports/testservices/OpenRgb.qml
// (kept in sync by test_openrgb_contract.py).
TestCase {
    name: "OpenRgbTest"

    // Trimmed real `openrgb --list-devices` output: duplicate names (two RAM
    // sticks), a multi-line Location: continuation, and a gamepad.
    readonly property string sampleListing: [
        "0: Corsair Dominator Titanium RGB DDR5",
        "  Type:           DRAM",
        "  Description:    Corsair DRAM RGB Device",
        "  LEDs: 'Corsair DRAM LED 0' 'Corsair DRAM LED 1'",
        "",
        "1: Corsair Dominator Titanium RGB DDR5",
        "  Type:           DRAM",
        "  Description:    Corsair DRAM RGB Device",
        "",
        "2: Gigabyte GeForce RTX 4080 SUPER AERO OC",
        "  Type:           GPU",
        "  Location:       I2C: NVIDIA i2c adapter 1 at 1:00.0",
        " (/dev/i2c-1), address 0x72",
        "",
        "3: Sony DualSense Edge",
        "  Type:           Gamepad",
        "  Serial:         14:3a:9a:7c:45:47"
    ].join("\n")

    function test_parse_device_list() {
        const devices = OpenRgb.parseDeviceList(sampleListing)
        compare(devices.length, 4)
        compare(devices[0].index, 0)
        compare(devices[0].name, "Corsair Dominator Titanium RGB DDR5")
        compare(devices[0].type, "DRAM")
        compare(devices[1].index, 1)
        compare(devices[1].name, "Corsair Dominator Titanium RGB DDR5")
        compare(devices[2].type, "GPU")
        compare(devices[3].index, 3)
        compare(devices[3].name, "Sony DualSense Edge")
        compare(devices[3].type, "Gamepad")
    }

    function test_parse_tolerates_noise_and_empty() {
        compare(OpenRgb.parseDeviceList("").length, 0)
        compare(OpenRgb.parseDeviceList(null).length, 0)
        // Non-header noise (e.g. "Connection attempt failed") is skipped.
        compare(OpenRgb.parseDeviceList("Connection attempt failed\n").length, 0)
        // LED lines like "'LED 1'" must not be mistaken for device headers.
        const devices = OpenRgb.parseDeviceList("0: Foo\n  LEDs: 'LED 1' 'Player 2'\n")
        compare(devices.length, 1)
        compare(devices[0].name, "Foo")
    }

    function test_build_command_skips_excluded_names() {
        const devices = OpenRgb.parseDeviceList(sampleListing)
        const cmd = OpenRgb.buildDeviceCommand("AABBCC", devices, ["Sony DualSense Edge"])
        compare(cmd, [
            "openrgb",
            "--device", "0", "--mode", "static", "--color", "AABBCC",
            "--device", "1", "--mode", "static", "--color", "AABBCC",
            "--device", "2", "--mode", "static", "--color", "AABBCC"
        ])
    }

    function test_build_command_excludes_all_duplicates_of_a_name() {
        const devices = OpenRgb.parseDeviceList(sampleListing)
        const cmd = OpenRgb.buildDeviceCommand("112233", devices,
            ["Corsair Dominator Titanium RGB DDR5"])
        compare(cmd, [
            "openrgb",
            "--device", "2", "--mode", "static", "--color", "112233",
            "--device", "3", "--mode", "static", "--color", "112233"
        ])
    }

    function test_build_command_null_when_nothing_remains() {
        const devices = OpenRgb.parseDeviceList(sampleListing)
        verify(OpenRgb.buildDeviceCommand("FFFFFF", devices, [
            "Corsair Dominator Titanium RGB DDR5",
            "Gigabyte GeForce RTX 4080 SUPER AERO OC",
            "Sony DualSense Edge"
        ]) === null)
        // Empty scan with exclusions set also yields null (skip the apply).
        verify(OpenRgb.buildDeviceCommand("FFFFFF", [], ["Whatever"]) === null)
    }

    function test_build_command_without_exclusions_targets_everything() {
        const devices = OpenRgb.parseDeviceList(sampleListing)
        const cmd = OpenRgb.buildDeviceCommand("010203", devices, [])
        compare(cmd.filter(a => a === "--device").length, 4)
    }

    function test_color_delta_is_summed_channel_difference() {
        compare(OpenRgb.colorDelta("000000", "000000"), 0)
        compare(OpenRgb.colorDelta("FFFFFF", "000000"), 765)
        compare(OpenRgb.colorDelta("102030", "102030"), 0)
        compare(OpenRgb.colorDelta("102030", "112233"), 6)
        compare(OpenRgb.colorDelta("FF0000", "00FF00"), 510)
    }

    function test_color_delta_malformed_is_maximal() {
        compare(OpenRgb.colorDelta("", "000000"), 765)
        compare(OpenRgb.colorDelta("12345", "000000"), 765)
        compare(OpenRgb.colorDelta("GGGGGG", "000000"), 765)
    }

    function test_mix_hex_blends_per_channel() {
        compare(OpenRgb.mixHex("000000", "FFFFFF", 0.5), "808080")
        compare(OpenRgb.mixHex("000000", "FFFFFF", 0), "000000")
        compare(OpenRgb.mixHex("000000", "FFFFFF", 1), "FFFFFF")
        compare(OpenRgb.mixHex("102030", "304050", 0.5), "203040")
    }

    function test_mix_hex_malformed_falls_back_to_the_other_endpoint() {
        compare(OpenRgb.mixHex("nope", "112233", 0.5), "112233")
        compare(OpenRgb.mixHex("112233", "bad", 0.5), "112233")
    }
}
