pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "sound_theme.js" as SoundThemeLogic

/**
 * The shell's sound events: an event name in, one XDG-resolved file played out.
 *
 * The split is deliberate and is the whole reason this is testable at all.
 * `scripts/sounds/scan-sound-themes.py` reports what is on disk and decides
 * nothing; `sound_theme.js` decides everything and touches no disk; this
 * singleton owns the process lifetimes that neither of them can.
 *
 * Playback is a spawned `pw-play`, not an in-process QtMultimedia player, and
 * that was measured rather than assumed. Importing QtMultimedia and playing one
 * 223ms chime takes a bare QtQuick process from 65 MiB / 133 mapped shared
 * objects to 113 MiB / 238 - permanently, for the life of the shell, whether or
 * not the user ever enables a sound - and its ffmpeg backend prints a three-line
 * decode banner to stderr per play, straight into the `log.log` that every
 * debugging session here greps. A spawn costs 6ms of CPU, is freed on exit, and
 * is a command list a test can read.
 */
Singleton {
    id: root

    property var catalogue: SoundThemeLogic.buildCatalogue(null)
    property bool ready: false

    readonly property var themes: SoundThemeLogic.selectableThemes(root.catalogue)
    readonly property string activeTheme: Config.options.sounds.theme

    // A singleton is constructed on first use, and the only thing that reaches
    // this one is a `play()` call - so the scan has not even started when the
    // first sound is asked for, and dropping it would silently lose whichever
    // event happens to come first after a login. Held rather than dropped, and
    // bounded rather than unbounded: the scan answers in ~20ms, so anything
    // still arriving after four events has a problem a queue cannot fix.
    property var pendingEvents: []
    readonly property int maxPendingEvents: 4

    function play(eventName) {
        if (!SoundThemeLogic.isPlayableEventName(eventName))
            return;
        if (!root.ready) {
            if (root.pendingEvents.length < root.maxPendingEvents)
                root.pendingEvents = root.pendingEvents.concat([eventName]);
            return;
        }
        const path = SoundThemeLogic.resolveEvent(root.catalogue, root.activeTheme, eventName);
        if (path.length === 0)
            return;
        Quickshell.execDetached(["pw-play", path]);
    }

    function rescan() {
        if (!scanProcess.running)
            scanProcess.running = true;
    }

    Process {
        id: scanProcess
        running: true
        command: ["python3", Directories.soundThemeScanScriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.catalogue = SoundThemeLogic.buildCatalogue(JSON.parse(text));
                } catch (error) {
                    // No themes this session means silence, not a broken shell:
                    // resolveEvent answers "" for every event against an empty
                    // catalogue and play() drops it.
                    console.warn("[SoundTheme] could not parse the theme scan:", error);
                    root.catalogue = SoundThemeLogic.buildCatalogue(null);
                }
            }
        }
        // Flushed on exit rather than on a successful parse, so a scan that
        // fails outright still clears the queue instead of holding events for
        // the rest of the session.
        onExited: {
            root.ready = true;
            const held = root.pendingEvents;
            root.pendingEvents = [];
            for (let i = 0; i < held.length; i++)
                root.play(held[i]);
        }
    }
}
