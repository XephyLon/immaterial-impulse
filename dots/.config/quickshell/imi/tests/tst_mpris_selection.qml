import QtQuick
import QtTest
import "../services/MprisSelection.js" as MprisSelection

TestCase {
    name: "MprisSelectionTest"

    function test_prefersPlayingPlayerWithMetadata() {
        const stale = { isPlaying: false, trackTitle: "", trackArtist: "" };
        const emptyPlaying = { isPlaying: true, trackTitle: "", trackArtist: "" };
        const video = { isPlaying: true, trackTitle: "Current video", trackArtist: "" };
        compare(MprisSelection.preferredPlayer([stale, emptyPlaying, video]), video);
    }

    function test_prefersPlayingOverPausedMetadata() {
        const paused = { isPlaying: false, trackTitle: "Old video", trackArtist: "Artist" };
        const playing = { isPlaying: true, trackTitle: "", trackArtist: "" };
        compare(MprisSelection.preferredPlayer([paused, playing]), playing);
    }

    function test_fallsBackToMetadataThenFirstPlayer() {
        const empty = { isPlaying: false, trackTitle: "", trackArtist: "" };
        const titled = { isPlaying: false, trackTitle: "Paused video", trackArtist: "" };
        compare(MprisSelection.preferredPlayer([empty, titled]), titled);
        compare(MprisSelection.preferredPlayer([empty]), empty);
        compare(MprisSelection.preferredPlayer([]), null);
    }
}
