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
        const words = [...line.querySelectorAll('.blyrics--word')]
            .map(w => [parseFloat(w.dataset.time),
                       (w.dataset.content || w.textContent || '').trim()])
            .filter(([t, w]) => Number.isFinite(t) && w.length > 0);
        return {
            t: parseFloat(line.dataset.time),
            text: words.map(([, w]) => w).join(' '),
            words: words,
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
        words = [(float(wt), str(ww)) for wt, ww in (entry.get("words") or [])]
        text = str(entry.get("text") or "")
        if text:
            out.append((t, text, words or None))
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
