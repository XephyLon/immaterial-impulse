#!/usr/bin/env python3
"""The screensaver's on-demand path: a key that reaches it, one monitor at a
time, and an idle inhibitor while a screen is deliberately dark.

Every one of these fails silently. An IPC verb nothing binds is a feature the
user cannot reach; a per-monitor blank that regresses the idle path leaves the
lock ladder wired to nothing; and an inhibitor acquired without a release path
keeps the machine awake for the rest of the session with nothing on screen to
explain it. None of it is reachable from qmltestrunner - the module is a Scope
of Quickshell types - so the wiring is pinned as a source contract and the set
arithmetic behind it lives in screensaver_screens.js (tst_screensaver_screens).
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HYPR = ROOT.parents[1] / "hypr"

SAVER = ROOT / "modules/imi/screensaver/Screensaver.qml"
IDLE = ROOT / "services/Idle.qml"
STATES = ROOT / "GlobalStates.qml"
KEYBINDS = HYPR / "hyprland/keybinds.lua"
HYPRIDLE = HYPR / "hypridle.conf"

SHORTCUT = "screensaverToggleMonitor"


def qml_function_body(src, name):
    """The body of `function <name>(...)` - brace matched, so a check about one
    verb cannot accidentally read its neighbour's body."""
    match = re.search(r"function\s+%s\s*\([^)]*\)\s*(?::\s*\w+\s*)?\{" % re.escape(name), src)
    assert match, f"no function {name}"
    depth, start = 0, match.end() - 1
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
    raise AssertionError(f"unterminated body for {name}")


def lua_bind_chunks(src):
    """(chord, chunk) for every `hl.bind("<chord>", ...)` in the file. `chunk`
    runs to the next bind, so a flag or dispatcher belonging to one bind is
    never read as another's."""
    chunks = []
    parts = src.split("hl.bind(")[1:]
    for part in parts:
        chord = re.match(r'\s*"([^"]*)"', part)
        if chord:
            chunks.append((chord.group(1), part))
    return chunks


class TheVerbsExist(unittest.TestCase):
    def setUp(self):
        self.saver = SAVER.read_text()

    def test_the_ipc_handler_still_answers_to_screensaver(self):
        self.assertIn('target: "screensaver"', self.saver)

    def test_the_idle_verbs_are_unchanged(self):
        for verb in ("function show(): void", "function hide(): void"):
            self.assertIn(verb, self.saver)

    def test_a_monitor_can_be_named(self):
        for verb in ("function showMonitor(name: string): void",
                     "function hideMonitor(name: string): void",
                     "function toggleMonitor(name: string): void"):
            self.assertIn(verb, self.saver,
                          "the per-monitor path has no IPC verb, so nothing "
                          "but the keybind can reach one screen")

    def test_the_per_monitor_verbs_write_the_screen_list(self):
        for verb, call in (("showMonitor", "root.showOn(name)"),
                           ("hideMonitor", "root.hideOn(name)"),
                           ("toggleMonitor", "root.toggleOn(name)")):
            self.assertIn(call, qml_function_body(self.saver, verb))


