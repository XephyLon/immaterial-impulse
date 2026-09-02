"""Offline contracts and golden metrics for the cheatsheet's typing test.

Ported from the p3drovfx fork, where the same surface is also a launcher
panel; here the cheatsheet is its only host, so the launcher/registry halves
are gone and the page's wiring into the cheatsheet's page list is pinned
instead. Paths: modules/imi/cheatsheet/typing/, services/Typing*.qml,
assets/typing/.
"""

from __future__ import annotations

import hashlib
import re
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def breakdown(target: str, entered: str) -> dict[str, int]:
    target_chars = list(target)
    entered_chars = list(entered)
    correct = sum(a == b for a, b in zip(target_chars, entered_chars))
    incorrect = min(len(target_chars), len(entered_chars)) - correct
    return {
        "correct": correct,
        "incorrect": incorrect,
        "extra": max(0, len(entered_chars) - len(target_chars)),
        "missed": max(0, len(target_chars) - len(entered_chars)),
    }


def wpm(characters: int, seconds: float) -> float:
    return characters / 5 / (seconds / 60) if seconds > 0 else 0


class TypingTestContractTests(unittest.TestCase):
    def test_the_page_is_one_entry_in_the_cheatsheets_page_list(self) -> None:
        """The tab bar and the SwipeView are drawn from one list, so a page
        that is on the switch cannot show under another page's tab."""
        cheatsheet = source("modules/imi/cheatsheet/Cheatsheet.qml")
        page = source("modules/imi/cheatsheet/CheatsheetTypingTest.qml")
        config = source("modules/common/Config.qml")
        settings = source("modules/imi/settings/pages/GeneralConfig.qml")
        self.assertIn('"component": typingTestPage', cheatsheet)
        self.assertIn("id: typingTestPage", cheatsheet)
        self.assertIn("readonly property var tabButtonList: cheatsheetRoot.pages.map(", cheatsheet)
        self.assertIn("model: cheatsheetRoot.pages", cheatsheet)
        # The frame is all the host page may own: no engine, no input sink, no
        # shortcut table of its own.
        self.assertIn("TypingTestSurface {", page)
        for banned in ("TypingTestEngine {", "TextInput {", "function handleShortcut"):
            self.assertNotIn(banned, page, banned)
        # It fits the screen the way the other two pages do, and learns that
        # it is on screen from the host rather than guessing at a SwipeView.
        for budget in ("maxContentHeight: cheatsheetRoot.pageHeightBudget",
                       "maxContentWidth: cheatsheetRoot.pageWidthBudget"):
            self.assertIn(budget, cheatsheet.split("id: typingTestPage", 1)[1].split("Component {", 1)[0], budget)
        self.assertIn("property bool tabActive", page)
        self.assertNotIn("swipeView.currentIndex", page)
        self.assertIn("property bool enableTypingTest: true", config)
        self.assertIn("Config.options.cheatsheet.enableTypingTest", settings)

    def test_nothing_in_the_test_snaps_in_or_out_on_state(self) -> None:
        """Gracefully entering and exiting: an element that comes and goes with
        the test's state is a Presence (or a FadeLoader), never a bare
        `visible:` on that state - a bare gate is a one-frame snap, and the
        results screen shipped as exactly that."""
        state = re.compile(r"engine\.|root\.page|restartArmed|isFinished|isRunning|hasTarget|state ===|options\.")
        for name in ("TypingTestSurface.qml", "TypingTestToolbar.qml"):
            text = source("modules/imi/cheatsheet/typing/" + name)
            for line_no, line in enumerate(text.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("visible:") and state.search(stripped):
                    self.fail(f"{name}:{line_no} gates visibility on state with a bare visible: {stripped}")
        surface = source("modules/imi/cheatsheet/typing/TypingTestSurface.qml")
        self.assertGreaterEqual(surface.count("Presence {"), 10)
        self.assertEqual(surface.count("FadeLoader {"), 3)
        # The stage and the score share one slot whose height eases, or the
        # cross-fade lands in a layout that still jumps between the two.
        self.assertIn("property real slotHeight:", surface)
        self.assertIn("Behavior on slotHeight", surface)
        presence = source("modules/common/widgets/Presence.qml")
        self.assertIn("visible: root.presence > 0", presence)
        self.assertIn("Behavior on presence", presence)

    def test_every_sound_effect_names_its_output(self) -> None:
        """A SoundEffect left on Qt's own default reports Ready and playing
        and opens no PipeWire stream on Qt 6.11 - measured with pactl: nothing
        for the bare effect, a `quickshell` stream on the default sink once
        audioDevice is MediaDevices.defaultAudioOutput."""
        player = source("modules/imi/cheatsheet/typing/TypingSounds.qml")
        effects = re.findall(r"SoundEffect \{(.*?)\n\s*\}", player, re.S)
        self.assertGreaterEqual(len(effects), 2)
        for body in effects:
            self.assertIn("audioDevice: outputs.defaultAudioOutput", body, body)
        self.assertIn("MediaDevices { id: outputs }", player)

    def test_config_declares_every_preference_the_settings_page_writes(self) -> None:
        config = source("modules/common/Config.qml")
        block = config.split("property JsonObject typingTest: JsonObject {", 1)[1]
        for key in (
            'property string language: "english_1k"',
            'property string mode: "time"',
            "property int fontSize:",
            "property int visibleLines:",
            "property string caretStyle:",
            "property bool highlightCurrentWord:",
            "property bool blindMode:",
            "property bool quickRestart:",
            "property bool finishOnLastWord:",
            "property JsonObject keyboard:",
            "property JsonObject sounds:",
            "property JsonObject history:",
        ):
            self.assertIn(key, block, key)
        # Every Config path the ported files read has to be declared under
        # cheatsheet.typingTest, or it reads undefined for ever.
        leaves = set()
        for path in sorted((ROOT / "modules/imi/cheatsheet/typing").glob("*.qml")):
            leaves |= set(re.findall(r"Config\.options\.cheatsheet\.typingTest\.([a-zA-Z.]+)", path.read_text(encoding="utf-8")))
        for leaf in sorted(leaves):
            name = leaf.split(".")[-1]
            self.assertRegex(block, r"property \w+(?:<\w+>)? " + re.escape(name) + r"\b", leaf)
        self.assertNotIn("Config.options.search.typingTest", "\n".join(
            p.read_text(encoding="utf-8") for p in (ROOT / "modules/imi/cheatsheet").rglob("*.qml")))
        # The enum has to list exactly the packs the assets ship.
        manifest = json.loads(
            (ROOT / "assets" / "typing" / "sounds-manifest.json").read_text(encoding="utf-8"))
        self.assertIn(manifest["clickPacks"][0]["id"], block)

    def test_history_is_bounded_local_and_aggregate_only(self) -> None:
        persistent = source("modules/common/Persistent.qml")
        history = source("modules/imi/cheatsheet/typing/TypingHistory.qml")
        self.assertIn("property JsonObject typingTest: JsonObject {", persistent)
        self.assertIn("property list<var> recentResults: []", persistent)
        self.assertIn("property list<var> personalBests: []", persistent)
        # Bounded, opt-out, and never storing what was typed.
        self.assertIn("Config.options.cheatsheet.typingTest.history.enable", history)
        self.assertIn("maxEntries", history)
        # Lifetime totals outlive the capped result list, and the activity
        # tally is bounded rather than derived from keeping every result.
        for field in ("testsStarted", "testsCompleted", "secondsTyping", "activity"):
            self.assertIn(field, persistent, field)
            self.assertIn(field, history, field)
        self.assertIn("activityWindowDays", history)
        # Clearing has to take the totals with it, not just the list.
        cleared = history.split("function clear()", 1)[1]
        for field in ("recentResults", "personalBests", "testsStarted",
                      "testsCompleted", "secondsTyping", "activity"):
            self.assertIn(field, cleared, field)


    def test_stats_page_only_reads_history(self) -> None:
        """It can be opened mid-session, so it must not be able to alter one."""
        stats = source("modules/imi/cheatsheet/typing/TypingStatsPage.qml")
        surface = source("modules/imi/cheatsheet/typing/TypingTestSurface.qml")
        self.assertIn("TypingHistory", stats)
        for banned in ("TypingTestEngine", "Persistent.states", "TypingHistory.record",
                       "TypingHistory.clear", "TypingHistory.registerStart"):
            self.assertNotIn(banned, stats, banned)
        self.assertIn("TypingStatsPage {}", surface)
        # A StyledToolTip reads `parent.hovered`; on a plain Rectangle that is
        # `undefined`, which the tooltip treats as hovered — 371 day cells each
        # showed their tooltip the moment the page opened.
        self.assertNotIn("StyledToolTip {", stats)
        # A card's content holder must be a layout: a plain Item takes no
        # implicit height from its children, so the card collapses and its
        # content lands on top of the next section.
        card = stats.split("component Card:", 1)[1].split("component ", 1)[0]
        self.assertIn("ColumnLayout", card)
        self.assertNotIn("Item {", card)
        # The engine announces the start; the surface is what persists it.
        engine = source("modules/imi/cheatsheet/typing/TypingTestEngine.qml")
        self.assertIn("signal started", engine)
        self.assertNotIn("Persistent", engine)
        self.assertIn("onStarted: TypingHistory.registerStart()", surface)
        engine = source("modules/imi/cheatsheet/typing/TypingTestEngine.qml")
        payload = engine.split("function resultPayload()", 1)[1].split("function ", 1)[0]
        for banned in ("inputText", "targetText", "targetWords"):
            self.assertNotIn(banned, payload, banned)


    def test_surface_owns_every_documented_shortcut(self) -> None:
        panel = source("modules/imi/cheatsheet/typing/TypingTestSurface.qml")
        for key in (
            "Qt.Key_R",
            "Qt.Key_Comma",
            "Qt.Key_H",
            "Qt.Key_L",
            "Qt.Key_Backspace",
            "Qt.Key_BracketLeft",
            "Qt.Key_BracketRight",
            "Qt.Key_P",
            "Qt.Key_N",
            "Qt.Key_Tab",
            "Qt.Key_S",
        ):
            self.assertIn(key, panel, key)
        # Tab points at restart and Enter presses it.
        self.assertIn("restartArmed", panel)
        # Escape closes an in-panel page before it leaves the panel.
        self.assertIn("function handleEscape()", panel)
        self.assertIn('root.page !== "test"', panel)


    def test_keyboard_preview_rows_are_complete(self) -> None:
        layouts = source("modules/imi/cheatsheet/typing/TypingKeyboardLayouts.qml")
        for layout in ("qwerty", "qwertz", "azerty", "dvorak", "colemak"):
            self.assertIn(f"{layout}: [", layouts)


    def test_vendored_sounds_are_attributed_and_checksummed(self) -> None:
        assets = ROOT / "assets" / "typing"
        manifest = json.loads((assets / "sounds-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["source"], "monkeytypegame/monkeytype")
        self.assertEqual(manifest["license"], "GPL-3.0-only")
        # A pinned, immutable commit — never a branch name.
        self.assertRegex(manifest["upstreamCommit"], r"^[0-9a-f]{40}$")
        self.assertGreaterEqual(len(manifest["clickPacks"]), 4)
        self.assertGreaterEqual(len(manifest["errorPacks"]), 1)
        for pack in manifest["clickPacks"] + manifest["errorPacks"]:
            self.assertTrue(pack["label"], pack["id"])
            self.assertEqual(len(pack["files"]), len(pack["sha256"]), pack["id"])
            for name, digest in pack["sha256"].items():
                path = assets / "sounds" / pack["id"] / name
                self.assertTrue(path.is_file(), str(path))
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest, str(path))
                self.assertEqual(path.read_bytes()[0:4], b"RIFF", str(path))


    def test_sound_sync_script_is_development_only_and_pinned(self) -> None:
        script = source("scripts/typing/sync_monkeytype_sounds.py")
        self.assertIn("--commit", script)
        self.assertIn("--check", script)
        self.assertIn("raw.githubusercontent.com/monkeytypegame/monkeytype", script)
        self.assertIn("sha256", script)
        self.assertNotIn("import Quickshell", script)
        # It writes assets; it must never run what it downloaded.
        for banned in ("subprocess", "os.system", "eval("):
            self.assertNotIn(banned, script, banned)


    def test_sound_playback_is_local_and_manifest_driven(self) -> None:
        packs = source("services/TypingSoundPacks.qml")
        player = source("modules/imi/cheatsheet/typing/TypingSounds.qml")
        self.assertIn("sounds-manifest.json", packs)
        self.assertNotIn("https://", packs)
        # The pool costs an audio thread, so it only exists once enabled.
        self.assertIn("active: root.soundEnabled", player)
        self.assertIn("SoundEffect", player)


    def test_runtime_is_local_and_input_path_has_no_process(self) -> None:
        runtime = "\n".join(
            source(path)
            for path in (
                "modules/imi/cheatsheet/CheatsheetTypingTest.qml",
                "modules/imi/cheatsheet/typing/TypingTestSurface.qml",
                "modules/imi/cheatsheet/typing/TypingTestEngine.qml",
                "modules/imi/cheatsheet/typing/TypingWordViewport.qml",
                "modules/imi/cheatsheet/typing/TypingSounds.qml",
                "modules/imi/cheatsheet/typing/TypingHistory.qml",
                "services/TypingLanguages.qml",
            )
        )
        self.assertNotIn("Process {", runtime)
        self.assertNotIn("https://", runtime)
        self.assertNotIn("http://", runtime)
        self.assertIn("TextInput", runtime)
        self.assertIn("onTextEdited", runtime)
        self.assertIn("Date.now()", runtime)


    def test_assets_are_attributed_and_manifest_checksums_match(self) -> None:
        assets = ROOT / "assets" / "typing"
        self.assertTrue((assets / "ATTRIBUTION.md").is_file())
        manifest = json.loads((assets / "languages-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["source"], "monkeytypegame/monkeytype")
        self.assertEqual(manifest["license"], "GPL-3.0-only")
        self.assertEqual(len(manifest["languages"]), 7)
        for language in manifest["languages"]:
            pack_path = assets / language["file"]
            self.assertTrue(pack_path.is_file(), language["id"])
            encoded = pack_path.read_bytes()
            self.assertEqual(hashlib.sha256(encoded).hexdigest(), language["sha256"])
            pack = json.loads(encoded)
            self.assertIsInstance(pack["words"], list)
            # Upstream's base packs are ~200 words, which ran out of variety
            # long before a 120-second test did. Every language ships the 1k
            # list, so no language is thinner than the rest.
            self.assertGreaterEqual(len(pack["words"]), 900, language["id"])
            self.assertEqual(len(pack["words"]), language["wordCount"], language["id"])
            self.assertEqual(len(set(pack["words"])), len(pack["words"]), language["id"])
            self.assertTrue(all(isinstance(word, str) and word for word in pack["words"]))


    def test_golden_metrics(self) -> None:
        self.assertEqual(breakdown("hello world", "hello world"), {
            "correct": 11, "incorrect": 0, "extra": 0, "missed": 0,
        })
        self.assertEqual(breakdown("hello world", "hello xorld"), {
            "correct": 10, "incorrect": 1, "extra": 0, "missed": 0,
        })
        self.assertEqual(breakdown("hello", "hellooo"), {
            "correct": 5, "incorrect": 0, "extra": 2, "missed": 0,
        })
        self.assertEqual(breakdown("hello world", "hello wo"), {
            "correct": 8, "incorrect": 0, "extra": 0, "missed": 3,
        })
        self.assertEqual(wpm(50, 60), 10)
        self.assertEqual(wpm(50, 0), 0)


    def test_sync_script_is_development_only_and_pinned(self) -> None:
        script = source("scripts/typing/sync_monkeytype_languages.py")
        self.assertIn("--commit", script)
        # A pack that comes back thin means the upstream file moved; the sync
        # must fail rather than quietly ship a stub.
        self.assertIn("MINIMUM_WORDS", script)
        self.assertIn("_1k.json", script)
        self.assertIn("raw.githubusercontent.com/monkeytypegame/monkeytype", script)
        self.assertIn("sha256", script)
        self.assertNotIn("import Quickshell", script)




if __name__ == "__main__":
    unittest.main()
