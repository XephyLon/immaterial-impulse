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
