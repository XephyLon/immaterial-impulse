#!/usr/bin/env python3
"""The depth layer's geometry is a two-sided contract with the wallpaper item.

The layer paints the wallpaper's own pixels back over the desktop widgets and
masks them, so it only reads as depth while it is drawing exactly the crop the
image under it is drawing. Every way that can break is silent on screen and
invisible to a unit test - the software scene graph draws no layer effect and
qmltestrunner cannot construct these types at all - so the parts that are source
text are checked here.

Four of these are bugs this file has already shipped once, in other features:

  - binding the pan to `parallaxOffsets` rather than to the viewport's live x/y
    reads the 600ms Behavior's DESTINATION, so the cutout arrives before the
    wallpaper under it (#157, ca667957a);
  - a top-level visual child without its own `!bgRoot.suppressContents` copy
    stays on screen when a fullscreen window hides the wallpaper;
  - an input-taking item over the desktop swallows the right-click menu and
    every widget drag, and nothing reports it;
  - a fill mode that disagrees with the `wallpaper` item is both a different
    crop AND, because the aspect flags are part of Qt's image request, a second
    full-resolution decode of a file that is already in the cache.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
CUTOUT = ROOT / "modules/imi/background/ClockDepthCutout.qml"

LAYER_ID = "clockDepthLayer"
CANVAS_ID = "widgetCanvas"
CUTOUT_TYPE = "ClockDepthCutout"
DEPTH_IMAGE_ID = "cutoutWallpaper"
MASK_SURFACE_ID = "maskSurface"
PAINTED_SOURCE = "paintedSource"
LIVE_SOURCE = "liveSource"
WALLPAPER_ID = "wallpaper"

# The registration - un-squashing the model's square mask and re-applying the
# wallpaper's crop - is computed in exactly one file. Two call sites draw this
# cutout: the desktop layer, and the picker that asks the user whether it is any
# good. A picker that derived its own crop would certify a mask against a
# geometry the desktop never uses, which is a visualizer that lies about the one
# thing it exists to judge.
REGISTRATION_FUNCTION = "coverRect"

INPUT_TYPES = ("MouseArea", "MultiPointTouchArea", "Flickable", "HoverHandler",
               "TapHandler", "DragHandler", "PointHandler", "WheelHandler",
               "PinchHandler")

# Properties that must be copied from the wallpaper item, because a difference
# in any of them is a different crop or a different image request.
SHARED_IMAGE_PROPERTIES = ("fillMode", "cache", "smooth", "asynchronous")

failures = []


def fail(message):
    failures.append(message)


def strip_comments(source):
    """Drop comments, keeping every newline so line-anchored patterns still work.

    Needed in both directions. A comment mentioning `parallaxOffsets` to explain
    why the layer does not read it would otherwise fail this check on its own
    prose - a check that trips on an explanation is a check someone deletes -
    and a brace inside one would derail the brace matcher. String state is
    tracked because `file://` inside a template literal is not a comment.
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


def block_for(source, object_id):
    """The whole declaration of the object carrying `id: <object_id>`.

    Brace-matched rather than line-scoped: every interesting property here is a
    binding that may be written across several lines, and a line-scoped reader
    finds the opening of a block and reports a clean tree.
    """
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


def type_block(source, type_name):
    """The whole declaration of the first `<TypeName> { ... }` in `source`.

    Brace-matched for the same reason `block_for` is, and deliberately not
    anchored on indentation: a check whose pattern bakes in the column its
    target currently sits at stops matching after any reformat, and passes
    vacuously rather than reporting that it has stopped looking.
    """
    marker = re.search(rf"(?<![\w.]){re.escape(type_name)}\s*\{{", source)
    if not marker:
        return None
    opening = source.index("{", marker.start())
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


def declaration(block, name):
    """One property's whole value, block-bodied values included."""
    marker = re.search(rf"^(\s*)(?:readonly\s+)?(?:property\s+\S+\s+)?{re.escape(name)}:\s*",
                       block, re.MULTILINE)
    if not marker:
        return None
    rest = block[marker.end():]
    depth = 0
    for index, char in enumerate(rest):
        if char in "{([":
            depth += 1
        elif char in "})]":
            if depth == 0:
                return rest[:index].strip()
            depth -= 1
        elif char == "\n" and depth == 0:
            return rest[:index].strip()
    return rest.strip()


