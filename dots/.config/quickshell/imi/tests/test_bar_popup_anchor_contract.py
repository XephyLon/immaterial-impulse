#!/usr/bin/env python3
"""A bar widget's open popup is marked by the edge indicator, and nothing else.

The bar had no open state for a widget whose popup is up. Two were tried and
failed on styling: a tonal container behind the widget (a filled pill behind
the Docker gauge's bare ring, wrong under every style but M3) and a dashed
ring around the visual (needs air the group pills and the flat bar do not
give). The open state is `PopupAnchorIndicator`: Material's active indicator,
a primary bar on the bar surface's popup-facing edge, as long as the widget's
visual, growing in and fading, at the edge and so outside every group pill.
A widget that holds a popup open on a click mounts one on its root, points it
at its visual and at the popup's edge, and paints no tonal toggled colours.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
BAR = ROOT / "modules/imi/bar"
INDICATOR = ROOT / "modules/common/widgets/PopupAnchorIndicator.qml"
EDGES = ROOT / "modules/common/functions/barEdges.js"

# The widgets whose popup a click holds open, the state that says so, and the
# visual the indicator is as long as.
POPUP_OWNERS = {
    "DockerPlugin.qml": ("root.popupOpen", "contentLoader"),
    "DiscordVoicePlugin.qml": ("root.popupOpen", "content"),
    "SysTray.qml": ("root.trayOverflowOpen", "trayOverflowButton.background"),
    "PrivacyIndicator.qml": ("root.controlsPinned", "pill"),
}


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


class PopupAnchorIndicatorTests(unittest.TestCase):
    def setUp(self):
        self.indicator = strip_comments(INDICATOR.read_text(encoding="utf-8"))

    def test_it_fades_and_grows_on_tokenised_tiers_only(self):
        self.assertNotRegex(self.indicator, r"duration:\s*\d", "no literal duration; bind to a tokenised tier")
        self.assertRegex(self.indicator, r"Behavior on presence \{\s*animation: Appearance\.animation\.\w+\.numberAnimation\.createObject\(this\)")
        self.assertRegex(self.indicator, r"Behavior on grow \{\s*animation: Appearance\.animation\.\w+\.numberAnimation\.createObject\(this\)")
        self.assertRegex(self.indicator, r"opacity:\s*root\.presence")
        self.assertRegex(self.indicator, r"visible:\s*root\.presence > 0")
        self.assertRegex(self.indicator, r"\* root\.grow", "the length rides the grow scalar")

    def test_it_sits_on_the_nearest_painted_plate(self):
        # Not the root's edge (a vertical bar's widgets are narrower than the
        # bar) and not the window's (taller than the plate by shadows and
        # gaps, unevenly): the nearest ancestor's popupAnchorSurface.
        self.assertIn("popupAnchorSurface", self.indicator)
        self.assertNotIn("Window.height", self.indicator)
        self.assertNotIn("Window.width", self.indicator)
        self.assertRegex(self.indicator, r"s\.mapToItem\(e,")

    def test_every_container_exposes_the_plate_it_paints(self):
        group = strip_comments((BAR / "BarGroup.qml").read_text(encoding="utf-8"))
        self.assertRegex(group, r"readonly property Item popupAnchorSurface: background\.color\.a > 0 \? background : null")
        for path, pills, islands in (
            (BAR / "BarContent.qml", ("leftMaterialPill", "centerMaterialPill", "rightMaterialPill"), ("leftIsland", "centerIsland", "rightIsland")),
            (ROOT / "modules/imi/verticalBar/VerticalBarContent.qml", ("topMaterialPill", "centerMaterialPill", "bottomMaterialPill"), ("topIsland", "centerIsland", "bottomIsland")),
        ):
            text = strip_comments(path.read_text(encoding="utf-8"))
            markers = re.findall(r"readonly property Item popupAnchorSurface: root\.isMaterial \? (\w+)\s*: root\.isFloatIslands \? (\w+)(.*?)barBackground\.color\.a > 0 \? barBackground : null", text, re.S)
            self.assertEqual([m[0] for m in markers], list(pills), f"{path.name}: each section names its material pill")
            self.assertEqual([m[1] for m in markers], list(islands), f"{path.name}: each section names its island")
            self.assertIn("centerPill.visible ? centerPill", markers[1][2], f"{path.name}: the centre section knows the centre-only pill")

    def test_its_dimensions_and_colour_are_tokens(self):
        self.assertRegex(self.indicator, r"property real thickness: Appearance\.borderWidth\.")
        self.assertRegex(self.indicator, r"color: Appearance\.colors\.colPrimary")
        self.assertNotRegex(self.indicator, r"(width|height|thickness):\s*\d+(\.\d+)?\s*$", "no literal size")

    def test_the_edge_helper_reads_the_bars_side_from_the_bottom_flag(self):
        edges = EDGES.read_text(encoding="utf-8")
        self.assertIn("function popupEdge(vertical, bottom)", edges)
        for token in ('"left"', '"right"', '"top"', '"bottom"'):
            self.assertIn(token, edges)


class PopupOwnerTests(unittest.TestCase):
    def test_every_popup_owner_mounts_the_indicator_on_its_open_state(self):
        for name, (state, visual) in POPUP_OWNERS.items():
            text = strip_comments((BAR / name).read_text(encoding="utf-8"))
            block = re.search(r"PopupAnchorIndicator \{(.*?)\n\s*\}", text, re.S)
            self.assertIsNotNone(block, f"{name} owns a popup and must mount PopupAnchorIndicator")
            body = block.group(1)
            self.assertRegex(body, r"shown:\s*" + re.escape(state), f"{name}: the indicator follows {state}")
            self.assertRegex(body, r"wraps:\s*" + re.escape(visual), f"{name}: the indicator is as long as {visual}")
            self.assertRegex(body, r"edgeItem:\s*root\b", f"{name}: the indicator sits on the widget's root, which spans the bar")
            self.assertRegex(body, r"edge:\s*BarEdges\.popupEdge\(Config\.options\.bar\.vertical, Config\.options\.bar\.bottom\)",
                             f"{name}: the edge comes from the bar's flags through the helper")
            self.assertIn('import "../../common/functions/barEdges.js" as BarEdges', text)

    def test_no_popup_owner_paints_a_tonal_container_or_a_ring_for_the_open_state(self):
        for name in POPUP_OWNERS:
            text = strip_comments((BAR / name).read_text(encoding="utf-8"))
            for prop in ("colBackgroundToggled", "colBackgroundToggledHover", "colRippleToggled", "PopupAnchorOutline"):
                self.assertNotIn(prop, text, f"{name}: {prop} is not the open state")

    def test_every_bar_file_with_a_click_held_popup_is_in_the_register(self):
        # A new widget that holds a popup open on a click joins POPUP_OWNERS,
        # or it ships without the open state.
        for path in sorted(BAR.glob("*.qml")):
            text = strip_comments(path.read_text(encoding="utf-8"))
            if re.search(r"property bool (popupOpen|controlsPinned)\b", text) or "trayOverflowOpen" in text:
                self.assertIn(path.name, POPUP_OWNERS, f"{path.name} holds a popup open on a click; register it")


if __name__ == "__main__":
    unittest.main()
