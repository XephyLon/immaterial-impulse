import QtQuick
import QtTest
import "../modules/imi/wallpaperSelector/we_color.js" as WeColor

// A Wallpaper Engine color property is an "r g b" triplet on --set-property.
// The vendored engine's ColorBuilder::parse reads a triplet with a decimal
// point as 0..1 floats and a DOT-LESS triplet as 0..255 integers, so the two
// forms must not be conflated: white written "1 1 1" would be read as
// (1/255, 1/255, 1/255) - near black. parse returns 0..1; format always writes
// the float form with a dot so a round trip stays float.
TestCase {
    name: "WeColorTest"

    function test_format_always_carries_a_dot() {
        // White: every channel is integral, but the output must still read as
        // float 1.0, not the integer 1 that WE would treat as 1/255.
        compare(WeColor.formatChannels([1, 1, 1]), "1.000 1.000 1.000")
        compare(WeColor.formatChannels([1, 0, 0]), "1.000 0.000 0.000")
        compare(WeColor.formatChannels([0.5, 0.25, 0]), "0.500 0.250 0.000")
    }

    function test_format_clamps_out_of_range() {
        compare(WeColor.formatChannels([2, -1, 0.5]), "1.000 0.000 0.500")
    }

    function test_parse_float_triplet_is_read_as_is() {
        compare(WeColor.parseChannel("0.5 0.25 0", 0), 0.5)
        compare(WeColor.parseChannel("0.5 0.25 0", 1), 0.25)
        compare(WeColor.parseChannel("1.0 1.0 1.0", 2), 1)
    }

    function test_parse_dotless_triplet_is_read_as_0_255() {
        // A project default the engine accepts in integer form.
        compare(WeColor.parseChannel("255 128 0", 0), 1)
        compare(WeColor.parseChannel("255 128 0", 1), 128 / 255)
        compare(WeColor.parseChannel("255 128 0", 2), 0)
    }

    function test_parse_guards_garbage_to_zero() {
        // NaN / negative / missing channel -> 0, never a NaN swatch.
        compare(WeColor.parseChannel("", 0), 0)
        compare(WeColor.parseChannel("0.5", 2), 0)
        compare(WeColor.parseChannel("-1.0 0 0", 0), 0)
    }

    function test_round_trip_stays_float() {
        // Formatting then parsing white returns 1, not 1/255 - the round trip
        // our own writes take must not drift toward black.
        var s = WeColor.formatChannels([1, 1, 1])
        compare(WeColor.parseChannel(s, 0), 1)
    }
}
