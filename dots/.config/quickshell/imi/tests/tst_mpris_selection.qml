import QtQuick
import QtTest
import "../services/MprisSelection.js" as MprisSelection

TestCase {
    name: "MprisSelectionTest"

    function player(busName, isPlaying, trackTitle, identity) {
        return {
            dbusName: `org.mpris.MediaPlayer2.${busName}`,
            identity: identity ?? busName,
            desktopEntry: "",
            isPlaying: isPlaying,
            trackTitle: trackTitle ?? "",
            trackArtist: "",
            trackArtUrl: "",
            position: 0,
            length: 0
        };
    }

    // The bus list measured on the reporting machine in issue #170: music
    // genuinely playing in Chromium, a paused video in Firefox that
    // plasma-browser-integration mirrors, and playerctld republishing that
    // paused video's metadata while reporting Playing under Firefox's identity.
    function liveBusList() {
        return {
            chromium: player("chromium.instance700643", true, "Provider", "Chromium"),
            firefox: player("firefox.instance_1_52", false, "Hasan Piker on Backing Insurgent", "Firefox"),
            plasma: player("plasma-browser-integration", false, "When Hasan Piker Met Mehdi Hasan", "Plasma Browser Integration"),
            proxy: player("playerctld", true, "When Hasan Piker Met Mehdi Hasan", "Mozilla zen")
        };
    }

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

    function test_busNameKeepsOnlyTheHalfThatSurvivesARestart() {
        compare(MprisSelection.playerIdFromBusName("org.mpris.MediaPlayer2.chromium.instance700643"), "chromium");
        compare(MprisSelection.playerIdFromBusName("org.mpris.MediaPlayer2.firefox.instance_1_52"), "firefox");
        compare(MprisSelection.playerIdFromBusName("org.mpris.MediaPlayer2.spotify"), "spotify");
        // A remote phone player is one id per device+player and carries no
        // instance suffix, so nothing may be trimmed off it.
        compare(MprisSelection.playerIdFromBusName("org.mpris.MediaPlayer2.kdeconnect.mpris_device1_vlc"),
            "kdeconnect.mpris_device1_vlc");
    }

    // The bug: playerctld claims Playing over a paused player's metadata under
    // that player's identity, so the "playing with metadata" rule matches it
    // truthfully and Array.find takes whichever came first in the bus list.
    function test_aProxyClaimingPlayingNeverWinsWhateverTheListOrder() {
        const buses = liveBusList();
        const orders = [
            [buses.proxy, buses.chromium, buses.firefox, buses.plasma],
            [buses.chromium, buses.firefox, buses.plasma, buses.proxy],
            [buses.plasma, buses.proxy, buses.chromium, buses.firefox]
        ];
        for (const order of orders) {
            const candidates = MprisSelection.candidatePlayers(order, true);
            verify(!candidates.includes(buses.proxy), "playerctld is not a candidate");
            compare(MprisSelection.selectPlayer(candidates, ""), buses.chromium);
        }
    }

    function test_theProxyIsExcludedEvenWithDuplicateFilteringOff() {
        const buses = liveBusList();
        const candidates = MprisSelection.candidatePlayers(
            [buses.proxy, buses.chromium, buses.firefox, buses.plasma], false);
        verify(!candidates.includes(buses.proxy), "playerctld is never a real player");
        compare(candidates.length, 3);
    }

    // plasma-browser-integration may be the only source for a browser whose own
    // MPRIS is off, and a kdeconnect bus is somebody's phone rather than a
    // local duplicate. Neither is a proxy.
    function test_plasmaIntegrationAndKdeconnectStayCandidates() {
        const plasma = player("plasma-browser-integration", false, "A tab");
        const phone = player("kdeconnect.mpris_device1_vlc", true, "Phone track");
        const candidates = MprisSelection.candidatePlayers([plasma, phone], true);
        verify(candidates.includes(plasma));
        verify(candidates.includes(phone));
    }

    // Suppressing every native browser bus while plasma-browser-integration is
    // up removed the only bus carrying what was actually playing, leaving the
    // paused mirror as the sole candidate.
    function test_duplicateSuppressionNeverDropsThePlayingBus() {
        const buses = liveBusList();
        const candidates = MprisSelection.candidatePlayers(
            [buses.chromium, buses.firefox, buses.plasma], true);
        verify(candidates.includes(buses.chromium), "the playing browser bus survives");
        verify(!candidates.includes(buses.firefox), "the paused browser bus is still a duplicate");
        verify(candidates.includes(buses.plasma));
    }

    function test_normalizingThePreferenceIsIdempotent() {
        const once = MprisSelection.normalizePreferredPlayer("Spotify");
        compare(once, "spotify");
        compare(MprisSelection.normalizePreferredPlayer(once), "spotify");
        compare(MprisSelection.normalizePreferredPlayer(MprisSelection.normalizePreferredPlayer(once)), "spotify");
    }

    function test_normalizingConvertsLegacyAndBusNameValues() {
        compare(MprisSelection.normalizePreferredPlayer(""), "");
        compare(MprisSelection.normalizePreferredPlayer("  "), "");
        compare(MprisSelection.normalizePreferredPlayer(undefined), "");
        compare(MprisSelection.normalizePreferredPlayer("spotify, firefox"), "spotify");
        compare(MprisSelection.normalizePreferredPlayer("org.mpris.MediaPlayer2.chromium.instance700643"), "chromium");
    }

    function test_aPreferenceThatCannotBeParsedStillMatchesThePlayerItNamed() {
        const firefox = player("firefox.instance_1_52", true, "A video", "Mozilla Firefox");
        const stored = MprisSelection.normalizePreferredPlayer("Mozilla Firefox");
        compare(stored, "mozilla");
        compare(MprisSelection.selectPlayer([firefox], stored), firefox);
    }

    function test_thePreferenceWinsOverWhateverElseIsPlaying() {
        const spotify = player("spotify", false, "A paused album");
        const chromium = player("chromium.instance700643", true, "Provider");
        compare(MprisSelection.selectPlayer([chromium, spotify], "spotify"), spotify);
        const shown = MprisSelection.meaningfulPlayers([chromium, spotify], "spotify");
        compare(shown.length, 1);
        compare(shown[0], spotify);
    }

    function test_aPreferredPlayerThatIsNotRunningFallsBackRatherThanShowingNothing() {
        const chromium = player("chromium.instance700643", true, "Provider");
        compare(MprisSelection.selectPlayer([chromium], "spotify"), chromium);
        const shown = MprisSelection.meaningfulPlayers([chromium], "spotify");
        compare(shown.length, 1);
        compare(shown[0], chromium);
        // ...and with nothing running at all it is still a null, not a throw.
        compare(MprisSelection.selectPlayer([], "spotify"), null);
    }

    function test_thePickerKeepsARowForAPreferenceWhosePlayerIsGone() {
        const chromium = player("chromium.instance700643", true, "Provider", "Chromium");
        const options = MprisSelection.playerOptions([chromium], "spotify");
        compare(options.length, 2);
        compare(options[0].value, "chromium");
        compare(options[0].name, "Chromium");
        compare(options[0].trackTitle, "Provider");
        verify(options[0].available);
        compare(options[1].value, "spotify");
        verify(!options[1].available, "the stored choice is still offered, marked absent");
    }

    function test_thePickerOffersOneRowPerPlayerNotPerInstance() {
        const idle = player("chromium.instance1", false, "", "Chromium");
        const playing = player("chromium.instance2", true, "Provider", "Chromium");
        const options = MprisSelection.playerOptions([idle, playing], "");
        compare(options.length, 1);
        compare(options[0].value, "chromium");
        verify(options[0].isPlaying, "the instance with something to say describes the row");
        compare(options[0].trackTitle, "Provider");
    }
}
