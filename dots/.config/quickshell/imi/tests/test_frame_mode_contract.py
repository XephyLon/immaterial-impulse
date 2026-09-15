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
        self.assertIn("Geo.innerRadius(root.liveRounding >= 0 ? root.liveRounding : Config.options.hyprland.decoration.rounding)", geo)
        # The dock is an occupant only while it reserves (pinned), through
        # the dock's own zone arithmetic.
        self.assertIn("readonly property bool dockReserves: (Config.options.dock.enable ?? false) && GlobalStates.dockPinned", geo)
        self.assertIn("\nimport qs\n", GEOMETRY.read_text(), "GlobalStates resolves only through the root module - the dock occupant was inert without it")
        # The dock's zone is one value too, published from the dock's own side
        # (DockReservation) and read by Dock.qml and the authority; the
        # design-token singleton knows nothing of the dock.
        self.assertIn("readonly property real dockThickness: root.dockReserves ? DockReservation.zone : 0", geo)
        self.assertIn("\nimport qs.modules.imi.dock\n", GEOMETRY.read_text())
        self.assertNotRegex(geo, r"DockGeo|dock_geometry", "no second copy of the dock's zone arithmetic here")
        self.assertNotRegex(appearance, r"dockExclusiveZone|dock_geometry", "Appearance is the layer everything builds on; it names no feature")
        reservation = _strip((ROOT / "modules/imi/dock/DockReservation.qml").read_text())
        self.assertIn("readonly property real zone: DockGeometry.exclusiveZone(", reservation)
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        self.assertIn("exclusiveZone: (root.pinned && !fullscreenOnThisMonitor) ? DockReservation.zone : 0", dock)
        self.assertIn("onPinnedChanged: GlobalStates.dockPinned = root.pinned", dock)
        self.assertIn("Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, root.dockEdge, root.dockThickness)", geo)
        # Per screen: the dock drops its zone on a fullscreen monitor. The
        # AUTHORITY owns that predicate - the same one Dock.qml uses - and the
        # readers ask by screen name; no caller hands in a fullscreen flag,
        # so the bands and the fillets cannot be given two answers.
        self.assertIn("return root.dockReserves && !WM.fullscreenOnMonitor(screenName);", geo)
        self.assertIn("fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)", dock)
        self.assertNotRegex(geo, r"function \w+\([^)]*fullscreen[^)]*\)", "no reader takes a caller's fullscreen flag")
        self.assertIn('FrameGeometry.bandMarginsForScreen(band.edge, band.screen?.name ?? "")', frame)
        self.assertNotIn("fullscreen: screenScope.fullscreen", frame)
        self.assertIn('FrameGeometry.cornerMarginsForScreen(', corners)
        self.assertIn('cornerPanelWindow.screen?.name ?? ""', corners)
        self.assertNotRegex(corners, r"cornerMarginsForScreen\([^\n]*fullscreen", "the fillet passes its screen, not its own fullscreen flag")
        # The compositor's live rounding, the option as the fallback; the
        # probe spawns only while frame mode is on.
        self.assertIn('command: ["hyprctl", "getoption", "decoration:rounding", "-j"]', geo)
        self.assertIn("running: root.enabled\n", geo)
        self.assertIn('if (event.name === "configreloaded" && root.enabled) roundingProbe.running = true;', geo)
        self.assertIn("onEnabledChanged: if (root.enabled) roundingProbe.running = true", geo)

    def test_one_geometry_authority(self):
        corners = _strip(CORNERS.read_text())
        self.assertIn("FrameGeometry.cornerMarginsForScreen(", corners)
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
        # Every band is inset at BOTH ends (the library's bandMargins), so the
        # side bands end at the frame's corners instead of running the full
        # screen height past a pinned dock.
        self.assertIn("top: band.bandMargins.top", frame)
        self.assertIn("bottom: band.bandMargins.bottom", frame)
        self.assertNotIn("bandOffsetFor", frame, "a band takes all four margins from the authority, not its own edge's offset alone")
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
