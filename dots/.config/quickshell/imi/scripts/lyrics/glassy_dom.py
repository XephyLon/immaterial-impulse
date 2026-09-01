#!/usr/bin/env python3
"""Word-synced lyrics straight out of GlassyMusic's BetterLyrics DOM.

The better-lyrics plugin renders full richsync inside the app - every
`.blyrics--word` span carries data-time and data-duration - and that data
exists nowhere else this machine can reach (the upstream source sits behind
a Cloudflare Turnstile token). With the app launched with
--remote-debugging-port=9222 (~/.config/glassy-music-flags.conf), this
client reads it over CDP.

Fails soft by design: no port, no page, no websockets module, or a track
mismatch all return None - the provider chain just moves on to unison and
lrclib. The track GUARD matters: CDP answers whatever tab is playing, and
lyrics for the wrong song are worse than none.
"""
import json
import urllib.request

# Poll budgets for the async-render race (see fetch). When Glassy's player bar
# shows the requested track, BetterLyrics is merely still fetching its DOM, so
# wait up to GLASSY_RENDER_WAIT for the lines. When it shows a different track,
# Glassy is not the source; bail after GLASSY_MATCH_GRACE (enough for its own
# title to catch up to a change) so the fallback chain is not stalled.
GLASSY_RENDER_WAIT = 9.0
GLASSY_MATCH_GRACE = 2.0
GLASSY_POLL_INTERVAL = 0.4

EXTRACT_JS = r"""(() => {
    const lines = [...document.querySelectorAll('.blyrics--line')].map(line => {
        // .blyrics--word spans are SYLLABLES; the word is the
        // .blyrics-word-group around them (whole word in data-content,
        // start time on the first syllable). Read groups first - flattening
        // syllables spaced "pro vi der" across the panel - and keep the
        // flat spans only as a fallback for lines without groups.
        const groups = [...line.querySelectorAll('.blyrics-word-group')];
        let words;
        // Prefer word-groups (whole word in data-content). Where a track
        // is not wrapped in them, reassemble the flat syllable spans by the
        // trailing space that marks a word boundary - a syllable keeps its
        // OWN textContent (with the space), never .trim(), so the boundary
        // survives; "pro"+"vi"+"der" rejoins into one word.
        if (groups.length > 0) {
            words = groups.map(group => {
                const syls = [...group.querySelectorAll('.blyrics--word')]
                    .map(s => [parseFloat(s.dataset.time),
                               (s.dataset.content || s.textContent || '').trim(),
                               parseFloat(s.dataset.duration)])
                    .filter(([st, sw]) => Number.isFinite(st) && sw.length > 0);
                if (syls.length === 0) return [NaN, ''];
                const start = syls[0][0];
                const last = syls[syls.length - 1];
                const end = Number.isFinite(last[2]) ? last[0] + last[2] : last[0];
                return [start,
                        (group.dataset.content || group.textContent || '').trim(),
                        Math.max(0, end - start),
                        syls.length > 1 ? syls.map(([st, sw]) => [st, sw]) : null];
            });
        } else {
            const flat = [...line.querySelectorAll('.blyrics--word')]
                .map(s => ({ t: parseFloat(s.dataset.time),
                             text: (s.textContent || ''),
                             dur: parseFloat(s.dataset.duration) }))
                .filter(s => Number.isFinite(s.t) && s.text.trim().length > 0);
            words = [];
            let cur = [];
            const flush = () => {
                if (cur.length === 0) return;
                const start = cur[0].t;
                const last = cur[cur.length - 1];
                const end = Number.isFinite(last.dur) ? last.t + last.dur : last.t;
                const text = cur.map(s => s.text).join('').trim();
                if (text) words.push([start, text, Math.max(0, end - start),
                    cur.length > 1 ? cur.map(s => [s.t, s.text.trim()]) : null]);
                cur = [];
            };
            for (const s of flat) { cur.push(s); if (/\s$/.test(s.text)) flush(); }
            flush();
        }
        words = words.filter(([t, w]) => Number.isFinite(t) && (w || '').length > 0);
        // BetterLyrics renders the romanization and translation as sibling
        // content lines inside the same .blyrics--line; carry them so the
        // shell can offer the same two toggles Glassy has.
        const romanized = line.querySelector('.blyrics--romanized')?.textContent?.trim() ?? '';
        const translated = line.querySelector('.blyrics--translated')?.textContent?.trim() ?? '';
        return {
            t: parseFloat(line.dataset.time),
            text: words.map(([, w]) => w).join(' '),
            words: words,
            romanized: romanized,
            translated: translated,
        };
    }).filter(l => Number.isFinite(l.t) && l.text.length > 0);
    const title = document.querySelector('.title.ytmusic-player-bar')?.textContent?.trim() ?? '';
    const byline = document.querySelector('.byline.ytmusic-player-bar')?.textContent?.trim() ?? '';
    return JSON.stringify({ title, byline, lines });
})()"""


