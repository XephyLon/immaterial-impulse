#!/usr/bin/env python3
"""Synced lyrics for TITLE ARTIST [DURATION], as one §-separated line.

Provider chain, in order:

 0. GlassyMusic's own BetterLyrics DOM over CDP (glassy_dom.py) - the full
    richsync the app is already showing, word stamps included, when the app
    runs with a debug port. Track-guarded; fails soft to the chain below.
 0.4 LyricsPlus / KPoe (lyricsplus.prjktla.my.id) - the app-INDEPENDENT
    word-sync source: a public, keyless proxy over Apple/Musixmatch/Spotify
    richsync, returning per-word time+duration. Answers first among the
    network providers, so word sync works with Glassy closed. Fails soft.
 0.5 BetterLyrics' richsync API (lyrics.api.dacubeking.com) - the
    Musixmatch word-by-word source the plugin itself uses - when the user
    has placed a bearer token in
    ~/.config/immaterial-impulse/betterlyrics-token (their own browser
    session's; the endpoint is Turnstile-gated). Word stamps without the
    app running. 401/403 or a missing file fall through silently.
 1. BetterLyrics' community API (unison.boidu.dev) - prioritized on the
    maintainer's call after comparing sync quality. Rows carry their body in
    `lyrics` with a `format` of lrc/ttml/plain; plain is unsynced and the
    whole widget is the sync, so it does not count as an answer. (The
    extension's primary source, lyrics.api.dacubeking.com, sits behind a
    Cloudflare Turnstile token and is not reachable from a shell script.)
 2. lrclib's exact get (track + artist + duration).
 3. lrclib's search - VALIDATED: the artist must match and a known duration
    must agree within five seconds. The old unvalidated q= search served
    Alan Walker's "Darkside" for "Faded": a plausible mask of the wrong
    thing, which is worse than no lyrics at all.

Output: one JSON line - {"ok": true, "lines": [{"t": sec, "text": "...",
"words": [[sec, "word"], ...]?}]} - or "not_found". `words` is present only
when the source carried word-level timing (enhanced LRC inline stamps, TTML
span timings); the shell synthesizes an even sweep otherwise.
"""
import json
import re
import sys
import urllib.parse
import urllib.request


# A browser-ish UA: several of these hosts (LyricsPlus behind Cloudflare)
# answer curl fine but 403 the default "Python-urllib/3.x" agent - which
# read as a dead server until the agent was the thing being refused.
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/128.0 Safari/537.36")


def http_json(url):
    try:
        request = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(request, timeout=12) as response:
            return json.loads(response.read().decode("utf-8", "replace"))
    except Exception:
        return None


WORD_STAMP = re.compile(r"<(\d+):(\d+(?:\.\d+)?)>")


def parse_lrc_rich(text):
    """[(t, text, words|None)] - words from enhanced-LRC inline <mm:ss.xx>."""
    lines = []
    for raw in text.splitlines():
        plain = WORD_STAMP.sub("", raw)
        words_text = re.sub(r"\[[^\]]*\]", "", plain).strip()
        if not words_text:
            continue
        words = None
        stamps = list(WORD_STAMP.finditer(raw))
        if stamps:
            words = []
            for index, stamp in enumerate(stamps):
                end = stamps[index + 1].start() if index + 1 < len(stamps) else len(raw)
                fragment = re.sub(r"\[[^\]]*\]", "", raw[stamp.end():end]).strip()
                if fragment:
                    words.append((int(stamp.group(1)) * 60 + float(stamp.group(2)), fragment))
            words = words or None
        for stamp in re.finditer(r"\[(\d+):(\d+(?:\.\d+)?)\]", raw):
            lines.append((int(stamp.group(1)) * 60 + float(stamp.group(2)), words_text, words))
    lines.sort(key=lambda entry: entry[0])
    return lines


def parse_lrc(text):
    """Line-level pairs; the rich parser's shadow, kept for its callers."""
    return [(t, words_text) for t, words_text, _ in parse_lrc_rich(text)]


def ttml_seconds(value):
    if value.endswith("ms"):
        return float(value[:-2]) / 1000
    if value.endswith("s") and ":" not in value:
        return float(value[:-1])
    out = 0.0
    for part in value.split(":"):
        out = out * 60 + float(part)
    return out


def parse_ttml_rich(text):
    """[(t, text, words|None)] - words from per-span begin timings."""
    import xml.etree.ElementTree as ET

    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return []
    lines = []
    for node in root.iter():
        if node.tag != "p" and not node.tag.endswith("}p"):
            continue
        begin = node.get("begin")
        line_text = "".join(node.itertext()).strip()
        if begin is None or not line_text:
            continue
        words = []
        for span in node:
            if span.tag != "span" and not span.tag.endswith("}span"):
                continue
            span_begin = span.get("begin")
            span_text = "".join(span.itertext()).strip()
            if span_begin is None or not span_text:
                continue
            try:
                words.append((ttml_seconds(span_begin), span_text))
            except ValueError:
                continue
        try:
            lines.append((ttml_seconds(begin), line_text, words or None))
        except ValueError:
            continue
    lines.sort(key=lambda entry: entry[0])
    return lines


