#!/usr/bin/env python3
"""The Components gallery lists every control that inherits the press morph.

`CheatsheetComponents.qml` exists so a change to a SHARED interaction token can
be reviewed against the controls it reaches, rather than one screenshot at a
time. That argument holds only while the catalogue is COMPLETE: a gallery
missing eight of the types a token moves is worse than none, because it looks
like the whole answer.

So the set it must cover is defined structurally rather than by hand - every
type whose root is `RippleButton`, plus every type whose root is one of those,
transitively. That is the set `Appearance.interaction.pressRadiusScale` and
`hoverScale` reach, it is the set that grows silently when someone adds a
button, and it is computable from the tree.

Two checks, in both directions:

  - every such type appears in the catalogue, or is listed in EXCLUDED with a
    reason. An exclusion is a sentence, not a flag: "it is vendored" and "it
    cannot be built" are different facts and the next reader needs to know
    which one applied;
  - every path the catalogue names exists. A rename that misses this file
    leaves a tile that reports "cannot be built" for ever, and a tile that
    fails is exactly what the gallery uses to say "this type needs its
    surroundings" - so the two failures are indistinguishable on screen.

The broader widget library is a CURATED selection in that file, not a checked
one: most of `modules/common/widgets` is layout scaffolding, loaders and
motion helpers with nothing to demo, and a lint over that set would be an
exclusion list with 140 entries nobody reads.
"""
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHELL = HERE.parent
GALLERY = SHELL / "modules/imi/cheatsheet/CheatsheetComponents.qml"
BASE = "RippleButton"

# Directory prefix -> why everything under it is out. A whole family of
# near-identical presets is noise in a gallery, not coverage: the thing a
# reviewer needs to see is the TYPE they all inherit, and that has its own tile.
EXCLUDED_DIRS = {
    "modules/imi/sidebarRight/quickToggles": (
        "each file here is one concrete toggle - Wi-Fi, Bluetooth, VPN, night "
        "light - built on QuickToggleButton or AndroidQuickToggleButton, and "
        "BOTH of those are in the gallery. Thirty-two tiles of the same shape "
        "with different glyphs would bury the sixty that differ, and most of "
        "them would draw `needs its surroundings` anyway because a toggle "
        "without its service has nothing to show. They joined this lint's set "
        "the day GroupButton was re-rooted on RippleButton, which is the lint "
        "working: the press morph really does reach them now."
    ),
}

# Path relative to the shell root -> why it is not in the gallery.
EXCLUDED = {
    "modules/common/plugins/designsystem/widgets/M3IconButton.qml":
        "vendored designsystem mirror - a second copy of a shipped widget, "
        "listing it would show the same control twice under two names",
    "modules/common/plugins/designsystem/widgets/NotificationActionButton.qml":
        "vendored designsystem mirror of the shipped NotificationActionButton",
    "modules/common/plugins/designsystem/widgets/NotificationGroupExpandButton.qml":
        "vendored designsystem mirror of the shipped NotificationGroupExpandButton",
    "modules/common/widgets/PassiveRippleSurface.qml":
        "not a control: the pressed LOOK of one that keeps its own input (a "
        "ComboBox, a list row). It receives no press, so a tile of it would "
        "be a rectangle that answers nothing; the combo box tile shows it",
    "modules/imi/bar/LeftSidebarButton.qml":
        "a bar widget the layout names by id (`leftSidebarButton`); it opens "
        "the sidebar from its own press, which the gallery's dumb rule "
        "(lint_dumb_widgets.py) forbids a tile to do. It WAS a tile, and was "
        "deleted as an orphan on the strength of that - but a layout id is a "
        "consumer, and the maintainer's bar had it in the first slot",
    "modules/imi/bar/PowerButton.qml":
        "the same: `powerButton` in a layout, opens the session menu on press",
    "modules/imi/bar/DockerPlugin.qml":
        "the same shape again: `plugin:docker_plugin` in a layout, reads the "
        "Docker service for its gauge and count and opens its container popup "
        "on press. It joined this set the day it became a RippleButton so a "
        "click has a press - the lint working, as with the quick toggles",
    "modules/imi/dock/DockAppButton.qml":
        "a dock entry is a running window's button - it takes a toplevel and "
        "an app id, and a bare one is an empty square that teaches nothing",
}


