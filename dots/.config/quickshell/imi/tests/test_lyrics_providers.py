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
        self.assertEqual(lyrics.from_unison("t", "a", 100), [(1.0, "hi", None)])

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
        self.assertEqual(lyrics.from_lrclib("t", "a", 100), [(2.0, "exact", None)])
        self.assertTrue(any("/get?" in u for u in self.calls))



class WordTimingTests(unittest.TestCase):
    def test_enhanced_lrc_words_are_extracted(self):
        rich = lyrics.parse_lrc_rich("[00:10.0]<00:10.0>hello <00:11.5>there")
        self.assertEqual(len(rich), 1)
        t, text, words = rich[0]
        self.assertEqual((t, text), (10.0, "hello there"))
        self.assertEqual(words, [(10.0, "hello"), (11.5, "there")])

    def test_plain_lrc_has_no_words(self):
        self.assertEqual(lyrics.parse_lrc_rich("[00:10.0]hello there")[0][2], None)

    def test_ttml_span_words_are_extracted(self):
        doc = ('<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
               '<p begin="10s"><span begin="10s">hello</span> '
               '<span begin="11.5s">there</span></p></div></body></tt>')
        t, text, words = lyrics.parse_ttml_rich(doc)[0]
        self.assertEqual((t, text), (10.0, "hello there"))
        self.assertEqual(words, [(10.0, "hello"), (11.5, "there")])

    def test_the_wire_is_json(self):
        import io, contextlib, sys as _sys
        argv, _sys.argv = _sys.argv, ["lyrics.py", "T", "A", "100"]
        orig = lyrics.http_json
        lyrics.http_json = lambda url: ({"lyrics": "[00:01.0]<00:01.0>hi <00:02.0>ho",
                                         "format": "lrc"} if "unison" in url else None)
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                lyrics.main()
        finally:
            lyrics.http_json = orig
            _sys.argv = argv
        import json as _json
        payload = _json.loads(out.getvalue())
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["lines"][0]["words"], [[1.0, "hi"], [2.0, "ho"]])



class GlassyDomTests(unittest.TestCase):
    """The pure half of the CDP provider: DOM payload -> lines, track-guarded."""

    def setUp(self):
        sys.path.insert(0, str(ROOT / "scripts/lyrics"))
        import glassy_dom
        self.mod = glassy_dom

    def payload(self, title="Lost Control", byline="Alan Walker, Sorana - 2 views"):
        return {"title": title, "byline": byline, "lines": [
            {"t": 12.0, "text": "Won't let go",
             "words": [[12.0, "Won't"], [12.3, "let"], [12.6, "go"]]},
            {"t": 15.0, "text": "provider here",
             "words": [[15.0, "provider", 0.9, [[15.0, "pro"], [15.3, "vi"], [15.6, "der"]]],
                       [16.0, "here"]]},
        ]}

    def test_words_come_through(self):
        lines = self.mod.lines_from_dom(self.payload(), "Lost Control", "Alan Walker & Sorana")
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0][2], [(12.0, "Won't"), (12.3, "let"), (12.6, "go")])

    def test_durations_and_syllables_survive(self):
        lines = self.mod.lines_from_dom(self.payload(), "Lost Control", "Alan Walker & Sorana")
        word = lines[1][2][0]
        self.assertEqual(word[0], 15.0)
        self.assertEqual(word[1], "provider")
        self.assertEqual(word[2], 0.9)
        self.assertEqual(word[3], [[15.0, "pro"], [15.3, "vi"], [15.6, "der"]])

    def test_wrong_title_is_refused(self):
        self.assertIsNone(self.mod.lines_from_dom(
            self.payload(title="Some Other Song"), "Lost Control", "Alan Walker"))

    def test_wrong_artist_is_refused(self):
        self.assertIsNone(self.mod.lines_from_dom(
            self.payload(byline="Somebody Else - views"), "Lost Control", "Alan Walker & Sorana"))

    def test_glassy_answers_before_every_network_provider(self):
        source = (ROOT / "scripts/lyrics/lyrics.py").read_text(encoding="utf-8")
        self.assertIn("(from_glassy, from_lyricsplus, from_cubey, from_unison, from_lrclib)", source)



class CubeyTests(unittest.TestCase):
    """The richsync API provider: token-gated, word-by-word preferred."""

    def test_no_token_is_a_silent_pass(self):
        orig = lyrics.cubey_token
        lyrics.cubey_token = lambda: None
        try:
            self.assertIsNone(lyrics.from_cubey("t", "a", 100))
        finally:
            lyrics.cubey_token = orig

    def test_word_by_word_beats_line_synced(self):
        payload = {
            "musixmatchWordByWordLyrics": "[00:10.0]<00:10.0>hello <00:11.5>there",
            "musixmatchSyncedLyrics": "[00:10.0]hello there",
        }
        lines = lyrics.parse_cubey(payload)
        self.assertEqual(lines[0][2], [(10.0, "hello"), (11.5, "there")])

    def test_line_synced_is_the_fallback(self):
        payload = {"musixmatchSyncedLyrics": "[00:10.0]hello there"}
        lines = lyrics.parse_cubey(payload)
        self.assertEqual(lines[0][:2], (10.0, "hello there"))
        self.assertIsNone(lines[0][2])

    def test_cubey_slots_after_glassy(self):
        source = (ROOT / "scripts/lyrics/lyrics.py").read_text(encoding="utf-8")
        self.assertIn("(from_glassy, from_lyricsplus, from_cubey, from_unison, from_lrclib)", source)



