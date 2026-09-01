import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.imi.mediaControls

/*
 * The line-level sweep, measured where nothing drifts: LyricsService is
 * seeded with one long line and no word stamps, the interpolated clock is
 * pinned to three positions across the line's span, and the view is
 * photographed at each. The runner measures how far the active colour
 * reaches; a working sweep reaches further at every step.
 */
ShellRoot {
    id: harness

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 520
        implicitHeight: 260
        color: "#101010"

        Lyrics {
            id: view
            anchors.fill: parent
            activeColor: "#00ff00"
            textColor: "#808080"
        }
    }

    property string shotDir: Quickshell.env("LYRICS_SWEEP_SHOTS") || "/tmp"
    property var positions: [10, 50, 90]
    property int step: 0

    function seed() {
        LyricsService.lyricsLines = [
            { time: 0, text: "the sweep crosses this entire long probe line", words: null },
            { time: 100, text: "next line far away", words: null }
        ];
        LyricsService.activeIndex = 0;
        LyricsService.slots = LyricsService.buildSlots(0);
        LyricsService.status = "ok";
    }

    function pin(position) {
        // playing=false path: estimatedPosition answers lastKnownPosition
        // when there is no player, which is exactly the pin we want.
        LyricsService.lastKnownPosition = position;
        LyricsService.lastPositionWall = 0;
    }

    Timer { id: t0; interval: 900; running: true; onTriggered: {
        harness.seed();
        harness.pin(harness.positions[0]);
        stepTimer.start();
    } }
    Timer { id: stepTimer; interval: 700; onTriggered: {
        const pos = harness.positions[harness.step];
        view.grabToImage(result => {
            result.saveToFile(`${harness.shotDir}/sweep_p${pos}.png`);
            harness.step++;
            if (harness.step >= harness.positions.length) {
                console.log("[LyricsSweepProbe] done");
                Qt.quit();
            } else {
                harness.pin(harness.positions[harness.step]);
                stepTimer.start();
            }
        });
    } }
}