def check(raw, cutout_raw=None):
    source = strip_comments(raw)
    cutout = strip_comments(cutout_raw if cutout_raw is not None else raw)
    layer = block_for(source, LAYER_ID)
    if layer is None:
        fail(f"no object carries `id: {LAYER_ID}` - the depth layer is gone")
        return

    for axis in ("x", "y", "width", "height"):
        value = declaration(layer, axis)
        expected = f"parallaxViewport.{axis}"
        if value != expected:
            fail(f"{LAYER_ID}.{axis} is {value!r}, expected {expected!r}: the layer "
                 f"must follow the viewport's live geometry, not the pan's target")

    if "parallaxOffsets" in layer:
        fail(f"{LAYER_ID} reads parallaxOffsets - that is the 600ms Behavior's "
             f"destination, so the subject would arrive before its own wallpaper")

    visible = declaration(layer, "visible")
    if visible is None or "!bgRoot.suppressContents" not in visible:
        fail(f"{LAYER_ID}.visible is {visible!r} and does not carry "
             f"!bgRoot.suppressContents: a top-level visual child needs its own "
             f"copy of the fullscreen gate")

    if declaration(layer, "enabled") != "false":
        fail(f"{LAYER_ID} does not declare `enabled: false` - the depth layer "
             f"must take no input")

    for kind in INPUT_TYPES:
        if re.search(rf"^\s*{kind}\s*\{{", layer, re.MULTILINE):
            fail(f"{LAYER_ID} contains a {kind}: an input-taking item over the "
                 f"desktop swallows the right-click menu and every widget drag")

    canvas = block_for(source, CANVAS_ID)
    layer_z = declaration(layer, "z")
    canvas_z = declaration(canvas, "z") if canvas else None
    try:
        if not (int(layer_z) > int(canvas_z)):
            fail(f"{LAYER_ID}.z ({layer_z}) is not above {CANVAS_ID}.z ({canvas_z}) - "
                 f"the cutout would be drawn under the clock, which is the effect "
                 f"the shell already had")
    except (TypeError, ValueError):
        fail(f"could not read both z values ({LAYER_ID}={layer_z!r}, "
             f"{CANVAS_ID}={canvas_z!r})")

    if not re.search(rf"^\s*{CUTOUT_TYPE}\s*\{{", layer, re.MULTILINE):
        fail(f"{LAYER_ID} does not draw a {CUTOUT_TYPE}: the registration must "
             f"come from the component the picker also draws, or the two can "
             f"disagree about where the mask lands")

    depth_image = block_for(cutout, DEPTH_IMAGE_ID)
    wallpaper = block_for(source, WALLPAPER_ID)
    if depth_image is None or wallpaper is None:
        fail(f"could not find both {DEPTH_IMAGE_ID} and {WALLPAPER_ID}")
        return
    for name in SHARED_IMAGE_PROPERTIES:
        mine, theirs = declaration(depth_image, name), declaration(wallpaper, name)
        if mine != theirs:
            fail(f"{DEPTH_IMAGE_ID}.{name} is {mine!r} but {WALLPAPER_ID}.{name} is "
                 f"{theirs!r}: the mask would crop differently from the image it "
                 f"masks, and the two images would no longer share one decode")
    # Not "the same expression as the wallpaper item's" - the wallpaper item has
    # no declarative source at all, because a switch assigns it imperatively so
    # it can snapshot the outgoing frame first. Reading the path instead would
    # put the incoming image under the outgoing image's mask for the length of
    # every switch, so the depth image follows the ITEM.
    cutout_use = type_block(layer, CUTOUT_TYPE)
    source_binding = declaration(cutout_use, "wallpaperSource") if cutout_use else None
    if source_binding != f"{WALLPAPER_ID}.source":
        fail(f"{CUTOUT_TYPE}.wallpaperSource is {source_binding!r}, expected "
             f"{WALLPAPER_ID + '.source'!r}: it must draw whatever the wallpaper "
             f"item is drawing, not whatever the config currently names")

    # Qt caches a pixmap by URL, and the accepted mask is rewritten AT THE SAME
    # PATH whenever a second candidate is accepted for the same wallpaper - so a
    # layer that names the path without the producer's revision token draws
    # whichever mask happened to load first, for the rest of the session, with
    # nothing in any log. Measured with a qml6 probe: re-assigning the identical
    # URL after the file changed still served the old bytes, and clearing the
    # source to "" first did not help.
    revision_binding = declaration(cutout_use, "maskRevision") if cutout_use else None
    if not revision_binding:
        fail(f"{CUTOUT_TYPE} is given no maskRevision: the accepted mask is "
             f"rewritten in place, and Qt would keep serving the cached one")

    # Without the mask the layer is a copy of the wallpaper drawn at full
    # opacity over the clock - the loudest possible version of this feature's
    # own failure, and one that nothing else here would notice, because every
    # geometry check above still passes on it.
    mask = re.search(r"OpacityMask\s*\{(.*?)\}", cutout, re.DOTALL)
    if not mask:
        fail(f"{CUTOUT_TYPE} contains no OpacityMask: the layer would paint the "
             f"whole wallpaper over the clock, not the subject")
    else:
        body = mask.group(1)
        # The mask paints the wallpaper image OR a live Wallpaper Engine surface
        # handed in by the desktop layer (spec §8.3), through one property whose
        # fallback has to be the image - so a call site that hands in nothing
        # still draws the wallpaper, and the source the two-image sharing rule
        # above is about is still the one that gets painted.
        painted = declaration(cutout, PAINTED_SOURCE)
        if declaration(body, "source") != f"root.{PAINTED_SOURCE}":
            fail(f"the OpacityMask does not paint root.{PAINTED_SOURCE}")
        if painted != f"root.{LIVE_SOURCE} ?? {DEPTH_IMAGE_ID}":
            fail(f"{PAINTED_SOURCE} is {painted!r}, expected "
                 f"'root.{LIVE_SOURCE} ?? {DEPTH_IMAGE_ID}': with no live surface "
                 f"the mask must fall back to {DEPTH_IMAGE_ID}")
        if declaration(body, "maskSource") != MASK_SURFACE_ID:
            fail(f"the OpacityMask's maskSource is not {MASK_SURFACE_ID}")
    surface = block_for(cutout, MASK_SURFACE_ID)
    if surface is None:
        fail(f"no object carries `id: {MASK_SURFACE_ID}`")
    elif declaration(surface, "clip") != "true":
        fail(f"{MASK_SURFACE_ID} does not clip: the mask is drawn oversized and "
             f"offset, and uncropped it masks the wrong pixels")