class LyricsPlusTests(unittest.TestCase):
    """KPoe v2: app-independent word sync, syllabus -> words."""

    def payload(self):
        return {"type": "Word", "lyrics": [
            {"time": 390, "text": "I wanna be a provider",
             "syllabus": [
                {"time": 390, "duration": 410, "text": "I "},
                {"time": 800, "duration": 850, "text": "wanna "},
                {"time": 1650, "duration": 440, "text": "be "},
                {"time": 2090, "duration": 410, "text": "a "},
                {"time": 2500, "duration": 380, "text": "pro"},
                {"time": 2880, "duration": 690, "text": "vi"},
                {"time": 3570, "duration": 500, "text": "der"}]},
            {"time": 20000, "text": "line-level only", "syllabus": []},
        ]}

    def test_syllables_rejoin_into_words(self):
        lines = lyrics.parse_lyricsplus(self.payload())
        self.assertEqual(len(lines), 1)  # the syllabus-less line is dropped
        t, text, words = lines[0]
        self.assertAlmostEqual(t, 0.39, places=3)
        self.assertEqual([w[1] for w in words], ["I", "wanna", "be", "a", "provider"])
        # "provider" carries its three syllables; "I" carries none.
        provider = words[-1]
        self.assertEqual([s[1] for s in provider[3]], ["pro", "vi", "der"])
        self.assertEqual(len(words[0]), 3)  # single-syllable word: no sub-array

    def test_non_word_type_is_refused(self):
        self.assertIsNone(lyrics.parse_lyricsplus({"type": "Line", "lyrics": []}))

    def test_lyricsplus_answers_before_the_gated_and_line_providers(self):
        source = (ROOT / "scripts/lyrics/lyrics.py").read_text(encoding="utf-8")
        self.assertIn("(from_glassy, from_lyricsplus, from_cubey, from_unison, from_lrclib)", source)



class NormalizeTrackTests(unittest.TestCase):
    def n(self, title, artist):
        return lyrics.normalize_track(title, artist)

    def test_youtube_suffix_and_packed_artist(self):
        # Firefox: everything in the title, no artist.
        self.assertEqual(self.n("Sleep Token - Provider - YouTube", ""),
                         ("Provider", "Sleep Token"))

    def test_vevo_channel_artist(self):
        # plasma-browser-integration: channel as artist.
        self.assertEqual(self.n("Sleep Token - Provider", "SleepTokenVEVO"),
                         ("Provider", "Sleep Token"))

    def test_topic_channel(self):
        self.assertEqual(self.n("Blinding Lights", "The Weeknd - Topic"),
                         ("Blinding Lights", "The Weeknd"))

    def test_official_noise_stripped(self):
        title, artist = self.n("Faded (Official Music Video)", "")
        self.assertEqual(title, "Faded")

    def test_clean_player_untouched(self):
        # Spotify: already correct, must not be mangled.
        self.assertEqual(self.n("Diamonds", "Rihanna"), ("Diamonds", "Rihanna"))

    def test_hyphen_title_kept_when_artist_is_real(self):
        # A real artist means the title's hyphen is not an "artist - song".
        self.assertEqual(self.n("Song - Part II", "Some Band"),
                         ("Song - Part II", "Some Band"))



class LyricsPlusDurationRetryTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self._orig = lyrics.http_json
        def fake(url):
            self.calls.append(url)
            # answer only the request WITHOUT a duration param
            if "duration" in url:
                return None
            return {"type": "Word", "lyrics": [
                {"time": 1000, "text": "hi there",
                 "syllabus": [{"time": 1000, "duration": 300, "text": "hi "},
                              {"time": 1300, "duration": 300, "text": "there"}]}]}
        lyrics.http_json = fake

    def tearDown(self):
        lyrics.http_json = self._orig

    def test_retries_without_duration_when_the_dated_query_is_empty(self):
        r = lyrics.from_lyricsplus("Provider", "Sleep Token", 222)
        self.assertIsNotNone(r)
        self.assertEqual([w[1] for w in r[0][2]], ["hi", "there"])
        self.assertEqual(len(self.calls), 2)  # tried with duration, then without
        self.assertIn("duration", self.calls[0])
        self.assertNotIn("duration", self.calls[1])


if __name__ == "__main__":
    unittest.main()
