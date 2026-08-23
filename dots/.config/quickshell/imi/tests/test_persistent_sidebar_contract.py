#!/usr/bin/env python3
"""A sidebar's surface stays mapped; the panel is what opens.

Layer-shell forbids window reuse, so a PanelWindow whose `visible` follows the
flag that asks for it is destroyed on every close and rebuilt on every open: a
new render thread, a new GL context, the scene graph built from nothing and
every glyph uploaded again. The shell has ONE GUI thread for all of its
windows. Measured with QSG_RENDER_TIMING on the real session, that thread sat
blocked for 61ms per sidebar open (`blockedForSync=61 ms, polish=0`) - every
window the shell draws frozen for fifteen frames at 240Hz, reported as "a
momentary freeze right before they open". With the window kept mapped and the
slide drawn by `EdgeSlide`, the same gesture blocks it for 1-3ms.

A persistent surface is a surface that can take input and focus while showing
nothing, and both sidebars had a property that was harmless only BECAUSE the
window used to be unmapped when closed. So the shape is four rules, read at
the declaration that maps the surface, and every one of them is a defect one
of these two files has had:

- the PanelWindow declares no `visible:` that reads the open flag (or any
  lifetime flag derived from it); the surface is mapped for the life of the
  shell;
- its `mask:` reads the open flag, so a closed panel is a hole the pointer
  falls through rather than a strip down the screen edge that eats clicks;
- its `WlrLayershell.keyboardFocus:` reads the open flag - the left sidebar's
  was an unconditional OnDemand, which on a mapped surface holds the keyboard;
- it declares an `EdgeSlide`, and the content's `visible:` reads that
  runner's `shown`, not the flag: the flag drops on frame one of the exit.

And `rules.lua` carries `no_anim` for both namespaces, not the slide rules
EdgeSlide replaced: a map animation fires once, at startup, on an empty
surface, and would fire a second time on top of the QML slide whenever a
remap happens.

Every sweep asserts it FOUND what it swept for.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT.parents[1] / "hypr/hyprland/rules.lua"
RUNNER = ROOT / "modules/common/widgets/EdgeSlide.qml"

SIDEBARS = {
    ROOT / "modules/imi/sidebarRight/SidebarRight.qml": ("GlobalStates.sidebarRightOpen", "quickshell:sidebarRight"),
    ROOT / "modules/imi/sidebarLeft/SidebarLeft.qml": ("GlobalStates.sidebarLeftOpen", "quickshell:sidebarLeft"),
}


def read(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    assert text.strip(), f"{path} is empty"
    return text


def code(path: Path) -> str:
    text = read(path)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def logical_lines(text: str):
    joined = []
    for line in text.splitlines():
        stripped = line.strip()
        if joined and stripped[:1] in {"+", "-", "*", "/", "?", ":", ".", "&", "|", ")", ","}:
            joined[-1] = joined[-1] + " " + stripped
        else:
            joined.append(line)
    return joined


def blocks(text: str, type_name: str):
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


def mapping_block(text: str, namespace: str, name: str) -> str:
    owning = [b for b in blocks(text, "PanelWindow") if f'WlrLayershell.namespace: "{namespace}"' in b]
    assert len(owning) == 1, \
        f"{name} has {len(owning)} PanelWindow declarations carrying {namespace} - this rule is about the one that maps it"
    return owning[0]


def declared_at_top_level(block: str, prop: str):
    """Values of `prop:` declared directly on `block`, not on anything nested
    inside it. A `mask: Region { item: ... }` spans lines; the value returned
    is the whole brace-matched declaration so the gate inside it is visible."""
    values = []
    depth = 0
    lines = logical_lines(block)
    for i, line in enumerate(lines):
        if depth == 1:
            match = re.match(rf"\s*{re.escape(prop)}\s*:(.*)", line)
            if match:
                value = match.group(1).strip()
                if value.endswith("{"):
                    inner = 1
                    j = i + 1
                    while j < len(lines) and inner > 0:
                        value += " " + lines[j].strip()
                        inner += lines[j].count("{") - lines[j].count("}")
                        j += 1
                values.append(value)
        depth += line.count("{") - line.count("}")
    return values


def test_the_surface_is_mapped_for_the_life_of_the_shell():
    for path, (flag, namespace) in SIDEBARS.items():
        name = path.relative_to(ROOT).as_posix()
        window = mapping_block(code(path), namespace, name)
        visibles = declared_at_top_level(window, "visible")
        assert visibles in ([], ["true"]), \
            (f"{name}'s PanelWindow declares `visible: {visibles}` - a surface that follows the "
             "open flag is destroyed on close and rebuilt on open, which blocked the shell's one GUI "
             "thread for 61ms per gesture. The panel slides; the surface stays.")
        assert "reallyVisible" not in window, \
            f"{name} still carries a `reallyVisible` lifetime flag - the surface has no lifetime to track any more"


def test_a_closed_panel_takes_neither_clicks_nor_the_keyboard():
    for path, (flag, namespace) in SIDEBARS.items():
        name = path.relative_to(ROOT).as_posix()
        window = mapping_block(code(path), namespace, name)

        masks = declared_at_top_level(window, "mask")
        assert len(masks) == 1, f"{name}'s PanelWindow declares {len(masks)} `mask:` - exactly one gates its input"
        assert flag in masks[0], \
            (f"{name}'s mask reads `{masks[0]}` without `{flag}` - a mapped surface with an ungated mask "
             "is a strip down the whole screen edge that eats every click while showing nothing")

        focus = declared_at_top_level(window, "WlrLayershell.keyboardFocus")
        assert len(focus) == 1, f"{name}'s PanelWindow declares {len(focus)} keyboardFocus values"
        assert flag in focus[0], \
            (f"{name}'s keyboardFocus reads `{focus[0]}` without `{flag}` - an always-mapped surface "
             "with OnDemand focus holds the keyboard while closed")


def test_the_panel_slides_on_the_shared_runner_and_hides_on_its_shown():
    runner = code(RUNNER)
    assert re.search(r"readonly\s+property\s+bool\s+shown\b", runner), \
        "EdgeSlide no longer publishes `shown` - the one signal that outlives the flag by the exit"
    for path, (flag, namespace) in SIDEBARS.items():
        name = path.relative_to(ROOT).as_posix()
        text = code(path)
        window = mapping_block(text, namespace, name)
        assert re.search(r"EdgeSlide\s*\{", window), \
            f"{name} declares no EdgeSlide - its panel has no slide of its own and the compositor's is gone"
        content_visibles = [l.strip() for l in logical_lines(window)
                            if re.match(r"\s*visible\s*:", l) and "slide.shown" in l]
        assert content_visibles, \
            (f"{name} hides nothing on `slide.shown` - content gated on the flag vanishes on frame one "
             "of a 400ms exit")
        flag_visibles = [l.strip() for l in logical_lines(window)
                         if re.match(r"\s*visible\s*:", l) and flag in l]
        assert flag_visibles == [], \
            f"{name} gates visibility on the open flag at {flag_visibles} - use the runner's `shown`"


def test_the_compositor_no_longer_animates_the_map():
    rules = code(RULES)
    for _, (flag, namespace) in SIDEBARS.items():
        lines = [l for l in rules.splitlines() if f'namespace = "{namespace}"' in l]
        assert lines, f"rules.lua has no layer rule for {namespace} at all"
        assert any("no_anim = true" in l for l in lines), \
            f"{namespace} has no `no_anim` rule - the compositor animates the map on top of EdgeSlide's slide"
        assert not any(re.search(r"animation\s*=", l) for l in lines), \
            f"{namespace} still carries a compositor slide rule: {[l.strip() for l in lines]}"


if __name__ == "__main__":
    raise SystemExit(run(globals()))
