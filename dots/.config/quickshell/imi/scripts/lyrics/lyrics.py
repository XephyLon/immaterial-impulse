#!/usr/bin/env python3
"""Synced lyrics for TITLE ARTIST [DURATION], as one §-separated line.

Provider chain, in order:

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

Output: time§text pairs joined by § with a trailing "ok", or "not_found".
"""
import json
import re
import sys
import urllib.parse
import urllib.request


def http_json(url):
    try:
        with urllib.request.urlopen(url, timeout=12) as response:
            return json.loads(response.read().decode("utf-8", "replace"))
    except Exception:
        return None


def parse_lrc(text):
    lines = []
    for raw in text.splitlines():
        words = re.sub(r"\[[^\]]*\]", "", raw).strip()
        if not words:
            continue
        for stamp in re.finditer(r"\[(\d+):(\d+(?:\.\d+)?)\]", raw):
            lines.append((int(stamp.group(1)) * 60 + float(stamp.group(2)), words))
    lines.sort(key=lambda pair: pair[0])
    return lines


def parse_ttml(text):
    import xml.etree.ElementTree as ET

    def seconds(value):
        if value.endswith("ms"):
            return float(value[:-2]) / 1000
        if value.endswith("s") and ":" not in value:
            return float(value[:-1])
        out = 0.0
        for part in value.split(":"):
            out = out * 60 + float(part)
        return out

    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return []
    lines = []
    for node in root.iter():
        if node.tag != "p" and not node.tag.endswith("}p"):
            continue
        begin = node.get("begin")
        words = "".join(node.itertext()).strip()
        if begin is None or not words:
            continue
        try:
            lines.append((seconds(begin), words))
        except ValueError:
            continue
    lines.sort(key=lambda pair: pair[0])
    return lines


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
        return parse_lrc(body) or None
    if fmt == "ttml":
        return parse_ttml(body) or None
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
        parsed = parse_lrc(exact["syncedLyrics"])
        if parsed:
            return parsed
    hits = http_json(base + "/search?" + urllib.parse.urlencode(
        {"track_name": title, "artist_name": artist}))
    hit = pick_search_hit(hits, artist, duration)
    if hit:
        return parse_lrc(hit["syncedLyrics"]) or None
    return None


def main():
    if len(sys.argv) < 3:
        print("no_info")
        return 0
    title, artist = sys.argv[1], sys.argv[2]
    try:
        duration = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    except ValueError:
        duration = 0.0
    for provider in (from_unison, from_lrclib):
        lines = provider(title, artist, duration)
        if lines:
            flat = []
            for stamp, words in lines:
                flat.append(str(stamp))
                flat.append(words.replace("§", " "))
            print("§".join(flat + ["ok"]))
            return 0
    print("not_found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
