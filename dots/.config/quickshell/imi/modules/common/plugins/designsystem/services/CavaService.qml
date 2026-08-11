pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

// The audio spectrum, and the cava process that produces it.
//
// This singleton used to declare `refCount`, `barCount` and `values` and
// nothing else: no producer, no process, and `values` was never assigned by
// anything in the tree. It read as the obvious API - a shared resource with a
// reference count - so widgets were written against it and rendered nothing,
// silently, while the bands the shell actually drew came from a `Process` that
// lived inside MediaControls and published to GlobalStates. See issue #155.
Singleton {
    id: root

    // The band contract, in one place, because it is not a preference: it is
    // what scripts/cava/raw_output_config.txt asks the process for.
    // `barCount` is that file's `bars`, `maxValue` its ascii output range. A
    // consumer drawing a different number of bars resamples
    // (modules/common/functions/cavaBands.js) rather than declaring its own
    // count and hoping the two stay equal - which is precisely how this file's
    // old `barCount: 32` came to disagree with the 50 bands being produced.
    readonly property int barCount: 50
    readonly property real maxValue: 1000

    // Consumers hold a claim (CavaRef) for exactly as long as they are showing
    // bands. cava decodes audio continuously, so it must not run for an idle
    // desktop; with nothing playing there is nothing to decode either.
    //
    // `isPlaying`, not `activePlayer !== null`: a *paused* player is still an
    // active player, so the old test kept cava decoding for as long as any
    // player existed at all. cava visualises whatever is audible rather than
    // that player's stream, so it then drew some other application's sound -
    // and every band it emitted retriggered twenty `Behavior on height`
    // animations, which tick at the display's refresh rate whether or not
    // anyone can see them. Measured on a 240 Hz output with three paused
    // players and a fullscreen game: the bar's render thread ran at 237 fps
    // behind the game, and pausing cava took it to 33.
    property int refCount: 0
    readonly property bool active: root.refCount > 0 && MprisController.isPlaying

    property list<real> values: []

    Process {
        id: cavaProc
        running: root.active
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        onRunningChanged: {
            if (!cavaProc.running) root.values = [];
        }
        stdout: SplitParser {
            onRead: data => {
                root.values = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }
}