def parse_ttml(text):
    """Line-level pairs; the rich parser's shadow, kept for its callers."""
    return [(t, line_text) for t, line_text, _ in parse_ttml_rich(text)]


def from_unison(title, artist, duration):
    params = {"song": title, "artist": artist}
    if duration:
        params["duration"] = int(duration)
    data = http_json("https://unison.boidu.dev/lyrics?"
                     + urllib.parse.urlencode(params))
    if not isinstance(data, dict) or data.get("success") is False:
        return None
    row = data.get("data") if isinstance(data.get("data"), dict) else data
    body, fmt = row.get("lyrics"), row.get("format")
    if not body:
        return None
    if fmt == "lrc":
        return parse_lrc_rich(body) or None
    if fmt == "ttml":
        return parse_ttml_rich(body) or None
    return None


def artist_matches(wanted, got):
    wanted, got = (wanted or "").casefold(), (got or "").casefold()
    return bool(wanted) and (wanted in got or got in wanted)


def duration_agrees(wanted, got):
    if not wanted:
        return True
    try:
        got = float(got)
    except (TypeError, ValueError):
        return True
    return abs(got - wanted) <= 5


def pick_search_hit(items, artist, duration):
    for item in items or []:
        if not isinstance(item, dict) or not item.get("syncedLyrics"):
            continue
        if not artist_matches(artist, item.get("artistName")):
            continue
        if not duration_agrees(duration, item.get("duration")):
            continue
        return item
    return None


def from_lrclib(title, artist, duration):
    base = "https://lrclib.net/api"
    exact = http_json(base + "/get?" + urllib.parse.urlencode(
        {"track_name": title, "artist_name": artist, "duration": int(duration or 0)}))
    if isinstance(exact, dict) and exact.get("syncedLyrics"):
        parsed = parse_lrc_rich(exact["syncedLyrics"])
        if parsed:
            return parsed
    hits = http_json(base + "/search?" + urllib.parse.urlencode(
        {"track_name": title, "artist_name": artist}))
    hit = pick_search_hit(hits, artist, duration)
    if hit:
        return parse_lrc_rich(hit["syncedLyrics"]) or None
    return None


CUBEY_URL = "https://lyrics.api.dacubeking.com/v2/lyrics"


def cubey_token():
    import os
    path = os.path.join(os.environ.get("XDG_CONFIG_HOME",
        os.path.expanduser("~/.config")), "immaterial-impulse/betterlyrics-token")
    try:
        with open(path) as f:
            token = f.read().strip()
        return token or None
    except OSError:
        return None


def parse_cubey(payload):
    """The response's best body, as rich lines. Word-by-word first - that
    is the whole reason to carry a token - then the line-synced fallbacks."""
    if not isinstance(payload, dict):
        return None
    for field in ("musixmatchWordByWordLyrics", "musixmatchSyncedLyrics",
                  "lrclibSyncedLyrics"):
        body = payload.get(field)
        if body:
            parsed = parse_lrc_rich(body)
            if parsed:
                return parsed
    return None