class TheKeybindExists(unittest.TestCase):
    def setUp(self):
        self.saver = SAVER.read_text()
        self.keybinds = KEYBINDS.read_text()

    def test_the_module_declares_a_global_shortcut(self):
        self.assertIn(f'name: "{SHORTCUT}"', self.saver,
                      "the IPC verbs shipped with nothing bound to them - the "
                      "gap this closes; a GlobalShortcut is how every other "
                      "module here is reachable from a key")

    def test_the_companion_config_binds_it(self):
        self.assertIn(f"quickshell:{SHORTCUT}", self.keybinds,
                      "a GlobalShortcut with no hl.bind() is as unreachable as "
                      "the IPC verbs were")

    def test_it_ships_bound_with_a_description(self):
        # Bound, not left for the user to discover: an unbound default is the
        # gap. Described, so it appears in the cheatsheet and in the keyboard
        # shortcuts editor, which is where a collision gets resolved.
        chords = [c for c, chunk in lua_bind_chunks(self.keybinds)
                  if f"quickshell:{SHORTCUT}" in chunk]
        self.assertEqual(len(chords), 1, f"expected one bind, got {chords}")
        chunk = next(chunk for c, chunk in lua_bind_chunks(self.keybinds)
                     if f"quickshell:{SHORTCUT}" in chunk)
        self.assertIn("description =", chunk)

    def test_the_chord_it_takes_is_not_already_taken(self):
        # "Check what is already taken" as a check rather than as a note. The
        # loop-generated binds are covered by the sibling test below.
        chords = [c for c, _ in lua_bind_chunks(self.keybinds)]
        ours = next(c for c, chunk in lua_bind_chunks(self.keybinds)
                    if f"quickshell:{SHORTCUT}" in chunk)
        self.assertEqual(chords.count(ours), 1,
                         f"{ours} is bound {chords.count(ours)} times")

    def test_no_generated_bind_can_produce_that_chord(self):
        # Several binds are built by concatenation in a loop
        # (`"SUPER + " .. arrowkey[i]`), so a literal scan cannot see them. What
        # they append comes from table literals in the same file, and every one
        # of those is a direction, a keypad code or a digit - never a bare
        # letter. If that stops holding, this chord needs re-checking by hand.
        tables = re.findall(r"\{\s*(\"[^\"]*\"(?:\s*,\s*\"[^\"]*\")*)\s*\}",
                            self.keybinds)
        suffixes = {s.strip().strip('"') for table in tables
                    for s in table.split(",")}
        ours = next(c for c, chunk in lua_bind_chunks(self.keybinds)
                    if f"quickshell:{SHORTCUT}" in chunk)
        key = ours.rsplit("+", 1)[-1].strip()
        self.assertNotIn(key, suffixes,
                         f"a generated bind appends {key!r}, so {ours} may "
                         "already be taken")

    def test_the_key_blanks_the_focused_monitor(self):
        # Focused, not "under the cursor": every other per-monitor surface here
        # (the OSDs, the desktop menu, the screen translator, the session
        # screen) resolves Hyprland.focusedMonitor, and a screensaver that
        # picked a different monitor than the rest of the shell would be its
        # own rule to remember.
        shortcut = self.saver[self.saver.index(f'name: "{SHORTCUT}"'):]
        shortcut = shortcut[:shortcut.index("IpcHandler")]
        self.assertIn("Hyprland.focusedMonitor?.name", shortcut)
        self.assertIn("root.toggleOn(", shortcut)

    def test_the_key_is_not_gated_on_the_idle_switch(self):
        # screensaver.enable arms hypridle's listener. Gating a key the user
        # just pressed on it would be a silent no-op with nothing to explain it,
        # so the gate belongs in show() and nowhere else.
        self.assertIn("Config.options.screensaver?.enable",
                      qml_function_body(self.saver, "show"))
        self.assertEqual(self.saver.count("screensaver?.enable"), 1)


