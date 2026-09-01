pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // The player the lyrics follow. The sidebar view hands its own in: its
    // dropdown can select a player other than the global active one, and
    // lyrics fetched for the wrong player are wrong lyrics with perfect
    // confidence.
    property MprisPlayer overridePlayer: null
    readonly property MprisPlayer activePlayer: root.overridePlayer ?? MprisController.activePlayer
    onActivePlayerChanged: root.restartLyrics()

    property var lyricsLines: []
    property int activeIndex: -1
    property string status: "idle"
    property var slots: []
    property bool desktopWidgetLyricsActive: false
    // The media sidebar's lyrics view, as a refcount: the desktop widget's
    // flag only ever had one writer, and the sidebar view silently never
    // armed the service - its spinner span forever over an idle fetcher.
    property int sidebarLyricsRefs: 0
    readonly property bool lyricsWanted: root.desktopWidgetLyricsActive || root.sidebarLyricsRefs > 0

    // The word-sweep clock: MPRIS position only moves when the player
    // answers a poll, so the sweep interpolates from the last answer while
    // playing. Consumers poll estimatedPosition() on their own cadence.
    property real lastKnownPosition: 0
    property double lastPositionWall: 0
    readonly property bool playing: root.activePlayer?.playbackState === MprisPlaybackState.Playing
    Connections {
        target: root.activePlayer
        function onPositionChanged() {
            root.lastKnownPosition = root.activePlayer.position
            root.lastPositionWall = Date.now()
        }
    }
    function estimatedPosition() {
        // Unanchored (no position signal yet): extrapolating from wall zero
        // computes hours and lights every word at once.
        if (!root.playing || root.lastPositionWall === 0)
            return root.activePlayer?.position ?? root.lastKnownPosition
        return root.lastKnownPosition + (Date.now() - root.lastPositionWall) / 1000
    }

    // Instrumental gaps become their own lines: where the space between one
    // line's sung end and the next line's start exceeds the threshold, a
    // filler entry (the view draws it as a breathing note) fills it - the
    // intro before the first line included. The sung end is the last word's
    // own end when the source carried word timing; a line-level source gets
    // a fixed allowance, so a merely slow line does not sprout notes.
    readonly property real fillerGapSeconds: 5
    function sungEnd(line) {
        if (root.looksLikeWords(line.words)) {
            const last = line.words[line.words.length - 1]
            if (last.length > 2 && isFinite(Number(last[2])))
                return Number(last[0]) + Number(last[2])
            return Number(last[0])
        }
        return line.time + root.fillerGapSeconds
    }
    function withFillers(lines) {
        // Fillers only where the source has per-word timing: a line-level
        // source has no trustworthy sung-end, so a gap it reports is a guess,
        // and a guessed instrumental break is worse than none.
        if (!lines.some(l => root.looksLikeWords(l.words)))
            return lines
        const out = []
        if (lines.length > 0 && lines[0].time > root.fillerGapSeconds)
            out.push({ time: 0, text: "", words: null, filler: true })
        for (let i = 0; i < lines.length; i++) {
            out.push(lines[i])
            if (i + 1 < lines.length) {
                const end = root.sungEnd(lines[i])
                if (lines[i + 1].time - end > root.fillerGapSeconds)
                    out.push({ time: end, text: "", words: null, filler: true })
            }
        }
        return out
    }

    function looksLikeWords(value) {
        return value !== null && value !== undefined
            && typeof value.length === "number" && value.length > 0
    }

    // The active line's words with absolute times - the provider's OWN
    // stamps only. A source without word timing gets no synthesized fake:
    // line-level data is styled fittingly (the view's glyph-masked sweep
    // across the line's span) instead of pretending to know each word.
    readonly property var activeWordTimeline: {
        if (root.activeIndex < 0 || root.activeIndex >= root.lyricsLines.length)
            return []
        return root.wordTimeline(root.lyricsLines[root.activeIndex])
    }

    // Any line's words as a timeline - the view builds one per delegate,
    // because a line's tail can still be singing after the NEXT line went
    // active (cross-line overlap: Provider's "Want" under the following
    // line's "And"), and a single active-line timeline cannot say so.
    function wordTimeline(line) {
        if (!line || !root.looksLikeWords(line.words))
            return []
        return line.words.map(word => ({
            time: Number(word[0]),
            text: String(word[1]),
            // The sung window's end (start + duration) when the source
            // carried it - the glow completes there and rests, instead of
            // stretching across the silence to the next word.
            end: word.length > 2 && isFinite(Number(word[2]))
                ? Number(word[0]) + Number(word[2]) : undefined,
            syllables: word.length > 3 && root.looksLikeWords(word[3])
                ? word[3].map(syl => ({ time: Number(syl[0]), text: String(syl[1]) }))
                : undefined,
        }))
    }

    // The active line's span, pacing that sweep.
    readonly property var activeLineSpan: {
        if (root.activeIndex < 0 || root.activeIndex >= root.lyricsLines.length)
            return null
        const start = root.lyricsLines[root.activeIndex].time
        const next = root.activeIndex + 1 < root.lyricsLines.length
            ? root.lyricsLines[root.activeIndex + 1].time : start + 8
        return { start: start, end: Math.max(next, start + 0.5) }
    }

    readonly property real lineAnticipation: 0.5
    // The active line's romanization/translation, and whether ANY line has
    // them (so the view shows the toggles only when there is something to
    // toggle). Line-level extras, not word-timed.
    function lineRomanized(index) {
        return (index >= 0 && index < root.lyricsLines.length)
            ? (root.lyricsLines[index].romanized ?? "") : ""
    }
    function lineTranslated(index) {
        return (index >= 0 && index < root.lyricsLines.length)
            ? (root.lyricsLines[index].translated ?? "") : ""
    }
    readonly property bool hasRomanization: root.lyricsLines.some(l => (l.romanized ?? "").length > 0)
    readonly property bool hasTranslation: root.lyricsLines.some(l => (l.translated ?? "").length > 0)

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            let lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    Timer {
        id: syncTimer
        // The interpolated clock, not the raw position: MPRIS position only
        // moves when the player answers the sidebar's 3s poke, and a line
        // index read off it flips up to a whole poke late - the shell sat a
        // line behind GlassyMusic's own karaoke at every transition.
        interval: 150
        repeat: true
        running: root.status === "ok" && root.lyricsLines.length > 0
        onTriggered: {
            // The line flips half a second EARLY, on the maintainer's call:
            // the reader wants the next line settled before it is sung. Only
            // the index anticipates - the word clock stays true, so an
            // early-arrived line simply waits unsung until its words come.
            const pos = root.estimatedPosition() + root.lineAnticipation
            let idx = -1
            for (let i = 0; i < root.lyricsLines.length; i++) {
                if (root.lyricsLines[i].time <= pos) idx = i
                else break
            }
            if (idx !== root.activeIndex) {
                root.activeIndex = idx
                root.slots = root.buildSlots(idx)
            }
        }
    }

    Process {
        id: lyricsProc
        running: false
        // A fetch that dies without printing - a network failure, a python
        // stack trace - used to strand the view on "loading" forever.
        onExited: (exitCode, exitStatus) => {
            if (root.status === "loading")
                root.status = "not_found"
        }
        stderr: SplitParser {
            onRead: line => console.warn("[Lyrics]", line)
        }
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed === "not_found") { root.status = "not_found"; return }
                if (trimmed === "no_info")   { root.status = "no_info";   return }

                let parsed = null
                try {
                    parsed = JSON.parse(trimmed)
                } catch (error) {
                    parsed = null
                }
                if (!parsed || parsed.ok !== true) return
                const rawLines = parsed.lines ?? []
                let lines = []
                for (let i = 0; i < rawLines.length; i++) {
                    const entry = rawLines[i]
                    const t = Number(entry?.t)
                    if (!isNaN(t))
                        lines.push({ time: t, text: entry.text ?? "", words: entry.words ?? null,
                            romanized: entry.romanized ?? "", translated: entry.translated ?? "" })
                }

                if (lines.length === 0) { root.status = "not_found"; return }

                root.lyricsLines = root.withFillers(lines)
                root.activeIndex = -1
                root.slots = root.buildSlots(-1)
                root.status = "ok"
            }
        }
    }

    function restartLyrics() {
        lyricsProc.running = false
        root.lyricsLines = []
        root.activeIndex = -1
        root.slots = []

        if (!root.lyricsWanted) {
            root.status = "idle"
            return
        }

        root.status = "loading"

        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length       ?? 0

        // Title only: a browser/YouTube player often reports an empty
        // artist with everything packed in the title ("Sleep Token -
        // Provider - YouTube"), and scripts/lyrics/lyrics.py's normalizer
        // unpacks that - which it cannot do if this guard drops the track
        // first. An unresolvable title still comes back not_found.
        if (!title) { root.status = "no_info"; return }

        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration))
        ]
        lyricsProc.running = true
    }

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() { root.restartLyrics() }
        function onTrackArtistChanged() { root.restartLyrics() }
    }

    onLyricsWantedChanged: {
        if (root.lyricsWanted) root.restartLyrics()
        else {
            lyricsProc.running = false
            root.lyricsLines = []
            root.slots = []
            root.status = "idle"
        }
    }
}
