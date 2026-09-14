#!/usr/bin/env python3
"""Frame mode, stage 1 (docs/proposals/frame-mode.md): off by default, one
geometry authority, and the surfaces that read it.

Pins: the config keys and their defaults; FrameGeometry is the only place
the insets are computed (ScreenCorners asks it for its margins, BarContent
asks it whether to square the plate, Frame draws the bands from it); the
family loads Frame only while the option is on; the bands reserve nothing and
take no input; the settings rows and the search index.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"
GEOMETRY = ROOT / "services/FrameGeometry.qml"
FRAME = ROOT / "modules/imi/frame/Frame.qml"
CORNERS = ROOT / "modules/imi/screenCorners/ScreenCorners.qml"
BAR = ROOT / "modules/imi/bar/BarContent.qml"
FAMILY = ROOT / "panelFamilies/ImmaterialImpulseFamily.qml"
PAGE = ROOT / "modules/imi/settings/pages/AppearanceConfig.qml"
INDEX = ROOT / "modules/imi/settings/SettingsContent.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class FrameModeContract(unittest.TestCase):
    def test_off_by_default_and_the_band_follows_the_gap(self):
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject frame: JsonObject {"):]
        block = block[:block.index("}")]
        self.assertRegex(block, r"property bool enable:\s*false", "a look, not a fix: off by default")
        self.assertRegex(block, r"property int thickness:\s*0")
        geo = _strip(GEOMETRY.read_text())
        self.assertIn("Geo.bandThickness(Config.options.appearance.frame.thickness, Config.options.hyprland.general.gapsOut)", geo)
        self.assertIn("&& !Config.options.bar.vertical", geo, "the vertical bar is not framed in stage 1")
        # The bar's edge is what the compositor reserves - ONE token, read by
        # the bar's reserver and by the authority, never a second copy.
        self.assertIn("readonly property real barThickness: Appearance.sizes.barExclusiveZone", geo)
        self.assertNotRegex(geo, r"baseBarHeight|Appearance\.sizes\.barHeight", "no hand copy of the reserver's expression")
        appearance = _strip((ROOT / "modules/common/Appearance.qml").read_text())
        frame = _strip(FRAME.read_text())
        corners = _strip(CORNERS.read_text())
        self.assertIn("property real barExclusiveZone: root.sizes.barReservedHeight", appearance)
        self.assertIn("zone: (Config?.options.bar.autoHide.enable && (!barRoot.mustShow || !Config?.options.bar.autoHide.pushWindows))\n                        ? 0 : Appearance.sizes.barReservedHeight",
                      _strip((ROOT / "modules/imi/bar/Bar.qml").read_text()))
        # The fillet radius is the window rounding, full stop.
        self.assertIn("Geo.innerRadius(Config.options.hyprland.decoration.rounding)", geo)
        # The dock is an occupant only while it reserves (pinned), through
        # the dock's own zone arithmetic.
        self.assertIn("readonly property bool dockReserves: (Config.options.dock.enable ?? false) && GlobalStates.dockPinned", geo)
        self.assertRegex(GEOMETRY.read_text(), r"^import qs\s*$", "GlobalStates resolves only through the root module - the dock occupant was inert without it")
        # The dock's zone is one token too, read by Dock.qml and the authority.
        self.assertIn("readonly property real dockThickness: root.dockReserves ? Appearance.sizes.dockExclusiveZone : 0", geo)
        self.assertNotIn("DockGeo.", geo, "no second copy of the dock's zone arithmetic here")
        self.assertIn("property real dockExclusiveZone: DockGeo.exclusiveZone(", appearance)
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        self.assertIn("exclusiveZone: (root.pinned && !fullscreenOnThisMonitor) ? Appearance.sizes.dockExclusiveZone : 0", dock)
        self.assertIn("onPinnedChanged: GlobalStates.dockPinned = root.pinned", dock)
        self.assertIn("Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, root.dockEdge, root.dockThickness)", geo)
        # Per screen: the dock drops its zone on a fullscreen monitor, so the
        # bands and fillets read the authority through the screen's flag.
        self.assertIn("function insetsFor(fullscreen)", geo)
        self.assertIn('FrameGeometry.bandOffsetFor("top", band.fullscreen)', frame)
        self.assertIn("FrameGeometry.cornerMarginsFor(", corners)
        # The compositor's live rounding, the option as the fallback.
        self.assertIn('command: ["hyprctl", "getoption", "decoration:rounding", "-j"]', geo)
        self.assertIn('if (event.name === "configreloaded") roundingProbe.running = true;', geo)

    def test_one_geometry_authority(self):
        corners = _strip(CORNERS.read_text())
        self.assertIn("FrameGeometry.cornerMargins(", corners)
        self.assertIn('color: FrameGeometry.enabled ? FrameGeometry.color : "#000000"', corners)
        # The window stays at the screen corner (the corner-open hit rect
        # lives there); only the fillet SHAPE moves inward.
        for side in ("left", "top"):
            self.assertIn(f"{side}VisualMargin: cornerPanelWindow.frameMargins.{side}", corners, side)
        self.assertNotIn("left: cornerPanelWindow.frameMargins.left", corners)
        self.assertIn("implicitSize: FrameGeometry.enabled ? Math.round(FrameGeometry.innerRadius) : Appearance.rounding.screenRounding", corners)
        self.assertNotRegex(corners, r"gapsOut|barHeight|decoration\.rounding", "ScreenCorners computes no inset or radius of its own")
        bar = _strip(BAR.read_text())
        self.assertEqual(bar.count("FrameGeometry.enabled ? 0 :"), 4, "the centre-only pill squares all four corners in frame mode")
        frame = _strip(FRAME.read_text())
        self.assertIn('color: band.painted ? FrameGeometry.color : "transparent"', frame, "painted or transparent, never unmapped")
        self.assertIn("visible: FrameGeometry.enabled\n", frame)
        self.assertNotIn("visible: FrameGeometry.enabled && !fullscreen", frame)
        self.assertIn("exclusionMode: ExclusionMode.Ignore", frame, "the band lives in the gap; it reserves nothing")
        self.assertIn("mask: Region {}", frame, "the band takes no input")
        self.assertEqual(frame.count("            Band {\n                screen: screenScope.modelData"), 4, "four bands, one per edge, each naming its screen")
        self.assertIn('FrameGeometry.bandOffset("top")', frame, "the bar-edge band starts under the bar's zone")
        self.assertIn("HyprlandData.specialWorkspaceByMonitorName[", frame)
        rules = (ROOT.parents[1] / "hypr/hyprland/rules.lua").read_text()
        self.assertIn('namespace = "quickshell:frame" }, no_anim = true', rules)

    def test_the_family_gates_the_surface_on_the_option(self):
        fam = FAMILY.read_text()
        self.assertIn("PanelLoader { extraCondition: FrameGeometry.enabled; component: Frame {} }", fam, "the family agrees with the authority (the vertical bar is not framed)")
        self.assertIn("import qs.modules.imi.frame", fam)

    def test_settings_rows_and_index(self):
        page = _strip(PAGE.read_text())
        self.assertIn('title: Translation.tr("Frame")', page)
        self.assertIn("Config.options.appearance.frame.enable = !Config.options.appearance.frame.enable", page)
        self.assertIn("property bool rowVisible: Config.options.appearance.frame.enable", page)
        self.assertIn("Config.options.appearance.frame.thickness = newValue", page)
        self.assertIn('Translation.tr("Frame")', INDEX.read_text())


if __name__ == "__main__":
    unittest.main()
