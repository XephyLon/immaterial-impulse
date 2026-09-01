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

EXTRACT_JS = """(() => {
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
        for word in entry.get("words") or []:
            wt, ww = float(word[0]), str(word[1])
            extra = []
            if len(word) > 2 and isinstance(word[2], (int, float)):
                extra.append(float(word[2]))
                if len(word) > 3 and isinstance(word[3], list):
                    extra.append([[float(st), str(sw)] for st, sw in word[3]])
            words.append(tuple([wt, ww] + extra))
        text = str(entry.get("text") or "")
        if text:
            out.append((t, text, words or None,
                        str(entry.get("romanized") or ""),
                        str(entry.get("translated") or "")))
    out.sort(key=lambda e: e[0])
    return out or None


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

    async def run():
        async with websockets.connect(ws_url, max_size=20_000_000, open_timeout=4) as ws:
            await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                "params": {"expression": EXTRACT_JS, "returnByValue": True}}))
            while True:
                reply = json.loads(await asyncio.wait_for(ws.recv(), timeout=6))
                if reply.get("id") == 1:
                    value = reply.get("result", {}).get("result", {}).get("value")
                    return json.loads(value) if value else None

    try:
        payload = asyncio.run(run())
    except Exception:
        return None
    return lines_from_dom(payload, title, artist)
