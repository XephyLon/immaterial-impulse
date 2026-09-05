#!/usr/bin/env python3
"""Pins for scripts/lyrics/lyrics.py - the provider chain and its guards.

The parsers (lrc and ttml), the search validation that killed the
Darkside-for-Faded mismatch, and the provider order (unison answers first,
lrclib only after) - all against stubbed http_json, no network.
"""
import sys
import time
import json
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

    def test_multi_stamp_line_drops_its_words(self):
        # A line repeated at two timestamps carries ONE set of inline word
        # stamps, absolute to the first occurrence; attaching them to the
        # second position mis-times its karaoke. Both positions keep the
        # line-level text, neither keeps the words.
        rich = lyrics.parse_lrc_rich("[00:10.0][00:40.0]<00:10.0>hello <00:11.5>there")
        self.assertEqual([r[0] for r in rich], [10.0, 40.0])
        self.assertEqual([r[1] for r in rich], ["hello there", "hello there"])
        self.assertTrue(all(r[2] is None for r in rich))

    def test_ttml_span_words_are_extracted(self):
        doc = ('<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
               '<p begin="10s"><span begin="10s">hello</span> '
               '<span begin="11.5s">there</span></p></div></body></tt>')
        t, text, words = lyrics.parse_ttml_rich(doc)[0]
        self.assertEqual((t, text), (10.0, "hello there"))
        self.assertEqual(words, [(10.0, "hello"), (11.5, "there")])

    def test_the_wire_is_json(self):
        import io, contextlib, sys as _sys, os
        os.environ["IMI_LYRICS_NO_CACHE"] = "1"  # exercise the fetch, not the cache
        self.addCleanup(lambda: os.environ.pop("IMI_LYRICS_NO_CACHE", None))
        argv, _sys.argv = _sys.argv, ["lyrics.py", "T", "A", "100"]
        orig = lyrics.http_json
        orig_glassy = lyrics.from_glassy
        # Glassy answers over CDP, not http_json - stub it off so this stays
        # hermetic whether or not a real GlassyMusic is running with a port.
        lyrics.from_glassy = lambda *a, **k: None
        lyrics.http_json = lambda url: ({"lyrics": "[00:01.0]<00:01.0>hi <00:02.0>ho",
                                         "format": "lrc"} if "unison" in url else None)
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                lyrics.main()
        finally:
            lyrics.http_json = orig
            lyrics.from_glassy = orig_glassy
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
             "words": [[12.0, "Won't", 0.2], [12.3, "let", 0.2], [12.6, "go", 0.3]]},
            {"t": 15.0, "text": "provider here",
             "words": [[15.0, "provider", 0.9, [[15.0, "pro"], [15.3, "vi"], [15.6, "der"]]],
                       [16.0, "here"]]},
        ]}

    def test_words_come_through(self):
        lines = self.mod.lines_from_dom(self.payload(), "Lost Control", "Alan Walker & Sorana")
        self.assertEqual(len(lines), 2)
        self.assertEqual([(w[0], w[1]) for w in lines[0][2]],
                         [(12.0, "Won't"), (12.3, "let"), (12.6, "go")])

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

    def line(self, *times):
        return [(t, "x", None, "", "") for t in times]

    def test_times_ready_rejects_a_zero_block(self):
        # A half-rendered snapshot: elements present, data-time still 0.
        self.assertFalse(self.mod.times_are_ready(self.line(0.0, 0.0, 5.0, 10.0)))

    def test_times_ready_accepts_real_increasing_stamps(self):
        self.assertTrue(self.mod.times_are_ready(self.line(11.0, 16.0, 20.0, 28.0)))

    def test_times_ready_allows_a_single_opening_zero(self):
        self.assertTrue(self.mod.times_are_ready(self.line(0.0, 5.0, 10.0)))

    def test_words_with_real_durations_are_kept_as_karaoke(self):
        # Genuine per-word karaoke carries per-word durations - keep the words.
        p = {"title": "Lost Control", "byline": "Alan Walker", "lines": [
            {"t": 10.0, "text": "won't let go",
             "words": [[10.0, "won't", 0.3], [10.4, "let", 0.3], [10.8, "go", 0.4]]}]}
        lines = self.mod.lines_from_dom(p, "Lost Control", "Alan Walker")
        self.assertTrue(lines[0][2])

    def test_durationless_words_become_line_level(self):
        # BetterLyrics' line-synced render: word spans with fake ~0.05s-apart
        # times and NO durations. Not real karaoke - drop the words so the line
        # sweep walks the whole line rather than racing to the last word.
        p = {"title": "Lost Control", "byline": "Alan Walker", "lines": [
            {"t": 0.59, "text": "welcome to the club",
             "words": [[0.59, "welcome", 0.0], [0.64, "to", 0.0],
                       [0.69, "the", 0.0], [0.74, "club", 0.0]]}]}
        lines = self.mod.lines_from_dom(p, "Lost Control", "Alan Walker")
        self.assertIsNone(lines[0][2],
                          "no real per-word duration -> line-level, not karaoke")

    def test_same_time_words_are_line_level(self):
        p = {"title": "Lost Control", "byline": "Alan Walker", "lines": [
            {"t": 10.0, "text": "won't let go",
             "words": [[10.0, "won't"], [10.0, "let"], [10.0, "go"]]}]}
        lines = self.mod.lines_from_dom(p, "Lost Control", "Alan Walker")
        self.assertIsNone(lines[0][2])



