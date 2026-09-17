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
import shutil
import subprocess
import tempfile
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
        self.assertIn("FrameGeometry.enabled, FrameGeometry.thickness, Appearance.sizes.hyprlandGapsOut)", reservation)
        self.assertNotIn("FrameGeometry.dockAttached, FrameGeometry.thickness", reservation,
                         "the surface sits where the attached tab needs it in BOTH states; floating is the pill's lift inside it")
        # The dock meets the band by moving its whole SURFACE (an anchored-
        # edge margin, which the compositor adds to the zone by itself), never
        # by re-deriving its inner margins - and only while pinned: an
        # unpinned dock hides and reveals from the screen edge.
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        self.assertIn("readonly property bool reserves: root.pinned && !fullscreenOnThisMonitor", dock)
        self.assertIn("exclusiveZone: dockRoot.reserves ? DockReservation.zone + dockRoot.splitZoneExtra : 0", dock)
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
        self.assertIn("dockRoot.attachedLook ? FrameGeometry.color : Appearance.colors.colLayer0", dock)
        self.assertIn("border.width: Config.options.dock.showBackground ? Appearance.borderWidth.standard : 0", dock)
        self.assertIn("border.color: dockRoot.attachedLook ? FrameGeometry.color : Appearance.colors.colLayer0Border", dock,
                      "the border is a colour change: a width from 0 draws nothing until 1, and a transparent ring is a seam")
        self.assertNotIn("regionItem:", dock, "the blur region is composed per corner, not a single-radius rect")
        # ...and published only while the pill is at rest: a Region tracks
        # its item's OWN geometry, the dock hides by offsetting an ancestor,
        # and a hidden dock left a frosted silhouette where the pill rests.
        self.assertIn("item: Config.options.dock.showBackground && dockMouseArea.atRest ? dockVisualBackground : null", dock)
        self.assertIn("readonly property bool atRest: anchors.horizontalCenterOffset === 0 && anchors.verticalCenterOffset === 0", dock)
        self.assertIn("DockGeometry.cornerRadiiAt(root.edge, radius,\n                                dockRoot.liftFromTab || dockRoot.splitTarget === 0 ? dockRoot.apart : 1,", dock,
                      "the outward corners round on the scalar, from the seam, not at a boolean - and stay round for a pill that was never fused")
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

    def test_the_dock_switch_is_the_split(self):
        """docs/proposals/motion-split.md §6: one scalar, the split tier taken
        whole, the pill lifting inside a surface that never moves, the look
        sequenced outside the motion, the corners and the neck keyed on the
        seam, and a zone that reserves the union of where the pill is and
        where it goes."""
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        reservation = _strip((ROOT / "modules/imi/dock/DockReservation.qml").read_text())
        appearance = _strip((ROOT / "modules/common/Appearance.qml").read_text())
        # The tier: a two-segment curve whose join - the seam - is the scalar's
        # midpoint, an 800 ms base through the policy, and the two constants
        # beside it. Measured, not chosen: the proposal's §4 and §5.
        self.assertIn("readonly property list<real> split: [0.15, 0, 0.5, 0.5, 0.5, 0.5, 0.6, 0.5, 0.5, 1, 1, 1]", appearance)
        self.assertIn("readonly property real splitDuration: 800", appearance)
        self.assertIn("property QtObject split: QtObject {", appearance)
        self.assertIn("motion.scale(animationCurves.splitDuration)", appearance)
        self.assertIn("readonly property real splitSeam: 0.5", appearance)
        self.assertIn("readonly property real splitNeckReach: 0.8", appearance)
        self.assertIn("### Split (one body becomes two, or two become one)", (ROOT.parents[3] / "docs/M3_GUIDELINES.md").read_text())
        # ONE scalar, 0 fused and 1 apart, driven by the CONFIGURED choice -
        # never by a state the user did not toggle (a fullscreen window
        # dropping `attached` used to replay a landing on every exit) - with
        # exactly one Behavior: the tier whole, enabled only when there is a
        # lift to draw, and a pause before a landing so the look lands before
        # the outline moves (the reference sequences effects and space).
        self.assertIn("property real splitProgress: dockRoot.splitTarget", dock)
        self.assertIn("readonly property real splitTarget: FrameGeometry.enabled && root.pinned && !DockReservation.attached ? 1 : 0", dock,
                      "the frame option and the pin: pinning a floating dock lifts it off the band")
        self.assertNotRegex(dock, r"splitTarget:.*(reserves|fullscreen)", "the scalar does not follow the fullscreen term")
        self.assertEqual(dock.count("Behavior on splitProgress"), 1)
        behavior = dock[dock.index("Behavior on splitProgress"):]
        behavior = behavior[:behavior.index("readonly property real splitTravel")]
        self.assertIn("enabled: dockRoot.splitTravel > 0", behavior, "no lift, no spatial tier: the look alone changes")
        self.assertIn("SequentialAnimation", behavior)
        self.assertIn("PauseAnimation { duration: splitBehavior.targetValue === 0 && dockRoot.splitProgress >= 1 ? Appearance.animation.elementMoveFast.duration : 0 }", behavior,
                      "a pause only when a look change is pending - a lift reversed mid-flight parked the pill in the air")
        for half in ("Appearance.animation.split.duration",
                     "easing.type: Appearance.animation.split.type",
                     "easing.bezierCurve: Appearance.animation.split.bezierCurve"):
            self.assertIn(half, behavior, "the tier is taken whole")
        self.assertNotRegex(dock, r"duration:\s*\d", "no literal duration anywhere in the dock")
        # The lift: the gap, only while the dock reserves its edge; the pill
        # moves on its OWN margins (so the blur region, which tracks its
        # item's own geometry, rides the lift) and the icons ride the pill.
        self.assertIn("readonly property real splitTravel: DockGeometry.splitTravel(FrameGeometry.enabled, dockRoot.reserves, Appearance.sizes.hyprlandGapsOut)", dock)
        self.assertIn("readonly property real splitLift: dockRoot.splitTravel * dockRoot.splitProgress", dock)
        self.assertIn("readonly property real splitRoom: DockGeometry.splitRoom(Appearance.sizes.hyprlandGapsOut, Appearance.sizes.elevationMargin)", dock)
        self.assertIn("DockGeometry.liftedMargins(root.edge, dockRoot.dockMargins, dockRoot.splitRoom, dockRoot.splitLift)", dock)
        self.assertIn("DockGeometry.liftOffset(root.edge, dockRoot.splitRoom, dockRoot.splitLift)", dock)
        self.assertIn("Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut) + dockRoot.splitRoom", dock,
                      "the strip grows by the room the lift needs, nothing at the defaults")
        # The reservation reserves the union of where the pill is and where it
        # is going: it steps at the start of a lift and the end of a landing,
        # a boolean that flips - never per frame, never against a floating
        # pill. The authority's zone stays the attached one.
        self.assertIn("exclusiveZone: dockRoot.reserves ? DockReservation.zone + dockRoot.splitZoneExtra : 0", dock)
        self.assertIn("readonly property real splitZoneExtra: DockGeometry.splitZoneExtra(dockRoot.splitTravel, dockRoot.splitTarget === 1, dockRoot.splitProgress)", dock)
        self.assertNotIn("splitZoneExtra", reservation)
        self.assertNotIn("splitProgress", reservation)
        # The look: the tab's until the pill has landed apart, then the pill's
        # on the effects tier - after the motion on a lift, before it on a
        # landing (the pause above). With no lift the look IS the switch and
        # runs on the effects tier alone, corners included, on its own scalar.
        self.assertIn("readonly property bool attachedLook: dockRoot.splitTravel > 0 ? (dockRoot.attached || (dockRoot.splitProgress < 1 && dockRoot.liftFromTab)) : dockRoot.attached", dock)
        # A lift that began as the tab splits; a pill that was never fused
        # (a floating dock being pinned) rises as a pill: no neck, corners
        # round. Latched at the target's rising edge.
        self.assertIn("property bool liftFromTab: true", dock)
        self.assertIn("onSplitTargetChanged: if (dockRoot.splitTarget === 1) dockRoot.liftFromTab = dockRoot.attachedBefore", dock,
                      "decided from last turn's attached, never from the look (its terms move on the same edge) nor from what changed (a change between edges escapes)")
        self.assertIn("onAttachedChanged: Qt.callLater(() => { dockRoot.attachedBefore = dockRoot.attached; })", dock)
        self.assertIn("property bool attachedBefore: false", dock, "a plain property, never a binding a handler destroys")
        self.assertNotIn("liftFromTab = dockRoot.attachedLook", dock)
        self.assertNotIn("pinnedAtLastEdge", dock)
        self.assertIn("&& (dockRoot.liftFromTab || dockRoot.splitTarget === 0)", dock, "the neck draws for a split and for every landing")
        self.assertIn("property real lookApart: dockRoot.attached ? 0 : 1", dock)
        look = dock[dock.index("Behavior on lookApart {"):]
        look = look[:look.index("}")]
        self.assertIn("enabled: dockRoot.splitTravel <= 0", look, "idle while the split scalar is the one read")
        self.assertIn("animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)", look)
        self.assertIn("readonly property real apart: dockRoot.splitTravel > 0 ? dockRoot.splitProgress : dockRoot.lookApart", dock)
        self.assertIn("Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }", dock)
        self.assertIn("Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }", dock)
        self.assertNotIn("Behavior on border.width", dock)
        # The corners and the neck are keyed on the SEAM - the outward pair
        # rounds from it, the neck lives from it to the pinch - so the token
        # is read, not decorative.
        # With a neck to expose them, the outward corners round over the
        # neck's span; without one - no lift, or no shader to draw it (the
        # software scene graph) - over the whole scalar, or a square corner
        # hovered over a lit gap for the lift's first half (measured).
        self.assertIn("readonly property bool necked: dockRoot.splitTravel > 0 && splitNeck.fieldAvailable", dock)
        self.assertIn("dockVisualBackground.necked ? Appearance.animation.splitSeam : 0,\n                                dockVisualBackground.necked ? Appearance.animation.splitNeckReach : 1)", dock,
                      "the corners round over the neck's span - seam to pinch - or over the whole look scalar without a lift")
        neck = dock[dock.index("id: splitNeck"):]
        neck = neck[:neck.rfind("Rectangle {", 0, neck.index("id: dockVisualBackground"))]
        self.assertIn("DockGeometry.neckWaist(splitNeck.pillAlong, dockRoot.splitProgress, Appearance.animation.splitSeam, Appearance.animation.splitNeckReach)", neck)
        # ...and the neck is a distance field: ONE shader over one box from
        # the module, the way the reference builds it (motion-split.md §1),
        # boxed rather than anchored (the turn is a size), the blend keyed on
        # the seam and nothing at rest.
        self.assertIn("ShaderEffect {\n                            id: splitNeck", dock, "the neck is a shader")
        self.assertIn('fragmentShader: Qt.resolvedUrl("shaders/split.frag.qsb")', neck)
        self.assertIn("DockGeometry.neckBlend(dockRoot.splitTravel, dockRoot.splitProgress, Appearance.animation.splitSeam)", neck)
        # The box holds still for a whole motion; only uniforms move per frame.
        self.assertIn("readonly property var box: DockGeometry.splitBox(root.edge,", neck)
        self.assertNotRegex(neck, r"box: [^\n]*(splitLift|splitProgress|dockVisualBackground)", "the box is built from the rest margins, never the moving pill")
        self.assertIn("readonly property real reach: DockGeometry.fieldReach(dockRoot.splitLift)", neck)
        self.assertIn("readonly property real pixelRatio: dockRoot.devicePixelRatio", neck, "the window's ratio follows fractional scaling")
        self.assertIn("readonly property color fillColor: FrameGeometry.color", neck)
        self.assertIn("readonly property real softness: DockGeometry.BLEND_SOFTNESS", neck)
        # Where no shader can draw, the pill keeps its Rectangle: the software
        # scene graph draws no ShaderEffect, and a failed load draws nothing.
        self.assertIn("readonly property bool fieldAvailable: splitNeck.GraphicsInfo.api !== GraphicsInfo.Software", neck)
        self.assertIn("&& splitNeck.status !== ShaderEffect.Error", neck)
        self.assertIn("readonly property bool painting: splitNeck.fieldAvailable &&", neck)
        # ...and the shader stays inside core GLSL ES 1.00 - the profile an
        # OpenGL 2.1-class backend gets (issue #70, c76d6b7b): no derivatives.
        frag = (ROOT / "modules/imi/dock/shaders/split.frag").read_text()
        code = "\n".join(l.split("//")[0] for l in frag.splitlines())
        for construct in ("fwidth", "dFdx", "dFdy", "#extension"):
            self.assertNotIn(construct, code, construct)
        for gone in ("Shape {", "ShapePath {", "PathSvg", "Rectangle {", "RoundCorner", "layer.enabled", "anchors."):
            self.assertNotIn(gone, neck, gone)
        self.assertNotIn("import QtQuick.Shapes", dock)
        # While the field paints, the pill's Rectangle does not: the same
        # silhouette in the same colour at both hand-overs, and a translucent
        # fill drawn twice is darker. An opacity flip, never a colour with a
        # Behavior on it (that would fade the pill out).
        self.assertIn("opacity: splitNeck.painting ? 0 : 1", dock)
        self.assertNotIn("Behavior on opacity", dock)
        # A direction from part way takes a proportional time with the
        # effects tier as its floor (the reference's rule), and the tier's
        # curve whole.
        self.assertIn("duration: DockGeometry.splitDuration(Appearance.animation.split.duration, Appearance.animation.elementMoveFast.duration, splitBehavior.from, splitBehavior.targetValue)", behavior)
        self.assertIn("onTargetValueChanged: splitBehavior.from = dockRoot.splitProgress", behavior,
                      "the start is latched: a duration bound to the moving scalar shortens its own run every frame")
        self.assertNotRegex(behavior, r"duration: DockGeometry\.splitDuration\([^)]*dockRoot\.splitProgress")

    def test_the_split_shader_binary_is_built_from_its_source(self):
        # The shell loads split.frag.qsb, never split.frag: an edit to the
        # source that is not rebaked changes nothing on screen and reads as
        # a fix. qsb's output is byte-for-byte deterministic, so the
        # committed binary must equal a fresh bake with the same profiles
        # (the background module's six: GLSL ES 1.00 included).
        qsb = shutil.which("qsb") or next((p for p in ("/usr/lib/qt6/bin/qsb", "/usr/lib64/qt6/bin/qsb")
                                           if Path(p).exists()), None)
        if qsb is None:
            self.skipTest("Qt's qsb is not installed")
        shaders = ROOT / "modules/imi/dock/shaders"
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "split.frag.qsb"
            subprocess.run([qsb, "--glsl", "100 es,120,150", "--hlsl", "50", "--msl", "12",
                            "-o", str(out), str(shaders / "split.frag")], check=True, capture_output=True)
            self.assertEqual(out.read_bytes(), (shaders / "split.frag.qsb").read_bytes(),
                             "split.frag.qsb is stale: rebake it with the command in this test")

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
