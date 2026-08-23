#!/usr/bin/env python3
"""A surface that animates on its way out is owned by that animation.

Layer-shell forbids window reuse, so a panel whose `visible` follows the flag
that asks for it is destroyed on the frame the flag drops - and anything the
QML was drawing at that moment is simply not drawn. That is the whole reason
the overview had no exit: `rules.lua` turns the compositor's own map animation
off for `quickshell:overview` (a map animation on a screen-sized surface reads
as the desktop lurching), the window went away with the flag, and between the
two there was nothing left to animate at either end.

The repair is one shape, and this file pins it at both of the surfaces that
have it, because the shape is what decays:

**The flag the window follows is NOT the flag the user's gesture sets.** A
second flag stays true through the exit and is cleared by the exit animation's
own `onFinished`. Never a `Timer` at the exit tier's duration:
`modules/imi/wallpaperSelector/WallpaperSelector.qml` was written that way
first, and measured on a 60fps capture the timer fired with a quarter of the
travel left - the last frame drawn was 74.6% of the way out and the next one
had no panel in it. A Behavior's animation starts a frame after the write that
triggers it and an accelerating curve carries most of its distance in its last
frames, so the two ends were never going to line up. An animation's own
`finished` cannot be early or late.

**One scalar drives every channel of the transition.** docs/M3_GUIDELINES.md §2
asks the opacity to finish on the same schedule as the scale; two animations at
two tiers is what makes a component reach full opacity while it is still
growing. The check reads the tier names out of each animation and refuses a
duration taken from one tier with a curve taken from another - a mismatch that
reads perfectly in review, since both halves name a real catalogued tier.

**And a blur region is not part of the card it sits behind.** The compositor
frosts the rectangle whether or not anything is drawn over it, so a region
gated on the open flag arrives an entrance before the card and stays an exit
after it - a frosted ghost with no card in it. The overview's regions follow
the card's own progress instead.

Every sweep asserts it FOUND what it swept for. A regex over QML that matches
nothing reads exactly like a regex over QML that found nothing wrong.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
OVERVIEW = ROOT / "modules/imi/overview/Overview.qml"
SELECTOR = ROOT / "modules/imi/wallpaperSelector/WallpaperSelector.qml"

# The declaration that maps the surface, and the property on it that decides
# whether the compositor has one. The overview's window is built unconditionally
# and toggles its own `visible`; the selector's is built by a Loader and toggles
# that Loader's `active`. Both mean "the surface exists", and both must read the
# lifetime flag rather than the flag the gesture sets.
#
# The gate is read at the mapping declaration's OWN top level rather than
# anywhere in the file. A sweep for "some `visible:` line mentions the lifetime
# flag" passes on a tree where the window has been put back on the gesture's
# flag and only the card inside it still reads the right one - which is the
# exact regression this file exists to catch, and it survived the first draft.
LIFETIME_FLAG = "reallyOpen"
SURFACES = {OVERVIEW: ("PanelWindow", "visible"), SELECTOR: ("Loader", "active")}


def read(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    assert text.strip(), f"{path} is empty"
    return text


def code(path: Path) -> str:
    """The file with its comments stripped, so a rule cannot be satisfied by
    prose about the rule."""
    text = read(path)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def logical_lines(text: str):
    """Source lines with wrapped expressions joined back onto one.

    A property whose value does not fit on a line is continued on the next one,
    starting with the operator it is continued by. A line-scoped scan reads
    those two halves as two lines, finds a `scale:` with nothing in it, and
    reports a clean tree - which is exactly what this file's job is not.
    """
    joined = []
    for line in text.splitlines():
        stripped = line.strip()
        if joined and stripped[:1] in {"+", "-", "*", "/", "?", ":", ".", "&", "|", ")", ","}:
            joined[-1] = joined[-1] + " " + stripped
        else:
            joined.append(line)
    return joined


def blocks(text: str, type_name: str):
    """Every `<type_name> { ... }` declaration in the file, brace-matched.

    Brace matching rather than a line scan: every property these rules judge
    sits on a continuation line, and a line-scoped check finds the opening
    brace and reports a clean tree.
    """
    found = []
    for opener in re.finditer(rf"(?<![\w.]){re.escape(type_name)}\s*\{{", text):
        start = opener.end() - 1
        depth = 0
        for index in range(start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    found.append(text[start:index + 1])
                    break
    return found


def mapping_block(text: str, type_name: str, name: str) -> str:
    """The one declaration in the file that maps a layer surface.

    Anchored on `WlrLayershell.namespace` rather than on being the first block
    of its type: a file may declare several Loaders, and only one of them has a
    window under it.
    """
    owning = [block for block in blocks(text, type_name)
              if "WlrLayershell.namespace" in block]
    assert len(owning) == 1, \
        (f"{name} has {len(owning)} {type_name} declarations carrying a layer "
         "surface - this rule is about the one that maps it")
    return owning[0]


def declared_at_top_level(block: str, prop: str):
    """Values of `prop:` declared directly on `block`, not on anything nested
    inside it."""
    values = []
    depth = 0
    for line in logical_lines(block):
        if depth == 1:
            match = re.match(rf"\s*{prop}\s*:(.*)", line)
            if match:
                values.append(match.group(1).strip())
        depth += line.count("{") - line.count("}")
    return values


def test_the_surface_outlives_the_gesture_by_one_exit_animation():
    for path, (declaration, gate) in SURFACES.items():
        text = code(path)
        name = path.relative_to(ROOT).as_posix()

        assert re.search(rf"property\s+bool\s+{LIFETIME_FLAG}\b", text), \
            (f"{name} has no `{LIFETIME_FLAG}` - its surface is back to living "
             "and dying with the flag the user's gesture sets, and its exit "
             "animation is drawing into a window that is already gone")

        gates = declared_at_top_level(
            mapping_block(text, declaration, name), gate)
        assert gates, \
            (f"{name}'s {declaration} declares no `{gate}:` of its own - "
             "nothing here says when the surface exists")
        assert all(LIFETIME_FLAG in value for value in gates), \
            (f"{name}'s {declaration} maps on `{gate}: {gates}` - the surface "
             f"must follow `{LIFETIME_FLAG}`, not the gesture's own flag, or it "
             "is destroyed on the frame the exit animation starts")

        clears = [line.strip() for line in logical_lines(text)
                  if re.search(rf"{LIFETIME_FLAG}\s*=\s*false", line)]
        assert clears, \
            (f"{name} never clears `{LIFETIME_FLAG}` - the surface is now "
             "mapped for the rest of the session")
        for line in clears:
            assert "onFinished" in line, \
                (f"{name} clears `{LIFETIME_FLAG}` at `{line}` - the window's "
                 "lifetime belongs to the exit animation's own `onFinished`. A "
                 "Timer at the exit tier's duration tore the wallpaper selector "
                 "down with 25% of its travel still to draw.")


def test_one_scalar_and_one_tier_per_animation():
    for path in SURFACES:
        text = code(path)
        name = path.relative_to(ROOT).as_posix()

        scalars = set(re.findall(r'property\s*:\s*"(\w+)"', text))
        assert len(scalars) == 1, \
            (f"{name} animates {sorted(scalars)} - the entrance and the exit are "
             "one scalar, or the opacity and the scale finish on two schedules "
             "and the surface reads as hiccuping (docs/M3_GUIDELINES.md §2)")

        animations = [block for block in blocks(text, "NumberAnimation")
                      if "Appearance.animation." in block]
        assert len(animations) == 2, \
            (f"{name} has {len(animations)} catalogued animations, not the "
             "entrance and exit pair this rule is about")
        for block in animations:
            tiers = set(re.findall(r"Appearance\.animation\.(\w+)\.", block))
            assert len(tiers) == 1, \
                (f"{name} builds one animation out of tiers {sorted(tiers)} - a "
                 "duration from one tier with a curve from another names two "
                 "real tiers and reads correctly, and is neither of them")


def test_the_overview_card_arrives_rather_than_appears():
    text = code(OVERVIEW)

    assert "transformOrigin: Item.Top" in text, \
        ("the overview card has no transform origin - it hangs from the top of "
         "its surface, and scaling about its centre reads as a card growing in "
         "mid-air rather than unfurling out of the edge it is fastened to")

    driven = [line.strip() for line in logical_lines(text)
              if re.match(r"\s*(opacity|scale)\s*:", line)
              and "openProgress" in line]
    assert len(driven) == 2, \
        (f"only {driven} follow `openProgress` - both the opacity and the scale "
         "take the one scalar, or the entrance is two transitions")


def test_the_blur_region_follows_the_card_not_the_flag():
    regions = blocks(code(OVERVIEW), "WindowBlurRegion")
    assert len(regions) == 1, \
        f"expected one WindowBlurRegion in the overview, found {len(regions)}"
    assert "GlobalStates.overviewOpen" not in regions[0], \
        ("the overview's blur regions are gated on the open flag again - the "
         "compositor frosts that rectangle whether or not the card is drawn "
         "over it, so the frost arrives a whole entrance early and leaves a "
         "whole exit late, as a ghost of a card that is not there")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
