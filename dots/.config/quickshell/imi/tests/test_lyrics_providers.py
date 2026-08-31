#!/usr/bin/env python3
"""Pins for scripts/lyrics/lyrics.py - the provider chain and its guards.

The parsers (lrc and ttml), the search validation that killed the
Darkside-for-Faded mismatch, and the provider order (unison answers first,
lrclib only after) - all against stubbed http_json, no network.
"""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lyrics"))
import lyrics


class LrcParseTests(unittest.TestCase):
    def test_lines_parse_and_sort(self):
        parsed = lyrics.parse_lrc("[00:12.5]world\n[00:03.2]hello\n\n[bad]meta")
        self.assertEqual(parsed, [(3.2, "hello"), (12.5, "world")])

    def test_multi_stamp_lines_repeat(self):
        parsed = lyrics.parse_lrc("[00:01.0][01:01.0]chorus")
        self.assertEqual(parsed, [(1.0, "chorus"), (61.0, "chorus")])


class TtmlParseTests(unittest.TestCase):
    def test_p_elements_with_begin(self):
        doc = ('<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
               '<p begin="12.5s">world</p><p begin="00:03.2">hello</p>'
               '<p>unstamped</p></div></body></tt>')
        self.assertEqual(lyrics.parse_ttml(doc), [(3.2, "hello"), (12.5, "world")])

    def test_garbage_is_empty(self):
        self.assertEqual(lyrics.parse_ttml("not xml"), [])


class SearchValidationTests(unittest.TestCase):
    def hit(self, artist, duration):
        return {"syncedLyrics": "[00:01.0]x", "artistName": artist, "duration": duration}

    def test_wrong_artist_is_refused(self):
        self.assertIsNone(lyrics.pick_search_hit(
            [self.hit("Somebody Else", 212)], "Alan Walker", 212))

    def test_far_duration_is_refused(self):
        self.assertIsNone(lyrics.pick_search_hit(
            [self.hit("Alan Walker", 250)], "Alan Walker", 212))

    def test_a_real_match_is_taken(self):
        self.assertIsNotNone(lyrics.pick_search_hit(
            [self.hit("Alan Walker", 214)], "Alan Walker", 212))

    def test_unknown_duration_passes(self):
        self.assertIsNotNone(lyrics.pick_search_hit(
            [self.hit("Alan Walker", None)], "Alan Walker", 212))


class ProviderChainTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.responses = {}
        def fake(url):
            self.calls.append(url)
            for key, value in self.responses.items():
                if key in url:
                    return value
            return None
        self._orig = lyrics.http_json
        lyrics.http_json = fake

    def tearDown(self):
        lyrics.http_json = self._orig

    def test_unison_answers_first(self):
        self.responses["unison"] = {"lyrics": "[00:01.0]hi", "format": "lrc"}
        self.assertEqual(lyrics.from_unison("t", "a", 100), [(1.0, "hi")])

    def test_unison_plain_is_not_an_answer(self):
        self.responses["unison"] = {"lyrics": "just words", "format": "plain"}
        self.assertIsNone(lyrics.from_unison("t", "a", 100))

    def test_unison_error_shape_is_not_an_answer(self):
        self.responses["unison"] = {"success": False, "error": "Lyrics not found"}
        self.assertIsNone(lyrics.from_unison("t", "a", 100))

    def test_lrclib_exact_beats_search(self):
        self.responses["/get?"] = {"syncedLyrics": "[00:02.0]exact"}
        self.responses["/search?"] = [ {"syncedLyrics": "[00:09.0]loose",
                                        "artistName": "a", "duration": 100} ]
        self.assertEqual(lyrics.from_lrclib("t", "a", 100), [(2.0, "exact")])
        self.assertTrue(any("/get?" in u for u in self.calls))


if __name__ == "__main__":
    unittest.main()
