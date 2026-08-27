#!/usr/bin/env python3
"""The Phone tab's pages, feature cards and settings page against what the
services and the config schema actually declare.

The rule this exists for is one sentence: **a button whose call no service
answers is a fake action.** `tests/test_phone_connect_contract.py` states it
for the right sidebar's dialog with a hand-written allowlist; the surfaces
here reach five services and a whole config subtree, so the allowlist is
DERIVED - every `PhoneX.member` in the surface is resolved against the
properties, functions and signals `services/PhoneX.qml` declares, and every
`Config.options.phone.*` path against `Config.qml`'s own block.

That is not hypothetical tidiness. The sibling fork's cards offer a phone
screenshot, a phone power toggle and a "hear yourself" loopback; our
PhoneScrcpy and PhoneMic answer none of the three (PhoneMic only ever
*unloads* a `module-loopback`, it never loads one), and the fork's webcam and
microphone pages carry a frame rate, a bitrate and three audio-effect
switches whose keys this schema does not declare - a control bound to an
undeclared key reads `undefined`, takes its fallback for ever, and is
destroyed by the JsonAdapter's first write (AGENT.md, The Config system).
Each of those is one copied block away from shipping.

The rest pins the seams this workstream owns but does not control:

- the pages are rooted on `PhoneSubPage`, which W5a owns and which does not
  exist in this checkout. The interface they are written against lives in a
  local stub under tests/imports/ - never a second copy under modules/, which
  would be exactly the dead-copy hazard lint_no_stale_widget_canvas.py exists
  to fail on;
- `PhoneFeatureCards` announces `openPage(id)` and reads nothing off the tab
  that hosts it;
- every state key phone_cards.js can answer with has an arm at the call site,
  because an unmapped key is a card drawing an empty line;
- the install guide copies through a constant argv, never a shell string.

Static, because none of this is reachable from qmltestrunner: it can build
neither a RippleButton nor a laid-out box. The decisions these files make are
driven by tests/tst_phone_cards.qml.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SURFACE = ROOT / "modules/imi/sidebarLeft/phone"
SETTINGS_PAGE = ROOT / "modules/imi/settings/pages/PhoneConfig.qml"
SETTINGS_CONTENT = ROOT / "modules/imi/settings/SettingsContent.qml"
CARDS_JS = SURFACE / "phone_cards.js"
SUBPAGE_STUB = ROOT / "tests/imports/qs/modules/imi/sidebarLeft/phone/PhoneSubPage.qml"
SERVICES = ROOT / "services"

SERVICE_NAMES = ("PhoneConnect", "PhoneDeps", "PhoneScrcpy", "PhoneCamera",
                 "PhoneMic", "PhoneContacts", "PhoneNotifications")

# The four pages, and the two composites. `phone_cards.js` is the arithmetic.
PAGES = ("PhoneContactsPage.qml", "PhoneAppsPage.qml",
         "PhoneWebcamPage.qml", "PhoneMicPage.qml")
CARD_FILES = ("PhoneFeatureCard.qml", "PhoneFeatureCards.qml", "InstallGuidePopup.qml")

MEMBER_USE = re.compile(r"\b(" + "|".join(SERVICE_NAMES) + r")\s*\.\s*(\w+)")
CONFIG_USE = re.compile(r"\bConfig\.options\.phone\??((?:\.\??\w+)+)")

DECLARED_MEMBER = re.compile(
    r"^\s*(?:readonly\s+)?property\s+(?:alias\s+)?[\w<>]+\s+(\w+)\s*[:{]"
    r"|^\s*function\s+(\w+)\s*\("
    r"|^\s*signal\s+(\w+)\b",
    re.M)

# What a Qt object gives every QML type for free, plus the two the surfaces
# read off a Singleton root. Anything else has to be declared by the service.
BUILTIN_MEMBERS = frozenset({"objectName", "parent", "children", "data"})


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def surface_sources():
    """(name, comment-stripped source) for everything this workstream owns."""
    for path in sorted(SURFACE.glob("*.qml")):
        yield path.name, strip_comments(path.read_text(encoding="utf-8"))
    yield SETTINGS_PAGE.name, strip_comments(SETTINGS_PAGE.read_text(encoding="utf-8"))


def declared_members(service: str) -> set:
    source = strip_comments((SERVICES / f"{service}.qml").read_text(encoding="utf-8"))
    names = set()
    for match in DECLARED_MEMBER.finditer(source):
        names.add(next(name for name in match.groups() if name))
    return names


def declared_config_paths() -> set:
    """Every leaf and branch under `Config.options.phone`, dotted.

    Brace-counted rather than indentation-matched: a check that bakes in an
    indent passes vacuously after any reformat."""
    source = strip_comments((ROOT / "modules/common/Config.qml").read_text(encoding="utf-8"))
    # There are two `phone` JsonObjects in that file - `sidebar.phone`, which
    # carries the tab's enable switch, and the top-level one this reads. The
    # top-level block is the least-indented of them; taking the first match
    # instead found `sidebar.phone` and reported every key on these pages as
    # undeclared.
    # `[ \t]*`, not `\s*`: `\s` matches a newline, so an indentation group
    # written that way swallows the blank lines above the match and reports the
    # LEAST-indented block as the deepest one.
    candidates = list(re.finditer(r"^([ \t]*)property JsonObject phone: JsonObject \{", source, re.M))
    assert candidates, "Config.qml declares no phone JsonObject"
    start = min(candidates, key=lambda match: len(match.group(1)))

    paths, stack, depth = set(), [], 1
    for line in source[start.end():].splitlines():
        nested = re.match(r"\s*property JsonObject (\w+): JsonObject \{", line)
        leaf = re.match(r"\s*property\s+[\w<>]+\s+(\w+)\s*:", line)
        prefix = [name for name, _ in stack]
        if nested:
            paths.add(".".join(prefix + [nested.group(1)]))
            stack.append((nested.group(1), depth))
        elif leaf:
            paths.add(".".join(prefix + [leaf.group(1)]))
        depth += line.count("{") - line.count("}")
        while stack and depth <= stack[-1][1]:
            stack.pop()
        if depth <= 0:
            break
    return paths


def answer_literals(source: str, function_name: str) -> set:
    """Every string a decision function in phone_cards.js can answer with.

    Every literal in the body rather than only `return "x"`: two of these are
    written as a ternary, and a check that saw only the statement form would
    report those functions as answering nothing at all - which passes."""
    body = re.search(rf"function {function_name}\(.*?\n\}}", source, re.S)
    assert body, f"phone_cards.js has no {function_name}()"
    # A key-shaped literal, not any quoted run: two of these bodies contain a
    # `String(x || "")` guard, and pairing quotes naively across it turns the
    # code between them into a "key" nothing could ever have an arm for.
    return set(re.findall(r'"([a-z][a-zA-Z_]*)"', body.group(0)))


class ServiceSurfaceTests(unittest.TestCase):
    """Nothing on these surfaces calls something no service answers."""

    @classmethod
    def setUpClass(cls):
        cls.declared = {name: declared_members(name) for name in SERVICE_NAMES}

    def test_every_service_member_the_surface_reads_is_declared(self):
        unknown = []
        seen = 0
        for file_name, source in surface_sources():
            for service, member in MEMBER_USE.findall(source):
                seen += 1
                if member in BUILTIN_MEMBERS:
                    continue
                if member not in self.declared[service]:
                    unknown.append(f"{file_name}: {service}.{member}")
        self.assertGreater(seen, 40, "the sweep found almost no service calls - "
                                     "the surface moved, or the pattern stopped matching")
        self.assertEqual(unknown, [], "these reach a service member nothing declares. A "
                                      "button whose call no service answers is a fake "
                                      "action; add it to the service or drop the control.")

    def test_the_forks_three_unanswerable_chips_are_not_here(self):
        """Named rather than swept, because each is one copied block away and
        each fails silently: the click lands, the binding throws a
        ReferenceError into the log, and nothing on screen changes."""
        for absent in ("adbScreenshot", "adbTogglePower", "toggleMonitor",
                       "monitorEnabled", "peakVolumePercent"):
            for file_name, source in surface_sources():
                self.assertNotIn(absent, source,
                                 f"{file_name} reaches {absent}, which no service here answers")

    def test_the_derivation_can_actually_fail(self):
        """A check that resolves everything would also resolve a typo."""
        self.assertNotIn("definitelyNotAMember", self.declared["PhoneScrcpy"])
        self.assertIn("launchMirror", self.declared["PhoneScrcpy"])
        self.assertIn("missingFor", self.declared["PhoneDeps"])
        self.assertIn("composeSms", self.declared["PhoneContacts"])
        self.assertIn("setAsDefaultInput", self.declared["PhoneMic"])
        self.assertIn("openPreview", self.declared["PhoneCamera"])


class ConfigSurfaceTests(unittest.TestCase):
    """Every phone config path a surface touches is declared in the schema."""

    @classmethod
    def setUpClass(cls):
        cls.paths = declared_config_paths()

    def test_the_schema_parse_found_the_block(self):
        for expected in ("showPeripheralCards", "contacts.favoriteIds",
                         "scrcpy.appMode.flexDisplay", "webcam.wifiIp",
                         "microphone.micGain"):
            self.assertIn(expected, self.paths, f"the schema parse missed {expected}")
        self.assertNotIn("webcam.fps", self.paths,
                         "this schema declares no webcam frame rate - if it grows one, "
                         "the pages may offer it")

    def test_no_surface_reads_a_key_the_schema_does_not_declare(self):
        unknown = []
        seen = 0
        for file_name, source in surface_sources():
            for tail in CONFIG_USE.findall(source):
                seen += 1
                path = tail.replace("?", "").lstrip(".")
                if path not in self.paths:
                    unknown.append(f"{file_name}: Config.options.phone.{path}")
        self.assertGreater(seen, 30, "the sweep found almost no config reads")
        self.assertEqual(unknown, [], "these bind an undeclared config key. An "
                                      "undeclared key reads `undefined`, takes its "
                                      "fallback for ever, and is destroyed by the "
                                      "JsonAdapter's first write.")


class SubPageContractTests(unittest.TestCase):
    """The seam with W5a: the pages are written against a host this checkout
    does not have, so what they assume about it is written down."""

    def test_the_shim_is_the_real_host_and_not_a_copy_of_it(self):
        """While the two halves were separate branches this was a hand-written
        stub; now that the host exists the shim must be a SYMLINK to it, the
        way tests/imports/qs/modules/imi/bar/ resolves its widgets. A second
        file of that name is the dead-copy hazard: the pages would be tested
        against one shape and drawn against another."""
        host = SURFACE / "PhoneSubPage.qml"
        self.assertTrue(host.is_file(), "W5a's PhoneSubPage.qml is missing")
        self.assertTrue(SUBPAGE_STUB.is_symlink(),
                        "the shim is a copy, not a symlink to the real host")
        self.assertEqual(SUBPAGE_STUB.resolve(), host.resolve(),
                         "the shim points somewhere other than the real host")

    def test_the_host_declares_the_interface_the_pages_use(self):
        # Comment-stripped: the stub's own header names every one of these,
        # and a check that reads the prose passes on a stub whose code has
        # lost them - planted, `signal back` renamed to `signal notBack` was
        # green until this line.
        host = strip_comments((SURFACE / "PhoneSubPage.qml").read_text(encoding="utf-8"))
        self.assertRegex(host, r"property string title", "no `title` on the host")
        self.assertRegex(host, r"signal back\b", "no `back()` on the host")
        self.assertRegex(host, r"default property alias \w+:",
                         "the host has no default content slot")
        self.assertRegex(host, r"ColumnLayout \{",
                         "the content slot must be a ColumnLayout - the pages state "
                         "their size with Layout.* and would warn about anchors "
                         "inside anything else")

    def test_every_page_is_rooted_on_the_host(self):
        for name in PAGES:
            source = strip_comments((SURFACE / name).read_text(encoding="utf-8"))
            root = re.search(r"^(\w+) \{", source, re.M)
            self.assertIsNotNone(root, f"{name}: no root object found")
            self.assertEqual(root.group(1), "PhoneSubPage",
                             f"{name} is not rooted on PhoneSubPage")

    def test_every_page_says_where_the_host_comes_from(self):
        """The next reader will look for PhoneSubPage.qml in this directory and
        not find it."""
        for name in PAGES:
            source = (SURFACE / name).read_text(encoding="utf-8")
            header = source[:source.index("PhoneSubPage {")]
            self.assertIn("W5a", header,
                          f"{name}'s header does not say who owns PhoneSubPage")


class FeatureCardsContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.cards = strip_comments((SURFACE / "PhoneFeatureCards.qml").read_text(encoding="utf-8"))
        cls.card = strip_comments((SURFACE / "PhoneFeatureCard.qml").read_text(encoding="utf-8"))
        cls.js = strip_comments(CARDS_JS.read_text(encoding="utf-8"))

    def test_the_stack_announces_a_page_and_names_only_the_two_that_exist(self):
        self.assertRegex(self.cards, r"signal openPage\(string id\)",
                         "PhoneFeatureCards does not declare openPage(string id)")
        emitted = set(re.findall(r"root\.openPage\(\"(\w+)\"\)", self.cards))
        self.assertEqual(emitted, {"webcam", "mic"},
                         f"openPage is raised with {sorted(emitted)}; the tab hosts "
                         f"only the webcam and microphone pages")

    def test_the_stack_reads_nothing_off_the_tab_that_hosts_it(self):
        """It is placed last in the tab's column and must stay placeable
        anywhere. `parent` is reached exactly once, to reparent the install
        guide onto the window's own content item."""
        # An anchor side is geometry, not a read of what the tab holds.
        anchor_sides = {"left", "right", "top", "bottom", "width", "height",
                        "horizontalCenter", "verticalCenter", "fill"}
        reaches = [use for use in re.findall(r"\bparent\s*\.\s*(\w+)", self.cards)
                   if use not in anchor_sides]
        self.assertEqual(reaches, [], f"the stack reaches into its parent: {reaches}")
        self.assertIn("Window.contentItem", self.cards,
                      "the install guide is not reparented onto the window's content "
                      "item, so it would be drawn inside a 200px card stack")

    def test_a_card_talks_to_no_service_at_all(self):
        """The card is the drawn thing; PhoneFeatureCards is the one place a
        click becomes a call. Keeping them apart is what makes the derived
        allowlist above worth having."""
        for service in SERVICE_NAMES:
            self.assertNotIn(f"{service}.", self.card,
                             f"PhoneFeatureCard reaches {service} directly")
        for name in ("clicked", "settingsClicked", "stopClicked"):
            self.assertRegex(self.card, rf"signal {name}\b", f"the card has no {name} signal")

    def test_every_state_key_the_arithmetic_can_answer_with_has_an_arm(self):
        """An unmapped key draws an empty line, which reads as a card with
        nothing to say rather than as a bug. One key per switch may ride the
        `default:` arm; a second one cannot."""
        for function_name in ("mirrorTitleKey", "mirrorSubtitleKey", "webcamTitleKey",
                              "webcamSubtitleKey", "micTitleKey", "micSubtitleKey"):
            keys = answer_literals(self.js, function_name)
            self.assertTrue(keys, f"{function_name} returns no keys")
            uncovered = {key for key in keys
                         if f'case "{key}":' not in self.cards
                         and f'=== "{key}"' not in self.cards}
            self.assertLessEqual(
                len(uncovered), 1,
                f"{function_name} can answer with {sorted(uncovered)}, and "
                f"PhoneFeatureCards.qml has an arm for none of them")

    def test_the_five_rungs_are_the_ones_the_card_draws(self):
        rungs = answer_literals(self.js, "cardState")
        self.assertEqual(rungs, {"unavailable", "offline", "connecting", "ready", "active"})
        for rung in ("unavailable", "offline", "connecting", "active"):
            self.assertIn(f'"{rung}"', self.card,
                          f"the card draws nothing different for the {rung} rung")

    def test_the_card_names_its_state_property_something_item_state_is_not(self):
        """A `property string state` shadows Item.state, which drives States and
        Transitions - a typo elsewhere then silently becomes a state name that
        matches nothing."""
        self.assertRegex(self.card, r"property string cardState:")
        self.assertNotRegex(self.card, r"property string state\b")


class InstallGuideContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.guide = strip_comments((SURFACE / "InstallGuidePopup.qml").read_text(encoding="utf-8"))
        cls.js = strip_comments(CARDS_JS.read_text(encoding="utf-8"))

    def test_the_copy_is_a_constant_argv_and_the_directory_spawns_no_shell(self):
        """The fork spelled this `bash -c "wl-copy '" + quote(text) + "'"`, so
        its own quoting helper is the only thing between an install command
        and a shell."""
        argv = re.search(r"function copyArgv\(.*?\n\}", self.js, re.S)
        self.assertIsNotNone(argv, "phone_cards.js has no copyArgv()")
        self.assertIn('"wl-copy"', argv.group(0))
        self.assertIn('"--"', argv.group(0),
                      "without a `--` a command beginning with a dash is read as a flag")
        self.assertIn("PhoneCards.copyArgv(", self.guide,
                      "the guide does not copy through the shared argv builder")
        for file_name, source in surface_sources():
            for shell in ('"bash"', '"sh"', '"bash", "-c"'):
                self.assertNotIn(shell, source, f"{file_name} spawns a shell")

    def test_the_guide_is_fed_by_the_probes_rather_than_by_its_own_table(self):
        """`missingFor(feature)` is the dependency table AND what the probes
        found. A second table here would list a dependency that is installed."""
        self.assertNotIn("pacman", self.guide, "the guide carries its own command table")
        self.assertNotIn("apt install", self.guide)
        self.assertRegex(self.guide, r"property var dependencies:",
                         "the guide does not take its rows as data")
        cards = strip_comments((SURFACE / "PhoneFeatureCards.qml").read_text(encoding="utf-8"))
        self.assertIn("PhoneDeps.missingFor(", cards)

    def test_the_distro_pills_and_their_preselection_come_from_the_arithmetic(self):
        self.assertIn("PhoneCards.distroPills()", self.guide)
        self.assertIn("PhoneCards.initialDistro(", self.guide)
        self.assertIn("PhoneDeps.recheck()", strip_comments(
            (SURFACE / "PhoneFeatureCards.qml").read_text(encoding="utf-8")))


