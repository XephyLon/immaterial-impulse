.pragma library

// What a recording quality tier costs, in Mbps, on a given screen - the live
// hint under Settings > Capture > Quality. Pure so that tst_record_bitrate.qml
// can drive it; the page only formats what this returns.
//
// gpu-screen-recorder's default bitrate mode is QP (constant quality, so the
// real bitrate follows what is on screen), which is why this is an ESTIMATE:
// a bits-per-pixel-per-frame model, anchored on a real recording rather than
// on a figure someone liked. A 1554x892 region of a busy desktop at 60 fps,
// `very_high`, H.264, measured 8.59 Mbps (2026-08-22) - 0.103 bits per pixel
// per frame - and the anchor is rounded to 0.10. Each tier is one square-root-
// of-two step from the next, because a tier is roughly three QP points and
// bitrate doubles about every six.
var ANCHOR_BITS_PER_PIXEL = 0.10;
var TIER_STEPS = {
    "medium": -2,
    "high": -1,
    "very_high": 0,
    "ultra": 1
};

// Config.qml's default, and what a stored value the shell does not know reads
// as - a hand-edited config must not estimate as zero Mbps.
var DEFAULT_QUALITY = "very_high";

function bitsPerPixel(quality) {
    var step = TIER_STEPS[quality];
    if (step === undefined)
        step = TIER_STEPS[DEFAULT_QUALITY];
    return ANCHOR_BITS_PER_PIXEL * Math.pow(Math.SQRT2, step);
}

// A capture cannot produce more frames than the screen refreshes, so the
// configured rate is capped at the monitor's. hyprctl reports the refresh as
// a float (59.997, 143.85); the hint shows whole frames.
function effectiveFps(fps, refreshRate) {
    if (!(refreshRate > 0))
        return fps;
    return Math.min(fps, Math.round(refreshRate));
}

// Whole Mbps, or 0 when there is no screen to estimate for - the caller hides
// the hint in that case rather than drawing a figure for a made-up screen.
function estimateMbps(width, height, fps, quality) {
    if (!(width > 0) || !(height > 0) || !(fps > 0))
        return 0;
    return Math.round(width * height * fps * bitsPerPixel(quality) / 1000000);
}