def lines_from_dom(payload, title, artist):
    """The pure half: DOM JSON -> [(t, text, words)] with the track guard."""
    if not isinstance(payload, dict):
        return None
    page_title = (payload.get("title") or "").casefold()
    want = (title or "").casefold()
    if not want or not page_title or (want not in page_title and page_title not in want):
        return None
    if artist:
        byline = (payload.get("byline") or "").casefold()
        first_artist = artist.casefold().split("&")[0].split(",")[0].strip()
        if first_artist and byline and first_artist not in byline:
            return None
    out = []
    for entry in payload.get("lines") or []:
        try:
            t = float(entry["t"])
        except (KeyError, TypeError, ValueError):
            continue
        words = []
        any_real_duration = False
        for word in entry.get("words") or []:
            wt, ww = float(word[0]), str(word[1])
            extra = []
            if len(word) > 2 and isinstance(word[2], (int, float)) and word[2] > 0:
                any_real_duration = True
                extra.append(float(word[2]))
                if len(word) > 3 and isinstance(word[3], list):
                    extra.append([[float(st), str(sw)] for st, sw in word[3]])
            words.append(tuple([wt, ww] + extra))
        # Real per-word karaoke carries per-word DURATIONS. BetterLyrics renders
        # LINE-synced lyrics as word spans too, but with no data-duration and
        # fake ~0.05s-apart data-time - so kept, the view raced the "current
        # word" through the whole line in a fraction of a second and parked on
        # the last word (the shimmer "jumped to the end"). When no word carries a
        # real duration, this is line-level: drop the words so the line sweep
        # walks the whole line (the same read LyricsPlus gives as one word).
        if not any_real_duration:
            words = []
        text = str(entry.get("text") or "")
        if text:
            out.append((t, text, words or None,
                        str(entry.get("romanized") or ""),
                        str(entry.get("translated") or "")))
    out.sort(key=lambda e: e[0])
    return out or None


def times_are_ready(lines):
    """BetterLyrics renders the line ELEMENTS before it fills their data-time:
    every line starts at data-time="0" and the real stamps arrive a beat later
    (the same async render the poll already waits on, one step deeper). Taking
    that half-rendered snapshot stamped a whole block of lines at t=0, and the
    sweep then stuck on the last of them while the song played on - the "open
    the sidebar right as a song starts and the lyrics are pinned" bug.

    A ready set has real, increasing stamps: at most one line may sit at ~0 (a
    genuine opening line), and the stamps must not decrease. A cluster of zeros
    means the render is not done, so the poll keeps waiting."""
    times = [float(line[0]) for line in lines]
    if sum(1 for t in times if t <= 0.05) > 1:
        return False
    return all(a <= b for a, b in zip(times, times[1:]))


def _page_ws_url():
    with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=3) as r:
        for target in json.loads(r.read().decode()):
            if target.get("type") == "page" and "music.youtube" in target.get("url", ""):
                return target["webSocketDebuggerUrl"]
    return None


def fetch(title, artist):
    try:
        import asyncio
        import websockets
    except ImportError:
        return None
    try:
        ws_url = _page_ws_url()
    except Exception:
        return None
    if not ws_url:
        return None

    # Glassy's BetterLyrics renders its DOM asynchronously after a track
    # change (it fetches over the network), so the shell's fetch on that
    # same change often arrives before the lines exist - which handed the
    # track to LyricsPlus and never came back, even though Glassy is the very
    # app playing it. A fixed 3s poll lost that race whenever the render ran
    # long. Poll SMART instead, off the one signal that tells the two cases
    # apart: Glassy's own player bar (EXTRACT_JS returns its title).
    #
    #   - Bar shows THIS track, lines not there yet -> Glassy is the source,
    #     BetterLyrics is still fetching; wait it out (RENDER_WAIT) so the
    #     word-synced lines win rather than a fallback grabbing the track.
    #   - Bar shows a DIFFERENT track (Glassy is running but not what is
    #     playing) -> not our source; bail after a short grace (MATCH_GRACE,
    #     enough for Glassy's own title to catch up to the change) so the
    #     fallback chain is not stalled for playback Glassy does not own.
    #
    # One websocket for the whole poll. The budgets are module constants so
    # a test can shrink them (GLASSY_RENDER_WAIT / GLASSY_MATCH_GRACE).
    want = (title or "").casefold()

    async def run():
        loop = asyncio.get_event_loop()
        async with websockets.connect(ws_url, max_size=20_000_000, open_timeout=4) as ws:
            mid = 0
            started = loop.time()
            matched_at = None
            while True:
                mid += 1
                await ws.send(json.dumps({"id": mid, "method": "Runtime.evaluate",
                    "params": {"expression": EXTRACT_JS, "returnByValue": True}}))
                payload = None
                while True:
                    reply = json.loads(await asyncio.wait_for(ws.recv(), timeout=6))
                    if reply.get("id") == mid:
                        value = reply.get("result", {}).get("result", {}).get("value")
                        payload = json.loads(value) if value else None
                        break
                lines = lines_from_dom(payload, title, artist)
                if lines and times_are_ready(lines):
                    return lines
                now = loop.time()
                page_title = ((payload or {}).get("title") or "").casefold()
                on_track = bool(want and page_title
                                and (want in page_title or page_title in want))
                if on_track:
                    if matched_at is None:
                        matched_at = now
                    if now - matched_at >= GLASSY_RENDER_WAIT:
                        return None
                elif now - started >= GLASSY_MATCH_GRACE:
                    return None
                await asyncio.sleep(GLASSY_POLL_INTERVAL)

    try:
        return asyncio.run(run())
    except Exception:
        return None
