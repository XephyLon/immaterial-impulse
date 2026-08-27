import QtTest
import "../modules/common/functions/record_bitrate.js" as RecordBitrate

// The recording quality row's live hint: what a quality tier is expected to
// cost in Mbps on the screen the settings window is on. The hint itself is a
// StyledText in a settings page, which `qmltestrunner` cannot build, so every
// decision behind it lives in record_bitrate.js and is exercised here.
//
// gpu-screen-recorder's default bitrate mode is QP - constant quality, so the
// real bitrate follows the content - and the estimate is a bits-per-pixel
// model anchored on a real recording rather than a promise: a 1554x892 region
// of a busy desktop at 60 fps, `very_high`, H.264, measured at 8.59 Mbps
// (2026-08-22), which is 0.103 bits per pixel per frame.
TestCase {
    name: "RecordBitrateTest"

    // ---------------------------------------------------------------------
    // The anchor, and the ladder around it
    // ---------------------------------------------------------------------

    function test_veryHighIsTheMeasuredAnchor() {
        // 1554 * 892 * 60 * 0.10 / 1e6 = 8.3 -> 8, against 8.59 measured.
        compare(RecordBitrate.estimateMbps(1554, 892, 60, "very_high"), 8);
    }

    // Each tier is one constant ratio from the next, so the four numbers under
    // the segmented row read as a ladder rather than as four unrelated guesses.
    function test_theTiersAreAConstantRatioApart() {
        const medium = RecordBitrate.bitsPerPixel("medium");
        const high = RecordBitrate.bitsPerPixel("high");
        const veryHigh = RecordBitrate.bitsPerPixel("very_high");
        const ultra = RecordBitrate.bitsPerPixel("ultra");
        verify(medium < high && high < veryHigh && veryHigh < ultra, "tiers must climb");
        fuzzyCompare(high / medium, veryHigh / high, 0.001);
        fuzzyCompare(ultra / veryHigh, veryHigh / high, 0.001);
    }

    // The maintainer's own screen, the one the example hint was written for.
    function test_theExampleScreen() {
        compare(RecordBitrate.estimateMbps(5120, 1440, 60, "very_high"), 44);
        compare(RecordBitrate.estimateMbps(5120, 1440, 60, "medium"), 22);
        compare(RecordBitrate.estimateMbps(5120, 1440, 60, "ultra"), 63);
    }

    function test_theEstimateScalesWithPixelsAndFrames() {
        const fullHd = RecordBitrate.estimateMbps(1920, 1080, 60, "high");
        const fourK = RecordBitrate.estimateMbps(3840, 2160, 60, "high");
        const halfRate = RecordBitrate.estimateMbps(1920, 1080, 30, "high");
        verify(Math.abs(fourK - 4 * fullHd) <= 2, "four times the pixels is four times the bits");
        verify(Math.abs(2 * halfRate - fullHd) <= 2, "half the frames is half the bits");
    }

    // Config.qml's default is very_high, and a stored value the shell does not
    // know (a hand-edited config, a future tier) reads as the default rather
    // than as zero Mbps.
    function test_anUnknownQualityEstimatesAsTheDefault() {
        compare(RecordBitrate.bitsPerPixel("weird"), RecordBitrate.bitsPerPixel("very_high"));
        compare(RecordBitrate.bitsPerPixel(undefined), RecordBitrate.bitsPerPixel("very_high"));
    }

    // ---------------------------------------------------------------------
    // The frame rate the screen can actually deliver
    // ---------------------------------------------------------------------

    // A capture cannot produce more frames than the screen refreshes, so a
    // 240 fps setting on a 60 Hz monitor records at 60 - and the hint says so.
    function test_theFrameRateIsCappedByTheRefreshRate() {
        compare(RecordBitrate.effectiveFps(240, 59.997), 60);
        compare(RecordBitrate.effectiveFps(30, 144), 30);
        compare(RecordBitrate.effectiveFps(60, 60), 60);
    }

    // hyprctl reports the rate as a float; the hint shows whole frames.
    function test_aFractionalRefreshRateRoundsToWholeFrames() {
        compare(RecordBitrate.effectiveFps(240, 143.85), 144);
        compare(RecordBitrate.effectiveFps(240, 74.97), 75);
    }

    function test_anUnknownRefreshRateLeavesTheSettingAlone() {
        compare(RecordBitrate.effectiveFps(60, 0), 60);
        compare(RecordBitrate.effectiveFps(60, NaN), 60);
        compare(RecordBitrate.effectiveFps(60, undefined), 60);
    }

    // ---------------------------------------------------------------------
    // No screen, no number
    // ---------------------------------------------------------------------

    // The hint is hidden rather than drawn for a made-up screen; a caller that
    // still asks gets nothing rather than a plausible figure.
    function test_anUnmeasuredScreenEstimatesNothing() {
        compare(RecordBitrate.estimateMbps(0, 1440, 60, "high"), 0);
        compare(RecordBitrate.estimateMbps(5120, 0, 60, "high"), 0);
        compare(RecordBitrate.estimateMbps(NaN, 1440, 60, "high"), 0);
        compare(RecordBitrate.estimateMbps(undefined, undefined, 60, "high"), 0);
        compare(RecordBitrate.estimateMbps(5120, 1440, 0, "high"), 0);
    }
}
