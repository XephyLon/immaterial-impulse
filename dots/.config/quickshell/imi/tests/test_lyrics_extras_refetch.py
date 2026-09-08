#!/usr/bin/env python3
"""Glassy's translation/romanization arrive late; the shell asks again.

BetterLyrics renders `.blyrics--translated` / `.blyrics--romanized` a few
seconds after the lyrics themselves, so a one-shot fetch that ran first
cached a payload without them and the toggles never showed for that song.
`lyrics.py ... --extras` re-asks Glassy for just those fields and folds
them into the cache; LyricsService polls it every 10 s while the panel is
open on an incomplete Glassy result, merging in place.
"""
import contextlib
import io
import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lyrics"))
import lyrics  # noqa: E402

SERVICE = ROOT / "services/LyricsService.qml"

PLAIN = [(1.0, "hello", None, "", ""), (2.5, "world", None, "", "")]
WITH_EXTRAS = [(1.0, "hello", None, "he-ro", "bonjour"), (2.5, "world", None, "", "monde")]


def _run(argv, glassy_lines):
    """Run lyrics.main() with a stubbed Glassy provider; return stdout."""
    saved_argv, saved_glassy = sys.argv, lyrics.from_glassy
    def from_glassy(title, artist, duration):   # named: lyrics.py labels the source by __name__
        return glassy_lines
    lyrics.from_glassy = from_glassy
    sys.argv = ["lyrics.py", *argv]
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            lyrics.main()
    finally:
        sys.argv, lyrics.from_glassy = saved_argv, saved_glassy
    return out.getvalue().strip()


class ExtrasRefresh(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["XDG_CACHE_HOME"] = self.tmp.name
        os.environ.pop("IMI_LYRICS_NO_CACHE", None)
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(lambda: os.environ.pop("XDG_CACHE_HOME", None))

    def test_extras_are_reported_and_folded_into_the_cache(self):
        first = json.loads(_run(["Song", "Artist", "200"], PLAIN))
        self.assertEqual(first["source"], "Glassy")
        self.assertNotIn("translated", first["lines"][0])

        refreshed = json.loads(_run(["Song", "Artist", "200", "--extras"], WITH_EXTRAS))
        self.assertTrue(refreshed["extras"])
        self.assertEqual(refreshed["lines"], [
            {"t": 1.0, "romanized": "he-ro", "translated": "bonjour"},
            {"t": 2.5, "translated": "monde"},
        ])
        # The next plain fetch is served from the cache - and now carries them.
        again = json.loads(_run(["Song", "Artist", "200"], PLAIN))
        self.assertEqual(again["lines"][0]["translated"], "bonjour")
        self.assertEqual(again["lines"][0]["romanized"], "he-ro")
        self.assertEqual(again["lines"][1]["translated"], "monde")
        self.assertNotIn("romanized", again["lines"][1])

    def test_nothing_new_says_so_and_leaves_the_cache_alone(self):
        json.loads(_run(["Song", "Artist", "200"], PLAIN))
        before = sorted(Path(self.tmp.name).rglob("*.json"))
        stamps = [p.stat().st_mtime_ns for p in before]
        self.assertEqual(_run(["Song", "Artist", "200", "--extras"], PLAIN), "no_extras")
        self.assertEqual(_run(["Song", "Artist", "200", "--extras"], None), "no_extras")
        self.assertEqual([p.stat().st_mtime_ns for p in before], stamps)

    def test_merge_matches_by_time_and_never_overwrites(self):
        payload = {"lines": [{"t": 1.0, "text": "a", "translated": "kept"}, {"t": 2.0, "text": "b"}]}
        gained = lyrics.merge_extras(payload, [
            {"t": 1.02, "translated": "new", "romanized": "ro"},
            {"t": 2.5, "translated": "far"},
        ])
        self.assertEqual(gained, 1)
        self.assertEqual(payload["lines"][0], {"t": 1.0, "text": "a", "translated": "kept", "romanized": "ro"})
        self.assertEqual(payload["lines"][1], {"t": 2.0, "text": "b"})


class ServiceContract(unittest.TestCase):
    def setUp(self):
        src = SERVICE.read_text()
        src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
        self.src = re.sub(r"//[^\n]*", "", src)

    def test_the_refetch_runs_only_for_an_incomplete_glassy_result_while_shown(self):
        timer = self.src[self.src.index("id: extrasTimer"):]
        timer = timer[:timer.index("onTriggered")]
        for clause in ("root.lyricsWanted", 'root.status === "ok"', 'root.source === "Glassy"',
                       "!(root.hasRomanization && root.hasTranslation)",
                       "root.extrasAttempts < root.extrasMaxAttempts"):
            self.assertIn(clause, timer, clause)
        self.assertRegex(self.src, r"property int extrasMaxAttempts:\s*12")
        self.assertRegex(self.src, r"property int extrasIntervalMs:\s*10000")

    def test_the_extras_call_reuses_the_fetch_arguments(self):
        self.assertIn('root.lastFetchArgs.concat(["--extras"])', self.src)
        self.assertIn("root.lastFetchArgs = fetchArgs", self.src)
        self.assertIn("root.extrasAttempts = 0", self.src, "a new track starts the attempt budget over")

    def test_merge_is_in_place_not_a_reload(self):
        body = self.src[self.src.index("function mergeExtras"):]
        body = body[:body.index("\n    }\n") + 7]
        self.assertNotIn("root.lyricsLines =", body, "reassigning lyricsLines resets the sweep")
        self.assertIn("root.lyricsLinesChanged()", body)
        self.assertIn("if (!line.translated && extras[e].translated)", body,
                      "a translation already shown is never overwritten by a later, different one")


if __name__ == "__main__":
    unittest.main()
