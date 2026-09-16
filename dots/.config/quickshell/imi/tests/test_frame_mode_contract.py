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
        # The dock is NOT an occupant of the frame. The frame's inner corner
        # on the dock's edge is at the band (a fillet at the dock's inset
        # arced into wallpaper; a band as tall as the dock's strip was a
        # border with a pill lost in it), and the authority names no dock: a
        # pinned dock meets the band from its own side - DockReservation
        # reads the authority, never the other way round - so there is no
        # import cycle and no per-screen plumbing (one frame for every screen).
        self.assertNotRegex(geo, r"[Dd]ock(Reserv|Thickness|Edge|Geo)", "the authority names no dock occupant")
        self.assertNotIn("import qs.modules.imi.dock", GEOMETRY.read_text())
        self.assertNotIn("GlobalStates", GEOMETRY.read_text())
        self.assertNotRegex(geo, r"ForScreen|fullscreenOnMonitor|ByScreen", "one frame for every screen: no per-screen readers")
        self.assertIn("Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness)", geo)
        self.assertNotRegex(appearance, r"dockExclusiveZone|dock_geometry", "Appearance is the layer everything builds on; it names no feature")
        # How a pinned dock meets the band is the frame's option, read by the
        # dock: on it as a tab (the default) or a gap above it. Anything but
        # "floating" attaches, so a hand-edited value leaves the dock somewhere.
        self.assertRegex(block, r'property string dock:\s*"attached"', "a pinned dock sits on the band by default")
        self.assertIn('readonly property bool dockAttached: String(Config.options.appearance.frame.dock ?? "attached") !== "floating"', geo)
        reservation = _strip((ROOT / "modules/imi/dock/DockReservation.qml").read_text())
        self.assertIn("readonly property real zone: DockGeometry.exclusiveZone(", reservation)
        self.assertIn("readonly property bool attached: FrameGeometry.enabled && FrameGeometry.dockAttached", reservation)
        self.assertIn("readonly property real frameOffset: DockGeometry.frameOffset(", reservation)
        self.assertIn("FrameGeometry.thickness, Appearance.sizes.hyprlandGapsOut)", reservation)
        # The dock meets the band by moving its whole SURFACE (an anchored-
        # edge margin, which the compositor adds to the zone by itself), never
        # by re-deriving its inner margins - and only while pinned: an
        # unpinned dock hides and reveals from the screen edge.
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        self.assertIn("readonly property bool reserves: root.pinned && !fullscreenOnThisMonitor", dock)
        self.assertIn("exclusiveZone: dockRoot.reserves ? DockReservation.zone : 0", dock)
        self.assertIn("fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)", dock)
        self.assertIn("root.edge, 0, dockRoot.reserves ? DockReservation.frameOffset : 0)", dock)
        for side in ("top", "bottom", "left", "right"):
            self.assertIn(f"{side}: dockRoot.frameMargins.{side}", dock, side)
        self.assertNotRegex(dock, r"dockThickness: DockGeometry\.thickness\([^)]*frame", "the dock's inner geometry knows nothing of the frame")
        # Attached, the pill is a tab of the band: its colour, no border, the
        # outward corners squared at the seam - and the blur region KEPT, per
        # corner (the bar plate in the same colour is blurred; a tab without
        # it read as unfrosted translucency on a real wallpaper). Unpinned too
        # while the band is the gap (a rounded, bordered pill on the default
        # band was a pill on a line); on any other band an unpinned dock
        # cannot be moved to meet the band, so it keeps the pill.
        self.assertIn("readonly property bool attached: DockReservation.attached && !fullscreenOnThisMonitor\n                && (dockRoot.reserves || DockReservation.frameOffset === 0)", dock)
        self.assertIn("dockRoot.attached ? FrameGeometry.color : Appearance.colors.colLayer0", dock)
        self.assertIn("border.width: Config.options.dock.showBackground && !dockRoot.attached ? 1 : 0", dock)
        self.assertNotIn("regionItem:", dock, "the blur region is composed per corner, not a single-radius rect")
        # ...and published only while the pill is at rest: a Region tracks
        # its item's OWN geometry, the dock hides by offsetting an ancestor,
        # and a hidden dock left a frosted silhouette where the pill rests.
        self.assertIn("item: Config.options.dock.showBackground && dockMouseArea.atRest ? dockVisualBackground : null", dock)
        self.assertIn("readonly property bool atRest: anchors.horizontalCenterOffset === 0 && anchors.verticalCenterOffset === 0", dock)
        self.assertIn("DockGeometry.cornerRadii(root.edge, radius, dockRoot.attached)", dock)
        for corner in ("topLeft", "topRight", "bottomLeft", "bottomRight"):
            self.assertRegex(dock, rf"{corner}Radius:\s+frameRadii\.{corner}", corner)
            self.assertIn(f"{corner}Radius: dockVisualBackground.{corner}Radius", dock, f"the blur region follows the pill's {corner}")
        # GlobalStates.dockPinned existed for the authority; nothing reads it now.
        self.assertNotIn("dockPinned", dock)
        self.assertNotIn("dockPinned", _strip((ROOT / "GlobalStates.qml").read_text()))
        self.assertIn("FrameGeometry.bandMargins(band.edge)", frame)
        self.assertIn("Math.max(1, FrameGeometry.thickness)", frame)
        self.assertNotRegex(frame, r"bandExtent|ForScreen", "the band is its thickness on every edge")
        self.assertNotIn("fullscreen: screenScope.fullscreen", frame)
        self.assertIn("FrameGeometry.cornerMargins(", corners)
        self.assertNotRegex(corners, r"cornerMarginsForScreen|screen\?\.name", "the fillet asks for its corner, not a screen")
        # The compositor's live rounding, the option as the fallback; the
        # probe spawns only while frame mode is on.
        self.assertIn('command: ["hyprctl", "getoption", "decoration:rounding", "-j"]', geo)
        self.assertIn("running: root.enabled && root.probeArmed\n", geo)
        self.assertNotIn("roundingProbe.running =", geo, "re-arm through the flag; a write over the binding destroys it")
        self.assertIn('if (event.name !== "configreloaded" || !root.enabled) return;', geo)

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
        # Every band is inset at BOTH ends (the library's bandMargins): the
        # horizontal bands span the width, the side bands run between them,
        # and no two overlap (the colour is translucent).
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
        # The dock row: a labelled choice, shown only while both the frame
        # and the dock are on.
        self.assertIn("Config.options.appearance.frame.dock = newValue", page)
        self.assertIn('{ "displayName": Translation.tr("Attached"), "value": "attached" }', page)
        self.assertIn('{ "displayName": Translation.tr("Floating"), "value": "floating" }', page)
        self.assertIn("property bool rowVisible: Config.options.appearance.frame.enable && (Config.options.dock.enable ?? false)", page)
        index = INDEX.read_text()
        self.assertIn('Translation.tr("Frame")', index)
        self.assertIn('Translation.tr("Floating dock")', index)


if __name__ == "__main__":
    unittest.main()