class GlassyDomPollTests(unittest.TestCase):
    """The smart poll: wait out Glassy's own async render, bail fast on a track
    Glassy is not playing. Guards the async-render race that twice handed a
    Glassy track to a fallback provider."""

    LINE = [{"t": 16.4, "text": "line", "words": [[16.4, "I", 0.2]]}]
    # BetterLyrics renders the line elements with data-time=0, then fills the
    # real stamps a beat later. The zero block is the half-rendered snapshot.
    ZEROS = [{"t": 0, "text": "a", "words": [[0, "a"]]},
             {"t": 0, "text": "b", "words": [[0, "b"]]},
             {"t": 0, "text": "c", "words": [[0, "c"]]}]
    REAL = [{"t": 11, "text": "a", "words": [[11, "a"]]},
            {"t": 16, "text": "b", "words": [[16, "b"]]},
            {"t": 20, "text": "c", "words": [[20, "c"]]}]

    def setUp(self):
        sys.path.insert(0, str(ROOT / "scripts/lyrics"))
        import glassy_dom
        self.mod = glassy_dom
        self._saved = (glassy_dom.GLASSY_RENDER_WAIT, glassy_dom.GLASSY_MATCH_GRACE,
                       glassy_dom.GLASSY_POLL_INTERVAL)
        # Shrink the budgets so the timing paths resolve in a fraction of a second.
        glassy_dom.GLASSY_RENDER_WAIT = 0.6
        glassy_dom.GLASSY_MATCH_GRACE = 0.2
        glassy_dom.GLASSY_POLL_INTERVAL = 0.02
        glassy_dom._page_ws_url = lambda: "ws://fake"

    def tearDown(self):
        (self.mod.GLASSY_RENDER_WAIT, self.mod.GLASSY_MATCH_GRACE,
         self.mod.GLASSY_POLL_INTERVAL) = self._saved
        sys.modules.pop("websockets", None)

    def _install(self, script):
        import types
        outer = self

        class FakeWS:
            def __init__(self):
                self.mid = 0

            async def send(self, msg):
                self.mid = json.loads(msg)["id"]

            async def recv(self):
                payload = script(self.mid)
                value = json.dumps(payload) if payload is not None else None
                return json.dumps({"id": self.mid, "result": {"result": {"value": value}}})

            async def __aenter__(self):
                return self

            async def __aexit__(self, *a):
                return False

        fake = types.ModuleType("websockets")
        fake.connect = lambda url, **kw: FakeWS()
        sys.modules["websockets"] = fake

    def _match(self, lines):
        return {"title": "Running in the Night", "byline": "FM-84", "lines": lines}

    def test_waits_out_the_render_race(self):
        # Player bar shows the track; the lines only appear after a few polls.
        self._install(lambda mid: self._match([] if mid <= 3 else self.LINE))
        self.assertTrue(self.mod.fetch("Running in the Night", "FM-84"),
                        "must wait for Glassy's own render, not bail to a fallback")

    def test_waits_for_populated_timestamps(self):
        # Lines exist but their stamps are still 0 for the first polls; the poll
        # must reject the zero block and return the real-timed lines - the
        # "sidebar opened as the song starts, lyrics pinned at t=0" bug.
        self._install(lambda mid: self._match(self.ZEROS if mid <= 3 else self.REAL))
        lines = self.mod.fetch("Running in the Night", "FM-84")
        self.assertTrue(lines)
        self.assertGreater(lines[0][0], 0.05,
                           "must return real-timed lines, not the t=0 render")

    def test_bails_fast_when_glassy_plays_another_track(self):
        self._install(lambda mid: {"title": "Some Other Song", "byline": "X", "lines": []})
        start = time.monotonic()
        self.assertIsNone(self.mod.fetch("Running in the Night", "FM-84"))
        self.assertLess(time.monotonic() - start, 0.5,
                        "a track Glassy is not playing must not stall the chain")

    def test_gives_up_when_the_track_never_renders(self):
        self._install(lambda mid: self._match([]))
        self.assertIsNone(self.mod.fetch("Running in the Night", "FM-84"))


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