SELF_CHECK_BACKGROUND = """
Item {
    id: widgetCanvas
    z: 2
}
Item {
    id: clockDepthLayer
    x: parallaxViewport.x
    y: parallaxViewport.y
    width: parallaxViewport.width
    height: parallaxViewport.height
    z: 3
    visible: !bgRoot.suppressContents && clockDepthLayer.opacity > 0
    enabled: false
    ClockDepthCutout {
        id: clockDepthCutout
        anchors.fill: parent
        wallpaperSource: wallpaper.source
        maskPath: ClockDepth.maskPath
        maskRevision: ClockDepth.maskRevision
    }
}
Image {
    id: wallpaper
    fillMode: Image.PreserveAspectCrop
    cache: true
    smooth: true
    asynchronous: true
}
"""

SELF_CHECK_CUTOUT = """
Item {
    id: root
    property Item liveSource: null
    readonly property Item paintedSource: root.liveSource ?? cutoutWallpaper
    Image {
        id: cutoutWallpaper
        anchors.fill: parent
        source: root.wallpaperSource
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        asynchronous: true
        visible: false
    }
    Item {
        id: maskSurface
        anchors.fill: parent
        visible: false
        clip: true
        Image { id: mask; fillMode: Image.Stretch }
    }
    OpacityMask {
        anchors.fill: parent
        source: root.paintedSource
        maskSource: maskSurface
    }
}
"""


def registration_callers():
    """Every file that computes the mask's placement for itself.

    The rule is one caller, and it is the whole reason the cutout became a
    component: the desktop layer and the picker that judges its output must be
    unable to disagree about where the mask lands, because a picker registered
    differently from the layer certifies a mask against a geometry nothing ever
    draws. A second caller is not a duplicate to tidy up later - it is a
    visualizer that can start lying without anything reporting it.
    """
    callers = []
    for path in sorted(ROOT.rglob("*.qml")) + sorted(ROOT.rglob("*.js")):
        if path.name == "clockDepth.js":
            continue
        try:
            text = strip_comments(path.read_text())
        except (OSError, UnicodeDecodeError):
            continue
        if re.search(rf"\.{REGISTRATION_FUNCTION}\s*\(", text):
            callers.append(path.relative_to(ROOT).as_posix())
    return callers


def check_one_registration():
    callers = registration_callers()
    # The eligibility unit test is the function's own test, which is the one
    # place calling it is not a second registration - it asserts the arithmetic
    # rather than drawing anything with it.
    expected = sorted([CUTOUT.relative_to(ROOT).as_posix(),
                       "tests/tst_clock_depth_eligibility.qml"])
    if sorted(callers) != expected:
        fail(f"{REGISTRATION_FUNCTION} is called from {callers}, expected only "
             f"{expected}: the mask's placement is computed in one file so the "
             f"picker cannot show a registration the desktop does not use")