class TheInhibitorIsAcquiredAndReleased(unittest.TestCase):
    def setUp(self):
        self.idle = IDLE.read_text()
        self.saver = SAVER.read_text()
        self.states = STATES.read_text()

    def test_the_state_the_hold_derives_from_exists(self):
        self.assertIn("property var screensaverScreens: []", self.states)

    def test_the_hold_is_ored_into_the_one_inhibitor(self):
        # One inhibitor, not a second IdleInhibitor of our own: Idle.qml's
        # window carries a comment about a 0x0 surface mapping unreliably, and
        # a second copy would have to re-learn that.
        self.assertIn("root.inhibit || root.autoInhibitActive || root.screensaverHold",
                      self.idle)
        self.assertEqual(self.idle.count("IdleInhibitor {"), 1)

    def test_the_hold_is_derived_and_so_has_no_release_path_to_forget(self):
        self.assertIn(
            "readonly property bool screensaverHold: GlobalStates.screensaverScreens.length > 0",
            self.idle)
        # A writer anywhere would make it a stored flag with a release path.
        for tree in ("modules", "services", "panelFamilies"):
            for path in (ROOT / tree).rglob("*.qml"):
                if path.is_file():
                    self.assertNotIn("screensaverHold =", path.read_text(), str(path))

    def test_it_does_not_fight_the_external_monitor_keep_awake(self):
        # Each input owns exactly one bit. toggleInhibit must keep writing only
        # the manual one, or a deliberate blank could flip the user's toggle.
        toggle = qml_function_body(self.idle, "toggleInhibit")
        self.assertNotIn("screensaverHold", toggle)
        self.assertNotIn("autoInhibitActive", toggle)
        self.assertIn("root.inhibit", toggle)
        self.assertIn("root.autoOnExternalMonitor && root.hasExternalMonitor", self.idle)

    def test_an_idle_raised_saver_holds_nothing(self):
        # The whole reason the two paths are separate state: a saver raised
        # because nobody is here must let the lock/DPMS/suspend ladder run.
        self.assertNotIn("screensaverActive", self.idle)

    def test_dismissing_a_deliberate_blank_releases_it(self):
        dismiss = qml_function_body(self.saver, "dismiss")
        self.assertIn("root.hideOn(screenLoader.modelData.name)", dismiss)

    def test_the_idle_resume_verb_releases_it_too(self):
        self.assertIn("GlobalStates.screensaverScreens = []",
                      qml_function_body(self.saver, "hide"))

    def test_an_unplugged_monitor_releases_it(self):
        # The delegate goes with the screen; the name would not, and the hold
        # is derived from the name.
        prune = qml_function_body(self.saver, "onScreensChanged")
        self.assertIn("ScreensaverScreens.pruned", prune)
        self.assertIn("GlobalStates.screensaverScreens = live", prune)


class ThePerMonitorPathDoesNotRegressTheIdlePath(unittest.TestCase):
    def setUp(self):
        self.saver = SAVER.read_text()
        self.hypridle = HYPRIDLE.read_text()

    def test_there_is_still_one_surface_per_screen(self):
        self.assertIn("model: Quickshell.screens", self.saver)

    def test_the_idle_flag_still_raises_every_one_of_them(self):
        self.assertIn("active: root.idleActive || screenLoader.deliberate", self.saver)

    def test_show_still_blanks_everything_and_names_no_monitor(self):
        show = qml_function_body(self.saver, "show")
        self.assertIn("GlobalStates.screensaverActive = true", show)
        self.assertNotIn("screensaverScreens", show,
                         "the idle verb must not enter the deliberate list, or "
                         "going idle would hold the inhibitor that stops the "
                         "session ever reaching the lock")

    def test_hypridle_still_drives_those_two_verbs(self):
        self.assertIn("ipc call screensaver show", self.hypridle)
        self.assertIn("ipc call screensaver hide", self.hypridle)

    def test_the_screensaver_still_fires_before_the_lock(self):
        timeouts = [int(t) for t in re.findall(r"timeout\s*=\s*(\d+)", self.hypridle)]
        self.assertEqual(timeouts[0], 240)
        self.assertLess(timeouts[0], timeouts[1])

    def test_only_the_idle_saver_takes_the_keyboard(self):
        # A deliberately blanked monitor with an exclusive keyboard grab would
        # swallow what the user types on the screen they moved to - and dismiss
        # itself on the first letter, which is the opposite of the feature.
        self.assertIn(
            "WlrLayershell.keyboardFocus: saverWindow.deliberate "
            "? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive",
            self.saver)

    def test_pointer_drift_does_not_take_down_a_deliberate_blank(self):
        # Getting back to work means moving the pointer off that monitor, which
        # is motion across this very surface.
        dismiss = qml_function_body(self.saver, "dismiss")
        self.assertIn("if (pointerMotion && saverWindow.deliberate)", dismiss)
        self.assertIn("onPositionChanged: saverWindow.dismiss(true)", self.saver)
        self.assertIn("onPressed: saverWindow.dismiss(false)", self.saver)

    def test_the_backdrop_is_still_black_on_both_paths(self):
        content = (ROOT / "modules/imi/screensaver/ScreensaverContent.qml").read_text()
        self.assertIn('color: "black"', content)


if __name__ == "__main__":
    unittest.main()