class SettingsPageTests(unittest.TestCase):
    """Settings > Devices & Phone: registered, addressable, and on the row
    grammar Settings > Capture is the reference for."""

    @classmethod
    def setUpClass(cls):
        cls.page = strip_comments(SETTINGS_PAGE.read_text(encoding="utf-8"))
        cls.content = SETTINGS_CONTENT.read_text(encoding="utf-8")

    def test_the_page_is_registered_with_a_stable_id_and_its_file_exists(self):
        entry = re.search(r'\{[^{}]*id: "devices-phone"[^{}]*\}', self.content)
        self.assertIsNotNone(entry, "no devices-phone entry in the settings catalogue")
        self.assertIn('Qt.resolvedUrl("pages/PhoneConfig.qml")', entry.group(0))
        self.assertIn("Translation.tr(", entry.group(0),
                      "the page's NAME must be translated; only its id is a literal")

    def test_the_page_scrolls_to_a_section_through_the_shared_helper(self):
        self.assertIn("function goTo(term)", self.page)
        self.assertIn("page.scrollToY(", self.page)
        self.assertNotIn("page.contentY =", self.page,
                         "a direct contentY write snaps under momentum scrolling")

    def test_every_toggle_row_carries_an_icon_chip(self):
        rows = re.findall(r"ConfigSwitch \{[^}]*?\}", self.page, re.S)
        self.assertGreaterEqual(len(rows), 10, "the page lost most of its switches")
        for row in rows:
            self.assertIn("iconChip: true", row,
                          f"a toggle row has no icon chip:\n{row[:160]}")

    def test_every_choice_option_carries_an_icon_and_a_label(self):
        for row in re.finditer(r"ConfigSelectionArray \{(.*?)\n {16}\}", self.page, re.S):
            options = re.search(r"options:\s*\[(.*?)\n\s*\]", row.group(1), re.S)
            self.assertIsNotNone(options, "a choice row declares no options")
            entries = re.findall(r"\{[^{}]*\}", options.group(1))
            self.assertTrue(entries, "no option entries parsed")
            for entry in entries:
                self.assertRegex(entry, r'\bicon:\s*"[a-z0-9_]+"',
                                 f"an option has no icon: {entry}")
                self.assertRegex(entry, r"\bdisplayName:\s*Translation\.tr\(",
                                 f"an option has no translated label: {entry}")

    def test_the_dropdown_says_which_choice_is_recommended(self):
        combos = re.findall(r"ConfigComboBox \{.*?\n {20}\}", self.page, re.S)
        self.assertEqual(len(combos), 1, "the page has one dropdown, the bitrate")
        self.assertEqual(combos[0].count("recommended: true"), 1)
        self.assertRegex(combos[0], r'buttonIcon:\s*"[a-z0-9_]+"')

    def test_every_text_field_floats_its_label(self):
        fields = re.findall(r"ConfigTextArea \{.*?\n {20}\}", self.page, re.S)
        self.assertGreaterEqual(len(fields), 2)
        for field in fields:
            self.assertIn("floatingLabel: true", field)

    def test_every_subsection_leads_with_an_icon(self):
        subsections = re.findall(r"ContentSubsection \{[^\n]*\n\s*icon:\s*\"[a-z0-9_]+\"", self.page)
        declared = self.page.count("ContentSubsection {")
        self.assertGreaterEqual(declared, 3)
        self.assertEqual(len(subsections), declared,
                         "a subsection on this page does not lead with an icon")

    def test_a_row_that_comes_and_goes_declares_rowVisible(self):
        """`visible` on a GroupedList row leaves a full-height empty plate."""
        self.assertIn("property bool rowVisible:", self.page)
        for row_type in ("ConfigSwitch", "ConfigTextArea", "ConfigSpinBox", "ConfigSelectionArray"):
            for block in re.findall(rf"{row_type} \{{(.*?)\n {{16,20}}\}}", self.page, re.S):
                self.assertNotRegex(block, r"^\s*visible:",
                                    f"a {row_type} row is gated with `visible`")

    def test_the_page_does_not_repeat_the_sub_pages_own_settings(self):
        """The webcam's and the microphone's settings live beside the toggle
        that starts them. Two pages writing one key is how the two come to
        disagree about what it means."""
        for key in ("webcam.cameraFacing", "webcam.resolution", "microphone.micGain"):
            self.assertNotIn(key, self.page,
                             f"Settings repeats {key}, which the sub-page owns")


if __name__ == "__main__":
    unittest.main(verbosity=1)