def from_cubey(title, artist, duration):
    token = cubey_token()
    if not token:
        return None
    data = urllib.parse.urlencode({
        "song": title, "artist": artist,
        **({"duration": str(int(duration))} if duration else {})}).encode()
    request = urllib.request.Request(CUBEY_URL, data=data, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            payload = json.loads(response.read().decode("utf-8", "replace"))
    except Exception:
        return None
    return parse_cubey(payload)


def reassemble_words(syllables):
    """Flat [(time, text, dur?), ...] -> word entries, split on the trailing
    space Apple/Musixmatch mark word boundaries with. A word that spanned
    several syllables ("pro"+"vi"+"der") becomes one entry carrying its
    syllables as sub-units; a single-syllable word carries none. Word time is
    its first syllable's, its duration runs to the last syllable's end.
    """
    words, current = [], []
    def flush():
        if not current:
            return
        start = current[0][0]
        last = current[-1]
        end = last[0] + last[2] if len(last) > 2 and last[2] is not None else last[0]
        text = "".join(s[1] for s in current).strip()
        if not text:
            current.clear()
            return
        entry = [start, text, max(0.0, end - start)]
        if len(current) > 1:
            entry.append([[s[0], s[1].strip()] for s in current if s[1].strip()])
        words.append(tuple(entry))
        current.clear()
    for syl in syllables:
        current.append(syl)
        if syl[1].endswith((" ", "\u00a0", "\n")):
            flush()
    flush()
    return words


LYRICSPLUS_URL = "https://lyricsplus.prjktla.my.id/v2/lyrics/get"


def parse_lyricsplus(payload):
    """KPoe v2 -> [(t, text, dur, [(t, word)])]. Word timing lives in each
    line's `syllabus` (time/duration in ms); a line without it is line-level
    and not what this provider is for, so it is dropped rather than faked."""
    if not isinstance(payload, dict) or payload.get("type") != "Word":
        return None
    out = []
    for line in payload.get("lyrics") or []:
        syllabus = line.get("syllabus") or []
        raw = []
        for syl in syllabus:
            try:
                wt = float(syl["time"]) / 1000.0
            except (KeyError, TypeError, ValueError):
                continue
            text = str(syl.get("text", ""))  # keep trailing space - the boundary
            if not text.strip():
                continue
            dur = syl.get("duration")
            raw.append((wt, text, float(dur) / 1000.0 if isinstance(dur, (int, float)) else None))
        words = reassemble_words(raw)
        if not words:
            continue
        try:
            line_t = float(line["time"]) / 1000.0
        except (KeyError, TypeError, ValueError):
            line_t = words[0][0]
        text = str(line.get("text", "")).strip() or " ".join(w[1] for w in words)
        out.append((line_t, text, words))
    out.sort(key=lambda e: e[0])
    return out or None


def from_lyricsplus(title, artist, duration):
    # Duration disambiguates covers, but LyricsPlus rejects a match whose
    # length differs from its own - and a browser's reported length often
    # does, so a song it HAS comes back empty. Try with duration for
    # precision, then without it rather than lose the track (Provider from a
    # YouTube tab: None at 222s, 53 lines with no duration).
    attempts = []
    if duration:
        attempts.append({"title": title, "artist": artist, "duration": str(int(duration))})
    attempts.append({"title": title, "artist": artist})
    for params in attempts:
        lines = parse_lyricsplus(http_json(LYRICSPLUS_URL + "?" + urllib.parse.urlencode(params)))
        if lines:
            return lines
    return None


def from_glassy(title, artist, duration):
    try:
        import glassy_dom
    except ImportError:
        return None
    return glassy_dom.fetch(title, artist)


# Browser MPRIS metadata is dirty: YouTube tabs report a title like
# "Sleep Token - Provider - YouTube" with no artist, or a "SleepTokenVEVO"
# channel as the artist - none of which a lyrics search matches. This
# normalizes them into a real title/artist, and is a no-op for a well-formed
# player (Spotify's "Diamonds" / "Rihanna" survives untouched).
TITLE_SUFFIXES = (" - youtube music", " - youtube", " - topic")
NOISE = re.compile(
    r"\s*[\(\[]\s*(official\s*(music\s*)?(video|audio|lyric(s)?(\s*video)?)"
    r"|lyric(s)?(\s*video)?|audio|visuali[sz]er|music\s*video|m/?v|hd|4k"
    r"|remaster(ed)?(\s*\d{4})?)\s*[\)\]]",
    re.IGNORECASE)


def channel_artist(artist):
    a = (artist or "").strip()
    low = a.casefold()
    return (not a) or low.endswith("vevo") or low.endswith("- topic") \
        or low.endswith("official")


def strip_channel(artist):
    a = (artist or "").strip()
    if a.casefold().endswith("vevo"):
        a = a[:-4].strip()
    if a.casefold().endswith("- topic"):
        a = a[:-7].strip()
    return a


def normalize_track(title, artist):
    title = (title or "").strip()
    artist = (artist or "").strip()
    low = title.casefold()
    for suffix in TITLE_SUFFIXES:
        if low.endswith(suffix):
            title = title[: len(title) - len(suffix)].strip()
            low = title.casefold()
    title = NOISE.sub("", title).strip()
    # "Artist - Song" packed into the title, with no usable artist of its own.
    if channel_artist(artist) and " - " in title:
        left, _, right = title.partition(" - ")
        left, right = left.strip(), right.strip()
        if left and right:
            title, artist = right, left
    else:
        artist = strip_channel(artist)
    return title, artist


def main():
    if len(sys.argv) < 3:
        print("no_info")
        return 0
    title, artist = normalize_track(sys.argv[1], sys.argv[2])
    if not title:
        print("no_info")
        return 0
    try:
        duration = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    except ValueError:
        duration = 0.0
    for provider in (from_glassy, from_lyricsplus, from_cubey, from_unison, from_lrclib):
        lines = provider(title, artist, duration)
        if lines:
            print(json.dumps({"ok": True, "lines": [
                {"t": stamp, "text": line_text,
                 **({"words": [list(word) for word in words]} if words else {})}
                for stamp, line_text, words in lines]}))
            return 0
    print("not_found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