def self_check():
    """Prove the machinery independently of what the tree happens to contain.

    A source-text check that silently stops matching is worse than no check, and
    an extractor is exactly the part that stops matching after a reformat.
    """
    global failures
    saved, failures = failures, []
    check(SELF_CHECK_BACKGROUND, SELF_CHECK_CUTOUT)
    clean = failures
    background_mutations = {
        "pan bound to the target": SELF_CHECK_BACKGROUND.replace(
            "x: parallaxViewport.x", "x: bgRoot.parallaxOffsets.x"),
        "fullscreen gate dropped": SELF_CHECK_BACKGROUND.replace(
            "visible: !bgRoot.suppressContents && clockDepthLayer.opacity > 0",
            "visible: clockDepthLayer.opacity > 0"),
        "input gate dropped": SELF_CHECK_BACKGROUND.replace("    enabled: false\n", ""),
        "a MouseArea in the layer": SELF_CHECK_BACKGROUND.replace(
            "    ClockDepthCutout {",
            "    MouseArea { anchors.fill: parent }\n    ClockDepthCutout {"),
        "drawn below the clock": SELF_CHECK_BACKGROUND.replace("    z: 3", "    z: 1"),
        "fill mode diverged": SELF_CHECK_BACKGROUND.replace(
            "    id: wallpaper\n    fillMode: Image.PreserveAspectCrop",
            "    id: wallpaper\n    fillMode: Image.Stretch"),
        "the layer removed": SELF_CHECK_BACKGROUND.replace(
            "id: clockDepthLayer", "id: somethingElse"),
        "the cutout chasing the config path": SELF_CHECK_BACKGROUND.replace(
            "wallpaperSource: wallpaper.source", "wallpaperSource: bgRoot.wallpaperPath"),
        "the layer rebuilding the cutout itself": SELF_CHECK_BACKGROUND.replace(
            "    ClockDepthCutout {\n        id: clockDepthCutout\n        anchors.fill: parent\n"
            "        wallpaperSource: wallpaper.source\n        maskPath: ClockDepth.maskPath\n"
            "        maskRevision: ClockDepth.maskRevision\n    }",
            "    Image { id: hand; source: wallpaper.source }"),
        "the mask cache-buster dropped": SELF_CHECK_BACKGROUND.replace(
            "        maskRevision: ClockDepth.maskRevision\n", ""),
    }
    cutout_mutations = {
        "the mask dropped entirely": re.sub(
            r"OpacityMask \{.*?\n    \}\n", "", SELF_CHECK_CUTOUT, flags=re.DOTALL),
        "the mask surface no longer clips": SELF_CHECK_CUTOUT.replace(
            "        clip: true\n", ""),
        "the OpacityMask masking something else": SELF_CHECK_CUTOUT.replace(
            "        maskSource: maskSurface", "        maskSource: somethingElse"),
        "the OpacityMask painting the image directly, live surface unreachable":
            SELF_CHECK_CUTOUT.replace(
                "        source: root.paintedSource", "        source: cutoutWallpaper"),
        "the painted source no longer falling back to the wallpaper image":
            SELF_CHECK_CUTOUT.replace(
                "readonly property Item paintedSource: root.liveSource ?? cutoutWallpaper",
                "readonly property Item paintedSource: root.liveSource"),
        "the cutout image no longer shares the wallpaper's request":
            SELF_CHECK_CUTOUT.replace(
                "        fillMode: Image.PreserveAspectCrop", "        fillMode: Image.Stretch"),
    }
    # The comment stripper is the half that decides whether any of the above
    # ever matches again once someone documents a refusal in the same words the
    # check greps for - which is exactly what the layer's own comments do.
    documented = SELF_CHECK_BACKGROUND.replace(
        "    x: parallaxViewport.x",
        "    // deliberately NOT bgRoot.parallaxOffsets, see #157 { unbalanced\n"
        "    x: parallaxViewport.x")
    problems = []
    if clean:
        problems.append(f"the reference tree does not pass: {clean}")
    for name, mutated in background_mutations.items():
        failures = []
        check(mutated, SELF_CHECK_CUTOUT)
        if not failures:
            problems.append(f"the check does not notice: {name}")
    for name, mutated in cutout_mutations.items():
        failures = []
        check(SELF_CHECK_BACKGROUND, mutated)
        if not failures:
            problems.append(f"the check does not notice: {name}")
    failures = []
    check(documented, SELF_CHECK_CUTOUT)
    if failures:
        problems.append(f"a comment naming the trap fails the check: {failures}")
    failures = saved
    return problems


def main():
    problems = self_check()
    if problems:
        for problem in problems:
            print(f"clock depth geometry lint SELF-CHECK: {problem}", file=sys.stderr)
        return 1

    check(BACKGROUND.read_text(), CUTOUT.read_text())
    check_one_registration()
    if failures:
        for message in failures:
            print(f"clock depth geometry lint: {message}", file=sys.stderr)
        return 1
    print("Clock depth geometry lint passed: the layer follows the viewport, "
          "gates on fullscreen, takes no input, shares the wallpaper's request "
          "and registers the mask in one place")
    return 0


if __name__ == "__main__":
    sys.exit(main())
