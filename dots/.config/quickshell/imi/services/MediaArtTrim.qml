pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * The letterbox insets of the active track's album art.
 *
 * Some players hand over art with the bars baked in - a square cover shipped
 * 16:9, a video thumbnail with pillarboxes - and the media widget crop-fills
 * its tiles, so the bars become the picture. scripts/media/art_trim.py is
 * the authority (symmetric near-uniform pairs only, 2%-45% per side, see its
 * docstring); this asks it once per art file and remembers the answer for
 * the session.
 *
 * file:// art only: remote art would need a download this probe does not do,
 * and every local player hands a cached file. A probe is one ~50ms process
 * per TRACK, not per frame - the map is keyed by the art URL the player
 * gave, so revisiting a track costs nothing.
 */
Singleton {
    id: root

    // artUrl -> Qt.rect source clip, or null where the probe proved nothing
    // (full-bleed art, an unreadable file, an asymmetric edge).
    property var clips: ({})

    readonly property string artUrl: MprisController.activePlayer?.trackArtUrl ?? ""
    readonly property string artFile: root.artUrl.startsWith("file://")
        ? decodeURIComponent(root.artUrl.substring(7)) : ""

    // The consumers' one question. Reads `clips`, so a binding through here
    // re-evaluates when a probe answers.
    function clipFor(url) {
        return root.clips[url] ?? null
    }

    onArtFileChanged: root.maybeProbe()

    function maybeProbe(): void {
        if (root.artFile === "" || root.clips[root.artUrl] !== undefined)
            return
        if (probe.running)
            return
        probe.forUrl = root.artUrl
        probe.forFile = root.artFile
        probe.running = true
    }

    Process {
        id: probe
        property string forUrl: ""
        property string forFile: ""
        command: ["python3", `${Directories.scriptPath}/media/art_trim.py`, probe.forFile]
        stdout: StdioCollector {
            id: probeCollector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(probeCollector.text)
                } catch (error) {
                    parsed = null
                }
                const next = Object.assign({}, root.clips)
                if (!parsed || parsed.error !== undefined
                    || !(parsed.width > 0) || !(parsed.height > 0)) {
                    // A failed probe is a remembered "no": retrying an
                    // unreadable file every track change would be a process
                    // in a loop.
                    next[probe.forUrl] = null
                } else {
                    const w = parsed.width - parsed.left - parsed.right
                    const h = parsed.height - parsed.top - parsed.bottom
                    const bars = parsed.left + parsed.right + parsed.top + parsed.bottom
                    next[probe.forUrl] = (bars > 0 && w > 0 && h > 0)
                        ? Qt.rect(parsed.left, parsed.top, w, h) : null
                }
                root.clips = next
                // The track may have moved on while the probe ran.
                root.maybeProbe()
            }
        }
    }
}