def qml_files():
    for path in SHELL.rglob("*.qml"):
        if "/tests/" in str(path):
            continue
        yield path


def root_type(path):
    """The type a QML file's root object declares, or None.

    The root is the first non-comment, non-import line opening a brace at
    column zero. Reading it textually rather than parsing is enough here
    because the shape is uniform in this tree, and a miss fails OPEN - the
    type is simply not counted as a descendant.
    """
    for line in path.read_text(errors="replace").splitlines():
        match = re.match(r"^([A-Z][A-Za-z0-9_]*)\s*\{", line)
        if match:
            return match.group(1)
    return None


def descendants_of(base):
    """Every type rooted on `base`, transitively, as shell-relative paths."""
    roots = {}
    for path in qml_files():
        root = root_type(path)
        if root:
            roots[path] = root

    family = {base}
    found = {}
    changed = True
    while changed:
        changed = False
        for path, root in roots.items():
            if root in family and path.stem not in family:
                family.add(path.stem)
                changed = True
        for path, root in roots.items():
            if root in family:
                found[str(path.relative_to(SHELL))] = root
    return found


def strip_comments(text):
    # Only a `//` after whitespace is a comment. The first version stripped
    # every `//`, which took `//example.invalid" }` off a URL prop - the entry
    # never closed, swallowed its neighbour, and inherited that neighbour's
    # `toggles: true`.
    return re.sub(r"(^|\s)//.*", r"\1", text)


def catalogue_entries():
    """Each `{ type: ... }` entry as its own balanced text, with what follows it.

    Returns [(entry_text, tail)] where `tail` is the run of characters between
    the entry's closing brace and the next `{`, `]` or end of file. Both halves
    are read: the entry for its claims, the tail for whether the entry really
    ended where its brace did.
    """
    text = strip_comments(GALLERY.read_text())
    found = []
    pos = 0
    while True:
        start = text.find('{ type: "', pos)
        if start < 0:
            return found
        depth = 0
        end = None
        for index in range(start, len(text)):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is None:
            return found
        stop = re.search(r"[{\]]", text[end:])
        tail = text[end:end + stop.start()] if stop else text[end:]
        found.append((text[start:end], tail))
        pos = end


def toggle_claims():
    """{path: whether the catalogue says this type is a toggle}."""
    # Read off the balanced entry, not the line or the text up to a `},`:
    # an entry may wrap, and its props are a nested object whose own `},`
    # is the first one a naive scan meets. Both earlier readings were wrong
    # in ways that read a real claim as absent.
    claims = {}
    for entry, _ in catalogue_entries():
        path = entry.split('"', 2)[1]
        claims[path] = re.search(r"\btoggles:\s*true\b", entry) is not None
    return claims


def source_of(path):
    return re.sub(r"//.*", "", (SHELL / path).read_text(errors="replace"))


def declares_toggled(path):
    return re.search(r"\bproperty\s+bool\s+toggled\b", source_of(path)) is not None


def reads_toggled(path):
    return re.search(r"\btoggled\b", source_of(path)) is not None


def catalogued():
    text = GALLERY.read_text()
    return set(re.findall(r'type:\s*"([^"]+)"', text))


class ComponentGalleryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.listed = catalogued()
        cls.family = descendants_of(BASE)

    @staticmethod
    def excluded_by_dir(path):
        return any(path.startswith(prefix + "/") for prefix in EXCLUDED_DIRS)

    def test_every_press_morphing_control_is_in_the_gallery(self):
        missing = sorted(
            path for path in self.family
            if path not in self.listed and path not in EXCLUDED
            and not self.excluded_by_dir(path)
        )
        self.assertEqual(missing, [], "\n".join([
            "These inherit the press morph but are not in the Components gallery.",
            "Add a tile for each, or add it to EXCLUDED here WITH A REASON:",
            *(f"  {path}" for path in missing),
        ]))

    def test_every_exclusion_names_a_real_file(self):
        stale = sorted(path for path in EXCLUDED if not (SHELL / path).exists())
        self.assertEqual(stale, [], "\n".join([
            "EXCLUDED names files that no longer exist - delete these entries:",
            *(f"  {path}" for path in stale),
        ]))

    def test_every_excluded_directory_still_holds_something(self):
        """A directory exclusion that covers nothing is a rule nobody reads."""
        empty = sorted(
            prefix for prefix in EXCLUDED_DIRS
            if not any(path.startswith(prefix + "/") for path in self.family)
        )
        self.assertEqual(empty, [], "\n".join([
            "EXCLUDED_DIRS names directories holding no press-morphing type -",
            "they moved or stopped inheriting. Delete these entries:",
            *(f"  {prefix}" for prefix in empty),
        ]))

    def test_every_exclusion_still_inherits_the_morph(self):
        """An exclusion that stopped being a descendant is dead weight."""
        irrelevant = sorted(
            path for path in EXCLUDED
            if (SHELL / path).exists() and path not in self.family
        )
        self.assertEqual(irrelevant, [], "\n".join([
            "EXCLUDED names files that no longer inherit RippleButton, so the",
            "gallery never wanted them - delete these entries:",
            *(f"  {path}" for path in irrelevant),
        ]))

    def test_every_entry_is_one_object(self):
        """Between one entry's closing brace and the next thing, only a comma.

        `{ type: "X", props: {} }, toggles: true,` is a JS syntax error - the
        claim landed in the ARRAY, after the object had closed - and it took
        the whole catalogue's compile down with it. The claim lint of the day
        still passed, because it grepped for the words and found them. A lint
        that a syntax error satisfies is checking the wrong thing; this one
        checks the shape.
        """
        stray = []
        for entry, tail in catalogue_entries():
            if re.fullmatch(r"\s*,?\s*", tail):
                continue
            path = entry.split('"', 2)[1]
            stray.append(f"{path}: `{tail.strip()}` sits outside the entry")
        self.assertEqual(stray, [], "\n".join([
            "These catalogue entries have text between their closing brace",
            "and the next entry. Inside the braces or nowhere:",
            *(f"  {line}" for line in stray),
        ]))

    def test_the_toggle_claim_matches_the_source(self):
        """`toggles: true` is a claim about the widget, so it is checked.

        Every RippleButton descendant INHERITS `toggled` whether or not it
        draws anything different for it, so "has the property" is not the same
        question as "is a toggle" - and answering the first put a switch that
        changed nothing on 46 of 62 component pages. The catalogue answers the
        second, and this holds it to the source.
        """
        wrong = []
        for path, claimed in toggle_claims().items():
            if not (SHELL / path).exists():
                continue
            # Two conditions, both needed. HAS the property: a RippleButton
            # descendant, or a type declaring its own. USES it: the word
            # appears in the source. Inheriting alone put a switch that changed
            # nothing on 46 pages; the word alone counted ConfigSelectionArray,
            # a ColumnLayout that hands `toggled:` to the buttons it lays out
            # and has no such property itself - and the knob that claim
            # produced wrote `toggled: false` into a type that cannot take it.
            actual = (path in self.family and reads_toggled(path)) or declares_toggled(path)
            if claimed != actual:
                wrong.append(f"{path}: catalogue says {claimed}, source says {actual}")
        self.assertEqual(wrong, [], "\n".join([
            "The catalogue's `toggles:` claim disagrees with the widget:",
            *(f"  {line}" for line in wrong),
        ]))

    def test_every_catalogued_path_exists(self):
        missing = sorted(path for path in self.listed if not (SHELL / path).exists())
        self.assertEqual(missing, [], "\n".join([
            "The gallery names files that do not exist. A tile for a missing",
            "file draws the same 'needs its surroundings' line a real one does,",
            "so a rename hides here rather than failing:",
            *(f"  {path}" for path in missing),
        ]))


if __name__ == "__main__":
    unittest.main()
