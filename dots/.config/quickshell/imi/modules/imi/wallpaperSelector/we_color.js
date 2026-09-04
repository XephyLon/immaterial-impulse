.pragma library

// Wallpaper Engine color properties on --set-property are "r g b" triplets.
// The vendored engine's ColorBuilder::parse reads the triplet two ways: a
// value with a decimal point anywhere is 0..1 floats; a DOT-LESS triplet is
// 0..255 integers (the form WE also accepts and vendored projects ship). So
// the two must not be conflated - white as the dot-less "1 1 1" is not float
// white, it is (1/255, 1/255, 1/255), near black.
//
// parseChannel returns a 0..1 float for the swatch and the sliders;
// formatChannels always writes the float form WITH a dot, so a value that is
// integral (white = 1.000) is not re-read as 0..255 on the next load.

// One channel of `text` as a 0..1 float. A dot-less triplet is 0..255 and is
// divided down; garbage / negative / a missing channel guards to 0 (never a
// NaN that would poison the swatch - the Math.max(0, NaN) trap).
function parseChannel(text, index) {
    var s = String(text).trim();
    var raw = parseFloat(s.split(/\s+/)[index]);
    if (!(raw >= 0)) return 0;
    // No decimal point anywhere in the triplet: WE reads it as 0..255.
    var v = (s.indexOf(".") === -1) ? raw / 255 : raw;
    return v > 1 ? 1 : v;
}

// 0..1 channels -> the string WE's --set-property takes, each clamped to
// 0..1 and always carrying a decimal point so WE reads it as a float.
function formatChannels(channels) {
    return channels.map(function (c) {
        var v = (c >= 0) ? (c > 1 ? 1 : c) : 0;
        return v.toFixed(3);
    }).join(" ");
}
