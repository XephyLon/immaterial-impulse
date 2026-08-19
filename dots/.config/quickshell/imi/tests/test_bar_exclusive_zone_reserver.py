#!/usr/bin/env python3
"""Source pins holding the bar's animated exclusive zone off the bar's window.

A layer surface's exclusive zone is a protocol value on the surface itself:
writing it is a set_exclusive_zone + commit and a compositor-wide re-arrange.
The bar slides in and out of auto-hide on a margin Behavior while its zone
snapped between two integers, so the bar glided and the windows behind it
jumped. `BarExclusiveZoneReserver` is a second, invisible, fully-masked
`PanelWindow` that owns the animated zone; both bars use that one component
rather than each deciding for themselves, which is the same rule
`bar_widget_source.js` and `dock_geometry.js` already carry.

None of it is reachable from a runtime harness. `qmltestrunner` cannot
construct a Quickshell window at all, and weston implements no
wlr-layer-shell, so no headless harness in this tree can map a layer surface
let alone ask a compositor what it reserved. It was measured instead in a
nested Hyprland - `tests/run_bar_exclusive_zone_probe.sh`, which reads the
reserved area back out of `hyprctl monitors` while the zone animates - and
what stays behind here is the source contract that probe was pointed at.

The pins are structural rather than textual for the reason recorded in
`test_background_fullscreen_suppression.py`: a raw pattern over QML decays
into one that matches nothing after any reformat.
"""
import re
import unittest
from pathlib import Path

from test_background_fullscreen_suppression import _qml_source

ROOT = Path(__file__).resolve().parents[1]
RESERVER = ROOT / "modules/imi/bar/BarExclusiveZoneReserver.qml"
BARS = {
    "Bar.qml": ROOT / "modules/imi/bar/Bar.qml",
    "VerticalBar.qml": ROOT / "modules/imi/verticalBar/VerticalBar.qml",
}

_BEHAVIOR_ON = re.compile(r"\bBehavior\s+on\s+([\w.]+)\s*$")
_TIER = re.compile(r"Appearance\.animation\.(\w+)\b")
_RESERVER_TYPE = "BarExclusiveZoneReserver"


def _reserver_elements(qml):
    """The component's instantiations, qualified import or not.

    VerticalBarContent reaches the bar's directory as `qs.modules.imi.bar as
    Bar`, so the vertical bar spells the type `Bar.BarExclusiveZoneReserver`.
    Matching the whole name would pin one bar and quietly stop covering the
    other, which is the drift these files keep having.
    """
    return [b for b in qml.elements()
            if b.name and b.name.split(".")[-1] == _RESERVER_TYPE]


def _behavior_tiers(qml):
    """`{animated property: motion tier}` for every Behavior in the file."""
    tiers = {}
    for block in qml.blocks:
        if block.name != "Behavior" or block.close_at is None:
            continue
        target = _BEHAVIOR_ON.search(block.header.strip())
        tier = _TIER.search(qml.body(block))
        if target and tier:
            tiers[target.group(1)] = tier.group(1)
    return tiers


class ReserverContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reserver = _qml_source(RESERVER)
        cls.bars = {name: _qml_source(path) for name, path in BARS.items()}
        windows = cls.reserver.elements("PanelWindow")
        assert len(windows) == 1, (
            f"expected exactly one PanelWindow in {RESERVER}, found {len(windows)}")
        cls.window = windows[0]
        cls.members = dict(cls.reserver.members(cls.window))

    def test_the_files_parse(self):
        """Vacuity guard. Every pin below reads structure, so a file the reader
        cannot balance would pass all of them by finding nothing."""
        for name, qml in [(RESERVER.name, self.reserver)] + list(self.bars.items()):
            with self.subTest(file=name):
                self.assertEqual(qml.unclosed, 0, f"unbalanced braces in {name}")
        for name, qml in self.bars.items():
            with self.subTest(file=name):
                self.assertEqual(len(qml.elements("PanelWindow")), 1,
                                 f"{name} should still declare exactly one PanelWindow")

    def test_neither_bar_carries_an_exclusive_zone(self):
        """The visible bar may not name `exclusiveZone` at all, not even as 0.

        `WlrLayershell::setExclusiveZone` forces `exclusionMode` to Normal, and
        a Normal-mode surface is placed inside the area other surfaces reserve
        - so a bar spelling `exclusiveZone: 0` beside its `ExclusionMode.Ignore`
        would be pushed off the screen edge by its own reserver. Comments are
        blanked by the reader, so the one in Bar.qml saying this does not
        satisfy the pin.
        """
        for name, qml in self.bars.items():
            with self.subTest(bar=name):
                self.assertNotIn(
                    "exclusiveZone", qml.code,
                    f"{name} names exclusiveZone again. The animated zone "
                    f"belongs to {RESERVER.name}; writing the property here at "
                    f"all flips this window into ExclusionMode.Normal.")
                window = qml.elements("PanelWindow")[0]
                self.assertEqual(
                    qml.member(window, "exclusionMode"), "ExclusionMode.Ignore",
                    f"{name}'s window must stay in Ignore mode, or the "
                    f"compositor moves it out of the zone the reserver holds.")

    def test_both_bars_reserve_through_the_one_component(self):
        for name, qml in self.bars.items():
            with self.subTest(bar=name):
                found = _reserver_elements(qml)
                self.assertEqual(
                    len(found), 1,
                    f"{name} should instantiate exactly one "
                    f"{_RESERVER_TYPE}, found {len(found)}. The two bars must "
                    f"not each work out what their exclusive zone does.")
                self.assertIsNotNone(
                    qml.member(found[0], "zone"),
                    f"{name}'s reserver declares no `zone`, so it reserves "
                    f"nothing and the bar has silently stopped pushing windows.")

    def test_the_animated_zone_lives_on_the_reserver(self):
        self.assertIn("animatedZone", self.members.get("exclusiveZone", ""),
                      "the reserver's exclusiveZone should read the animated "
                      "value, or nothing about the zone is animated at all")
        self.assertIn("animatedZone", _behavior_tiers(self.reserver),
                      "the reserver has no Behavior on animatedZone, so the "
                      "zone snaps and the windows behind the bar jump again")
        self.assertEqual(self.members.get("exclusionMode"), "ExclusionMode.Normal",
                         "the reserver is the window that reserves; Ignore "
                         "there means nothing is reserved by anything")

    def test_the_zone_and_the_bar_body_ride_the_same_curve(self):
        """The whole point of the split: the reflow follows the picture.

        A zone animating on a different tier from the slide is worse than one
        that snaps, because it disagrees with the bar for the whole gesture
        instead of only at the ends.
        """
        zone_tier = _behavior_tiers(self.reserver)["animatedZone"]
        for name, qml in self.bars.items():
            tiers = _behavior_tiers(qml)
            slides = {prop: tier for prop, tier in tiers.items()
                      if prop.startswith("anchors.")}
            with self.subTest(bar=name):
                self.assertTrue(
                    slides,
                    f"{name} has no Behavior on an anchor margin any more - "
                    f"the pin below cannot compare the zone against a slide "
                    f"that is not there.")
                self.assertEqual(
                    sorted(set(slides.values())), [zone_tier],
                    f"{name}'s body slides on {sorted(set(slides.values()))} "
                    f"while the exclusive zone animates on {zone_tier!r}.")

    def test_the_reserver_is_masked_to_nothing(self):
        """An empty mask is what makes a permanently mapped surface harmless.

        Quickshell sets Qt::WindowTransparentForInput only for a mask that
        resolves to an empty region, so a `Region` here that grew an item, a
        size or a child region would put an invisible input-taking sheet across
        the top of the screen.
        """
        regions = [b for b in self.reserver.elements("Region")]
        self.assertEqual(len(regions), 1,
                         "the reserver should declare exactly one Region, its mask")
        mask = regions[0]
        self.assertIn("mask", mask.header,
                      "the reserver's only Region should be its `mask`")
        self.assertEqual(self.reserver.members(mask), [],
                         "the reserver's mask Region binds something; an "
                         "item, an x/y/width/height or a radius all make it "
                         "resolve to a non-empty region, and the window then "
                         "takes input it must never take")
        self.assertEqual(mask.children, [],
                         "a child Region makes the mask non-empty")

    def test_the_reserver_paints_nothing_and_asks_for_no_blur(self):
        self.assertEqual(self.members.get("color"), '"transparent"',
                         "the reserver's clear colour must stay a literal "
                         "transparent - see lint_window_clear_color.py for why "
                         "a bound one costs a surface its blur permanently")
        self.assertEqual(self.reserver.elements("WindowBlurRegion"), [],
                         "the reserver paints nothing, so a blur region on it "
                         "asks the compositor to frost bare wallpaper")
        self.assertNotIn("WlrLayer.Overlay", self.reserver.code,
                         "an Overlay surface holds the compositor's fullscreen "
                         "fast path shut whatever its size, and this one has "
                         "no pixels to keep above anything")

    def test_the_reserver_borrows_each_bar_namespace_instead_of_minting_one(self):
        """A minted namespace is absent from `rules.lua`, where the catch-all
        `ignore_alpha = 0.05` then asks the compositor to blur behind a surface
        that paints nothing - and the rules.lua half ships in a different file
        from this one, so the two halves separate on any machine that updates
        one and not the other. Both bars' namespaces already carry
        `blur = false`, so borrowing needs no rules.lua entry at all."""
        namespace = self.members.get("WlrLayershell.namespace", "")
        self.assertNotIn('"', namespace,
                         "the reserver mints its own namespace instead of "
                         f"taking the bar's: {namespace!r}")
        for name, qml in self.bars.items():
            with self.subTest(bar=name):
                window = qml.elements("PanelWindow")[0]
                reserver = _reserver_elements(qml)[0]
                self.assertEqual(
                    qml.member(reserver, "barNamespace"),
                    qml.member(window, "WlrLayershell.namespace"),
                    f"{name}'s reserver is on a different namespace from the "
                    f"bar it reserves for, which is a namespace rules.lua has "
                    f"never heard of.")


if __name__ == "__main__":
    unittest.main()
