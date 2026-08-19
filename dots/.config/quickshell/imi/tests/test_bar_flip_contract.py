#!/usr/bin/env python3
"""One reposition, wired into both bars, animating one thing.

`BarFlipRuntimeTest.qml` scores the motion and is the check that earns its
place - but it needs weston and a `qs`, which CI has neither of, so it skips
exactly where a divergence between the two bars would go unnoticed. That is the
failure a47462fcc records: a capability added to one bar and not the other is
invisible on a default screen, because the vertical bar is opt-in. These are
the source pins that run everywhere.

The rules:

  - every bucket delegate in BOTH content trees hands its BarGroup the frame's
    registry. Six per tree - three buckets, two styles - the same count the
    edit overlay's own contract asserts, and for the same reason: a delegate
    that misses the wiring is a widget that teleports in one style and one
    orientation only;
  - each tree declares exactly one registry, as a child of its own root. The
    root is the frame every position is measured in, and a registry declared
    anywhere else measures in a frame that moves with the bar's auto-hide slide;
  - the reposition is declared in BarGroup and nowhere else. Both bars wrap
    every widget in one, so a second copy is the drift this file exists to
    stop;
  - and what is animated is the translate, never `x`/`y` or an anchor margin.
    A slot's coordinates belong to its layout: animating those fights the
    layout, and a `Behavior` on one of them is handed a target the layout moves
    every frame, which restarts every frame and never ticks (AGENT.md,
    b710ef731). Nor is a position measured with `mapToItem`, which composes
    that same translate back into the next invert.
"""
import re
from pathlib import Path

from contract_runner import run
from test_background_fullscreen_suppression import _qml_source

ROOT = Path(__file__).resolve().parents[1]
BAR_DIR = ROOT / "modules/imi/bar"
BAR_CONTENT = BAR_DIR / "BarContent.qml"
VERTICAL_CONTENT = ROOT / "modules/imi/verticalBar/VerticalBarContent.qml"
BAR_GROUP = BAR_DIR / "BarGroup.qml"
REGISTRY = BAR_DIR / "BarFlipRegistry.qml"
MODULE = BAR_DIR / "bar_flip.js"

TREES = (BAR_CONTENT, VERTICAL_CONTENT)

# A Behavior on a coordinate the layout writes. `\s*` rather than a literal
# space because the two spellings differ by whitespace nowhere that matters,
# and a pattern with baked-in indentation passes vacuously after a reformat.
_LAYOUT_BEHAVIOR = re.compile(r"Behavior\s+on\s+(x|y|anchors\.\w+Margin)\b")


def code(path):
    """QML source with comments blanked, so a comment cannot satisfy a pin."""
    return _qml_source(path).code


def test_every_bucket_delegate_in_both_trees_hands_over_the_registry():
    for path in TREES:
        text = code(path)
        # `flipRegistry: flipRegistry` is what this used to pin, and it is the
        # one spelling that cannot work: inside a BarGroup the bare name
        # resolves to the delegate's OWN property before it reaches the id in
        # the enclosing scope, so the binding is the property bound to itself.
        # QML reports it as `Binding loop detected for property
        # "flipRegistry"` on every delegate and hands each group a null
        # registry, which is a bar with no reposition at all - and neither the
        # QML suite nor the runtime harness sees it, because the harness
        # declares its own groups and wires them by a distinct id.
        wired = text.count("flipRegistry: barFlipRegistry")
        assert wired == 6, (
            f"{path.name} wires flipRegistry into {wired} delegates, not 6 - a "
            f"bucket or a style still teleports, in that orientation only")
        assert "flipRegistry: flipRegistry" not in text, (
            f"{path.name} binds the registry to a name that resolves to the "
            f"delegate's own property first - a binding loop, and a null "
            f"registry in every group")


def test_each_tree_declares_exactly_one_registry_on_its_own_root():
    for path in TREES:
        text = code(path)
        declared = len(re.findall(r"\bBarFlipRegistry\s*{", text))
        assert declared == 1, (
            f"{path.name} declares {declared} BarFlipRegistry instances, not 1 "
            f"- the ids are shared between screens and the positions are not")
        # The declaration is a direct child of the content root, which is the
        # frame every position is measured in. One indent level, and after the
        # root's opening brace.
        assert re.search(r"\n    (?:Bar\.)?BarFlipRegistry\s*{", text), (
            f"{path.name}'s registry is not a direct child of the content root "
            f"- its frame would then be some inner item, and every recalled "
            f"position would be measured against something that moves")


def test_the_reposition_is_declared_in_one_file():
    others = []
    for path in sorted(ROOT.glob("modules/**/*.qml")):
        if path == BAR_GROUP:
            continue
        if "flipTravel" in path.read_text(encoding="utf-8", errors="replace"):
            others.append(str(path.relative_to(ROOT)))
    assert not others, (
        f"the slot reposition is spelled outside {BAR_GROUP.name}: {others}. "
        f"Both bars wrap every widget in a BarGroup, so a second copy is a "
        f"second answer that only one of them will get")


def test_the_reposition_animates_a_transform_and_not_the_layouts_coordinates():
    text = code(BAR_GROUP)
    assert "Translate" in text, (
        f"{BAR_GROUP.name} no longer moves the slot with a Translate - a "
        f"coordinate written here is a coordinate taken off the layout")
    found = _LAYOUT_BEHAVIOR.findall(text)
    assert not found, (
        f"{BAR_GROUP.name} declares Behavior on {found} - those are written by "
        f"the layout on every reflow, so the Behavior restarts every frame and "
        f"never ticks (b710ef731)")


def test_the_reposition_takes_its_motion_tier_whole():
    text = code(BAR_GROUP)
    assert re.search(r"Appearance\.animation\.\w+\.numberAnimation\.createObject", text), (
        f"{BAR_GROUP.name} does not build its reposition from a tier's own "
        f"component - a duration without its curve is silently Easing.Linear")
    assert "animationCurves" not in text, (
        f"{BAR_GROUP.name} reads a duration out of animationCurves, which is a "
        f"tier's BASE: the motion speed slider and reduce motion cannot reach it")


def test_the_arithmetic_stays_out_of_the_qml():
    text = code(BAR_GROUP)
    assert 'import "bar_flip.js"' in text, (
        f"{BAR_GROUP.name} does not import {MODULE.name} - the invert and the "
        f"play offsets are the only part of this reachable from a test")
    # mapToItem composes transforms, so measuring a slot's position with it
    # would read the translate this animates back into the next invert.
    assert "mapToItem" not in text, (
        f"{BAR_GROUP.name} measures with mapToItem, which composes the "
        f"Translate it animates - the next reposition would invert from a "
        f"number that is still moving")


def test_the_registry_measures_in_its_parents_frame():
    text = code(REGISTRY)
    assert re.search(r"property\s+Item\s+frame:\s*root\.parent", text), (
        f"{REGISTRY.name} no longer names its parent as the frame - a frame "
        f"further out travels with the bar's auto-hide slide, and every slot "
        f"would read the slide as a reposition")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