class CacheTests(unittest.TestCase):
    """The on-disk cache: a repeat of the same track must not re-walk the
    network, and a not_found must not re-walk it for a while either."""

    def setUp(self):
        import tempfile, os
        self.tmp = tempfile.mkdtemp()
        self.env = os.environ.get("XDG_CACHE_HOME")
        os.environ["XDG_CACHE_HOME"] = self.tmp

    def tearDown(self):
        import os, shutil
        if self.env is None:
            os.environ.pop("XDG_CACHE_HOME", None)
        else:
            os.environ["XDG_CACHE_HOME"] = self.env
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_positive_roundtrip(self):
        key = lyrics.cache_key("Provider", "Sleep Token", 222)
        payload = {"ok": True, "source": "LRCLIB", "lines": [{"t": 1.0, "text": "hi"}]}
        lyrics.cache_put(key, payload)
        self.assertEqual(lyrics.cache_get(key), payload)

    def test_negative_roundtrip(self):
        key = lyrics.cache_key("Nope", "Nobody", 100)
        lyrics.cache_put(key, "not_found")
        self.assertEqual(lyrics.cache_get(key), "not_found")

    def test_key_is_case_and_duration_stable_but_track_specific(self):
        self.assertEqual(lyrics.cache_key("Provider", "Sleep Token", 222),
                         lyrics.cache_key("provider", "sleep token", 222))
        self.assertNotEqual(lyrics.cache_key("Provider", "Sleep Token", 222),
                            lyrics.cache_key("Provider", "Sleep Token", 250))
        self.assertNotEqual(lyrics.cache_key("A", "X", 100),
                            lyrics.cache_key("B", "X", 100))

    def test_expired_positive_is_a_miss(self):
        import os, json, time
        key = lyrics.cache_key("Old", "Song", 100)
        path = os.path.join(lyrics.cache_dir(), key + ".json")
        os.makedirs(lyrics.cache_dir(), exist_ok=True)
        with open(path, "w") as f:
            json.dump({"ts": time.time() - lyrics.POSITIVE_TTL - 10,
                       "result": {"ok": True, "lines": []}}, f)
        self.assertIsNone(lyrics.cache_get(key))

    def test_expired_negative_is_a_miss(self):
        import os, json, time
        key = lyrics.cache_key("Old", "Miss", 100)
        os.makedirs(lyrics.cache_dir(), exist_ok=True)
        with open(os.path.join(lyrics.cache_dir(), key + ".json"), "w") as f:
            json.dump({"ts": time.time() - lyrics.NEGATIVE_TTL - 10,
                       "result": "not_found"}, f)
        self.assertIsNone(lyrics.cache_get(key))

    def test_network_failure_is_not_cached_as_not_found(self):
        # An offline moment walks every provider to None exactly like a real
        # miss - but caching THAT as not_found hides lyrics for six hours
        # after the Wi-Fi comes back. Only a miss where at least one provider
        # actually answered may be negative-cached.
        import io, contextlib, sys as _sys, os
        orig_http, orig_glassy = lyrics.http_json, lyrics.from_glassy
        lyrics.from_glassy = lambda *a, **k: None
        argv = _sys.argv
        try:
            # Nothing reachable: http_json fails everywhere (never records an
            # answer). not_found is printed but NOT cached.
            lyrics.net_answers = 0
            lyrics.http_json = lambda url: None
            _sys.argv = ["lyrics.py", "Offline", "Song", "100"]
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                lyrics.main()
            self.assertEqual(out.getvalue().strip(), "not_found")
            self.assertIsNone(
                lyrics.cache_get(lyrics.cache_key("Offline", "Song", 100)),
                "an unreachable network must not poison the negative cache")

            # A provider ANSWERED and had nothing: that is a real miss, cached.
            def answering(url):
                lyrics.net_answers += 1
                return {"success": False, "error": "Lyrics not found"} if "unison" in url else None
            lyrics.net_answers = 0
            lyrics.http_json = answering
            _sys.argv = ["lyrics.py", "Offline", "Song", "100"]
            with contextlib.redirect_stdout(io.StringIO()):
                lyrics.main()
            self.assertEqual(
                lyrics.cache_get(lyrics.cache_key("Offline", "Song", 100)),
                "not_found")
        finally:
            lyrics.http_json, lyrics.from_glassy = orig_http, orig_glassy
            _sys.argv = argv

    def test_real_http_json_records_an_answer(self):
        # The seam the negative-cache guard rides on: a parsed response bumps
        # net_answers, an unreachable host does not.
        import unittest.mock as mock
        lyrics.net_answers = 0
        fake_response = mock.MagicMock()
        fake_response.read.return_value = b'{"ok": 1}'
        fake_response.__enter__ = lambda s: fake_response
        fake_response.__exit__ = lambda s, *a: False
        with mock.patch.object(lyrics.urllib.request, "urlopen", return_value=fake_response):
            self.assertEqual(lyrics.http_json("http://x"), {"ok": 1})
        self.assertEqual(lyrics.net_answers, 1)
        with mock.patch.object(lyrics.urllib.request, "urlopen", side_effect=OSError("no route")):
            self.assertIsNone(lyrics.http_json("http://x"))
        self.assertEqual(lyrics.net_answers, 1)

    def test_main_serves_the_second_call_from_cache(self):
        import io, contextlib, sys as _sys
        calls = {"n": 0}
        def counting(url):
            calls["n"] += 1
            return {"lyrics": "[00:01.0]hi", "format": "lrc"} if "unison" in url else None
        orig_http, orig_glassy = lyrics.http_json, lyrics.from_glassy
        lyrics.from_glassy = lambda *a, **k: None
        lyrics.http_json = counting
        argv = _sys.argv
        try:
            for _ in range(2):
                _sys.argv = ["lyrics.py", "Provider", "Sleep Token", "222"]
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    lyrics.main()
                self.assertTrue(json.loads(out.getvalue())["ok"])
            first_call_count = calls["n"]
            # A third identical call still adds nothing: the network ran once.
            _sys.argv = ["lyrics.py", "Provider", "Sleep Token", "222"]
            with contextlib.redirect_stdout(io.StringIO()):
                lyrics.main()
            self.assertEqual(calls["n"], first_call_count)
            self.assertGreater(first_call_count, 0)
        finally:
            lyrics.http_json, lyrics.from_glassy = orig_http, orig_glassy
            _sys.argv = argv


if __name__ == "__main__":
    unittest.main()
