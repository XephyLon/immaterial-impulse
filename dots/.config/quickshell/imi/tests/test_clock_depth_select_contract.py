#!/usr/bin/env python3
"""The desktop subject selector's surface, its arming, and its verdicts.

Picking the wallpaper's subject moved off a ~300px thumbnail in the wallpaper
selector and onto the desktop, at full size, over the real widgets. Almost
nothing about that is reachable from a unit test - qmltestrunner cannot
construct a layer surface, weston implements no wlr-layer-shell, and the one
thing the mode is for is a human looking at pixels - so the parts that ARE
source text are pinned here.

What each group is guarding, and why the failure would otherwise be silent:

  - THE SURFACE. Its whole design is that it redraws nothing: the wallpaper is
    already on screen at the size and crop the click has to be measured
    against, and the widgets are already under it. An `Image` appearing in that
    file is a second copy of the picture, which is a second chance to be
    misaligned - and a misalignment here reads as the model having picked the
    wrong thing.
  - THE CONVERSION. A click arrives in screen coordinates and has to reach the
    producer as a point in the picture. It goes screen -> the box the
    background published -> the rectangle ClockDepthCutout publishes ->
    `normalisedPoint`, and every step of that already exists. A second
    derivation - recomputing the crop here, or reading `coverRect` - would be a
    registration nothing else uses, which is the exact failure ClockDepthCutout
    was extracted to make impossible.
  - THE ARMING. Entering, escaping, accepting, declining, and the ground moving
    underneath (the wallpaper switching, the desktop ceasing to show a still).
    Every one of these leaves either a surface over a desktop it no longer
    describes, or a verdict recorded against the wrong picture.
  - THE PICKER. It is the way IN and the record of state now, not the place a
    mask is authored. The gesture coming back to it is a regression, not a
    convenience.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT.parents[1] / "hypr/hyprland/rules.lua"

SURFACE = ROOT / "modules/imi/clockDepthSelect/ClockDepthSelectSurface.qml"
MODE = ROOT / "modules/imi/clockDepthSelect/ClockDepthSelect.qml"
GLOBAL_STATES = ROOT / "GlobalStates.qml"
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
SERVICE = ROOT / "services/ClockDepth.qml"
PICKER = ROOT / "modules/imi/wallpaperSelector/ClockDepthPicker.qml"
SELECTOR = ROOT / "modules/imi/wallpaperSelector/WallpaperSelectorContent.qml"
FAMILY = ROOT / "panelFamilies/ImmaterialImpulseFamily.qml"

NAMESPACE = "quickshell:clockDepthSelect"


def strip_comments(source):
    """Drop comments, keeping newlines so line-anchored patterns still work.

    Needed in both directions here. Every rule below is explained in a comment
    beside the code that honours it, so a check reading raw text would find its
    own prose and pass on a file that had deleted the code - and a brace inside
    a comment would derail the block reader. String state is tracked because
    `file://` inside a template literal is not the start of a comment.
    """
    out = []
    index, length = 0, len(source)
    quote = None
    while index < length:
        char = source[index]
        if quote:
            out.append(char)
            if char == "\\" and index + 1 < length:
                out.append(source[index + 1])
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if char in "'\"`":
            quote = char
            out.append(char)
            index += 1
            continue
        if char == "/" and index + 1 < length and source[index + 1] == "/":
            while index < length and source[index] != "\n":
                index += 1
            continue
        if char == "/" and index + 1 < length and source[index + 1] == "*":
            end = source.find("*/", index + 2)
            end = length if end < 0 else end + 2
            out.append("\n" * source.count("\n", index, end))
            index = end
            continue
        out.append(char)
        index += 1
    return "".join(out)


def body_after(source, marker):
    """The brace-matched block that opens at the first `marker` in `source`.

    Brace-matched rather than line-scoped because every one of these bodies is
    written across several lines, and a line-scoped reader finds an opening
    brace, reports a clean file, and stops looking.
    """
    found = re.search(marker, source)
    if not found:
        return None
    opening = source.find("{", found.end() - 1)
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1:index]
    return None


def block_for(source, object_id):
    """The whole declaration of the object carrying `id: <object_id>`."""
    marker = re.search(rf"^\s*id:\s*{re.escape(object_id)}\s*$", source, re.MULTILINE)
    if not marker:
        return None
    opening = source.rfind("{", 0, marker.start())
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1:index]
    return None


def text(path):
    return strip_comments(path.read_text())


class TheSurfaceRedrawsNothing(unittest.TestCase):
    """The transparent-over-the-real-thing property, in source terms."""

    def setUp(self):
        self.surface = text(SURFACE)

    def test_the_surface_declares_no_image_of_its_own(self):
        # The wallpaper is on screen already. An Image here would be a second
        # copy of it, drawn from a second decode at a geometry this file worked
        # out for itself - and this feature has already spent an evening on a
        # misalignment that turned out not to exist.
        self.assertNotRegex(
            self.surface, r"(?<![\w.])Image\s*\{",
            "the selection surface must not draw a picture of its own - the "
            "wallpaper under it is the one the mask has to line up with")

    def test_the_surface_is_transparent_and_takes_the_whole_screen(self):
        self.assertIn('color: "transparent"', self.surface)
        for edge in ("left", "right", "top", "bottom"):
            self.assertRegex(self.surface, rf"{edge}:\s*true")

    def test_the_cutout_is_the_shared_component_with_its_revision(self):
        cutout = block_for(self.surface, "cutout")
        self.assertIsNotNone(cutout, "the surface draws no ClockDepthCutout")
        self.assertIn("ClockDepthCutout", self.surface)
        # Qt caches a pixmap by URL and the candidate is rewritten at the same
        # path on every click, so without the producer's token the preview
        # freezes on the first click's mask - which reads exactly like the
        # model ignoring every point after the first.
        self.assertRegex(cutout, r"maskRevision:\s*root\.maskRevision")

    def test_the_cutout_draws_the_candidate_not_the_accepted_mask(self):
        # ClockDepth.maskPath is only ever the ACCEPTED mask. A surface whose
        # whole job is judging something before it is accepted would show the
        # previous verdict and never change.
        self.assertRegex(
            self.surface,
            r"maskPath:\s*ClockDepth\.candidates\?\.\[root\.modelName\]")
        self.assertNotRegex(self.surface, r"maskPath:\s*ClockDepth\.maskPath")


class TheClickReachesThePicture(unittest.TestCase):
    def setUp(self):
        self.surface = text(SURFACE)

    def test_the_cutout_sits_in_the_box_the_background_published(self):
        frame = block_for(self.surface, "pictureFrame")
        self.assertIsNotNone(frame, "nothing carries the published viewport")
        for axis in ("x", "y", "width", "height"):
            self.assertRegex(
                frame, rf"{axis}:\s*root\.viewport\?\.{axis}",
                f"the picture frame's {axis} is not the published viewport's - "
                "the surface would be drawing against a geometry it guessed")
        self.assertRegex(
            self.surface,
            r"viewport:\s*GlobalStates\.clockDepthViewports\?\.\[root\.screen\.name\]",
            "the viewport must be read per screen: one wallpaper is cropped "
            "differently on every output")

    def test_the_conversion_is_the_one_that_already_exists(self):
        area = block_for(self.surface, "pointArea")
        self.assertIsNotNone(area, "the surface has no click area")
        self.assertIn("ClockDepthLogic.promptFromScreen", area)
        # Through the rectangle the cutout PUBLISHES, so the click is measured
        # against the same registration the mask is drawn with.
        self.assertIn("cutout.maskRect", area)

    def test_the_surface_derives_no_registration_of_its_own(self):
        # lint_clock_depth_geometry.py already fails the suite on a second
        # caller of coverRect; this is the same rule stated where the temptation
        # is - the surface knows the box and the picture's size and could work
        # the crop out again in three lines.
        self.assertNotIn("coverRect", self.surface)
        self.assertNotIn("PreserveAspectCrop", self.surface)

    def test_the_click_area_waits_for_the_wallpaper_to_decode(self):
        # An Image's implicit size reads 0 until its source resolves, and
        # coverRect answers a zero-sized source with the box itself - so a click
        # arriving in that window is measured against a frame the picture does
        # not occupy and sent to the producer as a point somewhere else.
        area = block_for(self.surface, "pointArea")
        self.assertRegex(area, r"enabled:[^\n]*cutout\.wallpaperStatus === Image\.Ready")
        self.assertRegex(area, r"enabled:[^\n]*root\.viewport !== null")

    def test_left_includes_and_right_excludes(self):
        area = block_for(self.surface, "pointArea")
        self.assertRegex(area, r"acceptedButtons:\s*Qt\.LeftButton \| Qt\.RightButton")
        self.assertRegex(
            area, r"ClockDepth\.addPoint\([^)]*mouse\.button === Qt\.LeftButton")


class TheSurfaceIsALayerSurfaceThisShellCanLiveWith(unittest.TestCase):
    def setUp(self):
        self.surface = text(SURFACE)
        self.rules = RULES.read_text()

    def test_it_mints_its_own_namespace(self):
        self.assertIn(f'WlrLayershell.namespace: "{NAMESPACE}"', self.surface)
        # Reusing quickshell:popup is the documented wrong answer: it carries
        # ignore_alpha = 1 from an old tooltip fix, which is right for an opaque
        # card and wrong for a screen-sized transparent one.
        self.assertNotIn('WlrLayershell.namespace: "quickshell:popup"', self.surface)

    def test_it_sits_above_everything_it_is_drawn_over(self):
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", self.surface)
        self.assertIn("exclusionMode: ExclusionMode.Ignore", self.surface)

    def test_its_keyboard_grab_is_not_session_wide(self):
        # One surface per output. An Exclusive grab is not scoped to the output
        # it was taken on, so it swallows what the user types on every other
        # screen - the trap Screensaver.qml records for a per-monitor blank.
        self.assertIn("WlrKeyboardFocus.OnDemand", self.surface)
        self.assertNotIn("WlrKeyboardFocus.Exclusive", self.surface)

    def test_the_layer_rules_exist_for_the_namespace(self):
        # Without them a screen-sized surface whose pixels are mostly
        # transparent falls through to the catch-all `ignore_alpha = 0.05` and
        # asks the compositor to blur the entire screen behind it, and gets a
        # map animation on something the size of the desktop.
        self.assertRegex(
            self.rules, rf'namespace = "{re.escape(NAMESPACE)}" \}}, no_anim = true')
        self.assertRegex(
            self.rules, rf'namespace = "{re.escape(NAMESPACE)}" \}}, blur = false')

    def test_the_toolbar_publishes_the_blur_region_that_rule_requires(self):
        # blur = false without a region is a panel with no blur at all rather
        # than one with a crisp shadow. lint_blur_region_pairing.py fails on the
        # pairing; this says which item the region is for.
        region = body_after(self.surface, r"WindowBlurRegion\s*\{")
        self.assertIsNotNone(region, "no WindowBlurRegion for the toolbar")
        self.assertIn("regionItem: chromeCard", region)

    def test_the_toolbar_keeps_its_own_clicks(self):
        # The click gesture covers the whole screen. Without a scrim under the
        # toolbar, pressing "Use this" also plants a point underneath it.
        chrome = block_for(self.surface, "chromeCard")
        self.assertIsNotNone(chrome, "the toolbar has no id to check")
        self.assertRegex(chrome, r"MouseArea\s*\{")
        self.assertRegex(chrome, r"acceptedButtons:\s*Qt\.AllButtons")


class TheVerdictsLiveHereNow(unittest.TestCase):
    def setUp(self):
        self.surface = text(SURFACE)
        self.mode = text(MODE)

    def test_escape_cancels_without_a_verdict(self):
        keys = body_after(self.surface, r"Keys\.onPressed:\s*event =>")
        self.assertIsNotNone(keys, "the surface handles no keys")
        self.assertIn("Qt.Key_Escape", keys)
        self.assertIn("root.cancelled()", keys)
        for verdict in ("acceptModel", "declineWallpaper", "accepted()", "declined()"):
            self.assertNotIn(
                verdict, keys,
                "Escape must leave without a verdict: the candidate stays on "
                "disk under its own key, so re-entering picks the gesture up")

    def test_accept_and_decline_are_both_reachable_from_the_surface(self):
        self.assertIn("root.accepted()", self.surface)
        self.assertIn("root.declined()", self.surface)
        self.assertIn("root.cancelled()", self.surface)

    def test_accepting_records_the_mask_and_turns_the_feature_on(self):
        accept = body_after(self.mode, r"function accept\(\)")
        self.assertIsNotNone(accept, "the mode has no accept()")
        self.assertIn("ClockDepth.acceptModel(ClockDepth.promptedModel)", accept)
        # Accepting while the global switch is off writes the artifact and
        # changes nothing on screen, which reads as the button not working.
        self.assertIn("Config.options.background.clockDepth.enable = true", accept)
        self.assertIn("root.cancel()", accept)

    def test_declining_records_the_refusal_and_leaves(self):
        decline = body_after(self.mode, r"function decline\(\)")
        self.assertIsNotNone(decline, "the mode has no decline()")
        self.assertIn("ClockDepth.declineWallpaper()", decline)
        self.assertIn("root.cancel()", decline)

    def test_cancelling_gives_no_verdict_at_all(self):
        cancel = body_after(self.mode, r"function cancel\(\)")
        self.assertIsNotNone(cancel, "the mode has no cancel()")
        self.assertIn("GlobalStates.clockDepthSelectOpen = false", cancel)
        for verdict in ("acceptModel", "declineWallpaper"):
            self.assertNotIn(verdict, cancel)


class TheModeDisarmsWhenTheGroundMoves(unittest.TestCase):
    def setUp(self):
        self.mode = text(MODE)

    def test_the_surfaces_are_gated_on_the_one_flag(self):
        self.assertRegex(self.mode, r"active:\s*GlobalStates\.clockDepthSelectOpen")
        self.assertRegex(self.mode, r"model:\s*Quickshell\.screens")

    def test_arming_captures_the_wallpaper_it_armed_on(self):
        armed = body_after(self.mode, r"function onClockDepthSelectOpenChanged\(\)")
        self.assertIsNotNone(armed, "nothing watches the arming flag")
        self.assertIn("ClockDepth.wallpaperPath", armed)
        self.assertIn("root.armedWallpaper", armed)

    def test_a_wallpaper_change_underneath_disarms(self):
        # The clicks are stored against the picture's cache key. If the picture
        # changes, every one of them belongs to a different file and the cutout
        # on screen is registered against something no longer there - and
        # nothing about that is visible, because a cutout of the wrong picture
        # is still a cutout.
        changed = body_after(self.mode, r"function onWallpaperPathChanged\(\)")
        self.assertIsNotNone(changed, "nothing watches the wallpaper")
        self.assertIn("root.armedWallpaper", changed)
        self.assertIn("root.cancel()", changed)

    def test_a_desktop_that_stops_showing_a_still_disarms(self):
        changed = body_after(self.mode, r"function onSelectableChanged\(\)")
        self.assertIsNotNone(changed, "nothing watches whether picking is possible")
        self.assertIn("ClockDepth.selectable", changed)
        self.assertIn("root.cancel()", changed)

    def test_the_mode_is_loaded_by_the_panel_family(self):
        # A module nothing loads is a module that is never wrong.
        family = text(FAMILY)
        self.assertIn("import qs.modules.imi.clockDepthSelect", family)
        self.assertRegex(family, r"PanelLoader \{ component: ClockDepthSelect \{\} \}")


class TheDesktopHandsOverItsGeometry(unittest.TestCase):
    def setUp(self):
        self.background = text(BACKGROUND)
        self.states = text(GLOBAL_STATES)
        self.service = text(SERVICE)

    def test_the_flag_and_the_map_are_declared(self):
        self.assertIn("property bool clockDepthSelectOpen: false", self.states)
        self.assertIn("property var clockDepthViewports: ({})", self.states)

    def test_the_two_full_screen_modes_exclude_each_other(self):
        # Edit Mode shrinks the desktop; picking must click the wallpaper at the
        # size it is masked at. Either arriving while the other is up leaves a
        # mode half-armed - a picker surface over a shrunk desktop maps every
        # click through geometry that is no longer on screen.
        #
        # Stated once in GlobalStates rather than as a gate inside either mode,
        # because the two landed from separate branches and a gate reading the
        # other's key resolves to `undefined` on a base that has not declared it
        # yet, and then takes its fallback forever.
        # The statement, not the handler's layout: onEditModeChanged became a
        # block when Edit Mode's drawer joined it (leaving the mode also
        # closes the drawer), and the exclusion this check exists for is the
        # `if` itself, wherever the handler puts its braces. The entry branch
        # then became a block of its own when stage 8 added the bar-popup
        # dismissal beside the exclusion, so BOTH brace positions are
        # optional - the pinned fact is that entering the mode closes the
        # picker, first thing in its branch.
        self.assertRegex(
            self.states,
            r"onEditModeChanged:\s*\{?\s*if\s*\(root\.editMode\)\s*\{?\s*root\.clockDepthSelectOpen = false")
        self.assertRegex(
            self.states,
            r"onClockDepthSelectOpenChanged:\s*\{?\s*if\s*\(root\.clockDepthSelectOpen\)\s*\{?\s*root\.editMode = false")

    def test_the_depth_layer_stands_down_while_a_selection_is_live(self):
        # The surface draws the candidate over the same widgets at the same
        # geometry. Left on, the accepted mask underneath would be a second
        # silhouette, and where the two disagree the difference reads as the
        # candidate having claimed something it did not.
        self.assertRegex(
            self.background, r"selecting:\s*GlobalStates\.clockDepthSelectOpen")

    def test_the_published_box_is_the_depth_layers_own(self):
        layer = block_for(self.background, "clockDepthLayer")
        self.assertIsNotNone(layer, "the depth layer is gone")
        published = re.search(
            r"publishedViewport:(.*?)onPublishedViewportChanged", layer, re.DOTALL)
        self.assertIsNotNone(published, "the layer publishes no viewport")
        value = published.group(1)
        for axis in ("x", "y", "width", "height"):
            self.assertRegex(
                value, rf"{axis}:\s*clockDepthLayer\.{axis}",
                f"the published {axis} is not the depth layer's own - the "
                "surface would draw its cutout somewhere the desktop does not")
        # The wallpaper ITEM's source, not the config path: a switch assigns
        # that source imperatively so it can snapshot the outgoing frame.
        self.assertRegex(value, r"source:\s*String\(wallpaper\.source\)")
        # Null while disarmed, so the binding is a comparison rather than a
        # fresh object on every frame of every pan for the rest of the session.
        self.assertRegex(value, r"GlobalStates\.clockDepthSelectOpen\s*\?")

    def test_the_publisher_is_keyed_per_screen_and_clears_on_disarm(self):
        publish = body_after(self.background, r"function publishDepthViewport\(viewport\)")
        self.assertIsNotNone(publish, "the background publishes nothing")
        self.assertIn("bgRoot.screen.name", publish)
        self.assertIn("delete published[bgRoot.screen.name]", publish)

    def test_the_service_keeps_watching_while_the_mode_is_armed(self):
        # ClockDepth forgets every cached answer the moment nothing is
        # watching, and the picker's claim dies with the picker as the wallpaper
        # selector closes. Read off the flag rather than given a second writer
        # of `picking`: one bool with two writers is cleared by whichever
        # surface goes away last, on an ordering nothing controls.
        watching = re.search(
            r"property bool watching:(.*?)\n\n", self.service, re.DOTALL)
        self.assertIsNotNone(watching, "the service declares no watching")
        self.assertIn("GlobalStates.clockDepthSelectOpen", watching.group(1))


class ThePickerIsTheWayInNotThePlaceToAuthor(unittest.TestCase):
    def setUp(self):
        self.picker = text(PICKER)
        self.selector = text(SELECTOR)

    def test_the_picker_no_longer_takes_the_clicks(self):
        # The whole point of the change. A ~300px preview is where a click on a
        # character's shoulder becomes several hundred pixels of error at
        # 5120x1440, and nothing about the resulting mask says so.
        for authoring in ("ClockDepth.addPoint", "ClockDepth.undoPoint",
                          "ClockDepth.clearPoints", "normalisedPoint"):
            self.assertNotIn(
                authoring, self.picker,
                f"{authoring} is back in the picker: the mask must be authored "
                "on the desktop, at the size it is judged at")

    def test_the_prompted_column_offers_the_way_in(self):
        self.assertIn("signal selectOnDesktopRequested()", self.picker)
        button = block_for(self.picker, "selectOnDesktopButton")
        self.assertIsNotNone(button, "the prompted column has no way onto the desktop")
        self.assertIn("visible: candidate.prompted", button)
        self.assertIn("root.selectOnDesktopRequested()", button)
        # Refusing while the desktop shows something else - a preview this
        # dialog's own grid reverts on close, a live Wallpaper Engine project -
        # is the difference between picking on the wallpaper and picking on
        # whatever is there afterwards.
        self.assertIn("ClockDepth.selectable", button)

    def test_the_prompted_column_no_longer_accepts_from_a_thumbnail(self):
        accept = block_for(self.picker, "acceptButton")
        self.assertIsNotNone(accept, "the picker has no accept button at all")
        self.assertIn("visible: !candidate.prompted", accept)

    def test_the_two_detectors_keep_their_run_and_their_accept(self):
        # Nothing about the salient columns changed, and a sweep that took them
        # out with the gesture would be a regression this file should name.
        run = block_for(self.picker, "runButton")
        self.assertIsNotNone(run, "the detectors lost their Run button")
        self.assertIn("ClockDepth.runModel(candidate.modelName)", run)
        self.assertIn("ClockDepth.acceptModel(candidate.modelName)", self.picker)
        self.assertIn("ClockDepth.declineWallpaper()", self.picker)

    def test_entering_arms_before_either_surface_closes(self):
        handler = body_after(self.selector, r"onSelectOnDesktopRequested:")
        self.assertIsNotNone(handler, "the selector does not answer the picker")
        armed = handler.index("GlobalStates.clockDepthSelectOpen = true")
        closed = handler.index("GlobalStates.wallpaperSelectorOpen = false")
        self.assertLess(
            armed, closed,
            "arm first: ClockDepth keeps its cache answers only while "
            "something is watching, and destroying the picker drops its claim - "
            "so arming afterwards lets the service forget the candidate the "
            "user is about to judge")


if __name__ == "__main__":
    unittest.main()


class TheClickHistoryIsWholeStates(unittest.TestCase):
    """Undo and redo over the selection gesture.

    The history keeps whole point lists rather than a stack of "remove the last
    click", because start-over has to be one undo away like every other step. A
    pop-the-last-point stack cannot express it: clearing four points would cost
    four undos, or be unrecoverable, and both read as the history having lost
    the gesture.
    """

    def setUp(self):
        self.service = text(SERVICE)
        self.surface = text(SURFACE)

    def test_every_edit_goes_through_one_commit(self):
        # If an edit writes root.points directly it is invisible to undo, and
        # the failure is silent - the button simply skips a step.
        for name in ("addPoint", "clearPoints"):
            body = re.search(r"function %s\(.*?\n    \}" % name, self.service, re.DOTALL)
            self.assertIsNotNone(body, "%s is gone" % name)
            self.assertIn("commitPoints", body.group(0),
                          "%s edits the points without the history seeing it" % name)

    def test_adopting_a_stored_prompt_is_not_an_undoable_step(self):
        # Reading a prompt off disk is where a gesture starts. If it were a
        # step, undo would walk back into a previous session's clicks.
        body = re.search(r"function adoptPoints\(.*?\n    \}", self.service, re.DOTALL)
        self.assertIsNotNone(body, "adoptPoints is gone")
        self.assertIn("root.pointHistory = []", body.group(0))
        self.assertIn("root.pointFuture = []", body.group(0))

    def test_a_new_click_forgets_the_redo_branch(self):
        body = re.search(r"function commitPoints\(.*?\n    \}", self.service, re.DOTALL)
        self.assertIsNotNone(body, "commitPoints is gone")
        self.assertIn("root.pointFuture = []", body.group(0))

    def test_both_chords_reach_the_service(self):
        keys = re.search(r"Keys\.onPressed:.*?\n        \}", self.surface, re.DOTALL)
        self.assertIsNotNone(keys, "the surface handles no keys")
        block = keys.group(0)
        self.assertIn("Qt.ControlModifier", block)
        self.assertIn("Qt.ShiftModifier", block)
        self.assertIn("ClockDepth.undoPoint()", block)
        self.assertIn("ClockDepth.redoPoint()", block)

    def test_undo_is_offered_while_there_is_history_not_while_there_are_points(self):
        # After "Start over" there are no points and undo must still be live.
        undo = re.search(r"id: undoButton.*?\n                \}", self.surface, re.DOTALL)
        self.assertIsNotNone(undo, "the undo button is gone")
        self.assertIn("ClockDepth.pointHistory.length > 0", undo.group(0))
        self.assertNotIn("root.points.length", undo.group(0))
