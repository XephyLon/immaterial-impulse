#!/usr/bin/env python3
"""The quick sliders' cards arrive through the shared wave, bottom-up.

Each quick slider is two entrances on one trigger, and they are deliberately
two channels rather than one. The FILL sweeps from zero to the real reading
through `StyledSlider`'s glide velocity (4a8ddce51, "feat(sidebar): every
widget owns its entrance - the fork's real motion language"); the CARD fades,
scales and rises into place on the `appear` scalar a `StaggerWave` animates and
a `StaggerEntrance` dresses - the fork's `AndroidSliderWidgetBase` entrance
(opacity 0 -> 1, scale 0.85 -> 1, 20px rise, after a per-slider delay), spelled
with the two shared components rather than as a fourth hand-copied
three-channel dressing.

What this file pins is the shape that decays, because none of it is reachable
from `qmltestrunner` (a `StyledSlider` will not build there) and all of it
fails silently on screen:

- The three cards are the wave's members, handed in as a LIST in bottom-up
  order. They are not one container's children - the bottom row packs volume
  and mic side by side - so a wave walking `children` would find the row and
  not the cards, and the row is not a member. Order is the design: the spec is
  bottom-up, and a list is the only place that order is written.
- Each card declares `appear` at its own top level. A card without it is not a
  member: the wave skips it and the dresser skips it, and it arrives drawn at
  full strength one frame before its neighbours start fading - the "always
  there, then the animation begins" read the toggle grid already paid for.
- Every container holding a member has a `StaggerEntrance` aimed at it. The
  dresser installs opacity, scale and the rise on a container's CHILDREN, so a
  member whose container has no dresser rides the wave on `appear` alone -
  which is a number changing and nothing moving.
- The wave runs on the sidebar's trigger, park-and-enter, ungated - the same
  edge the fill sweep already runs on, so the two channels cannot start on
  different gestures.
- No `Behavior on opacity` or `Behavior on scale` anywhere in the file. Both
  are the dressing's channels, and a Behavior on either swallows the park and
  retargets every frame of the wave (`lint_wave_member_opacity_behavior.py`
  holds the root-level case tree-wide; the members here are nested Loaders,
  which that lint does not see).
- The fill sweep stays. The cards' entrance is IN ADDITION to it, not instead.

Every check is proven against an in-memory mutation of the real file, so a
regex that stops matching reads as a failure rather than as a clean tree.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
QUICK_SLIDERS = ROOT / "modules/imi/sidebarRight/QuickSliders.qml"

# Bottom-up: the bottom row's two cards first, brightness (the top card) last.
MEMBERS = ["volumeLoader", "micLoader", "brightnessLoader"]
WAVE_ID = "sliderWave"

ID_LINE = re.compile(r"^\s*id:\s*(\w+)\s*$")
APPEAR_LINE = re.compile(r"^\s*property real appear\b")
TARGET_LINE = re.compile(r"^\s*target:\s*(\w+)\s*$")
ITEMS_LINE = re.compile(r"^\s*items:\s*\[([^\]]*)\]")
BEHAVIOR_ON = re.compile(r"^\s*Behavior on (opacity|scale)\b")
CHANNEL_WRITE = re.compile(r"^\s*(opacity|scale)\s*:")


def strip_comments(line: str) -> str:
    return line.split("//", 1)[0]


class Block:
    def __init__(self, header: str, start: int, depth: int, parent):
        self.header = header.strip()
        self.start = start
        self.end = None
        self.depth = depth
        self.parent = parent
        self.id = None
        # (line number, text, depth-at-line-start) for every line inside.
        self.lines = []

    def own_lines(self):
        """Lines at the block's own top level - its properties and handlers."""
        return [(n, t) for n, t, d in self.lines if d == self.depth + 1]

    def enclosing_id(self):
        block = self.parent
        while block is not None:
            if block.id is not None:
                return block.id
            block = block.parent
        return None


def parse(text: str):
    """A brace walk over the file: every `{ ... }` is a Block, ids attach to
    the block they sit in. JS bodies and template literals balance their own
    braces and simply become anonymous blocks nobody asks about."""
    blocks = []
    stack = []
    depth = 0
    for number, raw in enumerate(text.splitlines(), start=1):
        line = strip_comments(raw)
        for block in stack:
            block.lines.append((number, raw, depth))
        match = ID_LINE.match(line)
        if match and stack:
            stack[-1].id = match.group(1)
        for char in line:
            if char == "{":
                header = line.split("{", 1)[0]
                block = Block(header, number, depth, stack[-1] if stack else None)
                blocks.append(block)
                stack.append(block)
                depth += 1
            elif char == "}":
                depth -= 1
                if stack:
                    stack.pop().end = number
    return blocks


def by_id(blocks, wanted):
    return [b for b in blocks if b.id == wanted]


def check(text: str) -> list:
    problems = []
    blocks = parse(text)
    root = blocks[0] if blocks else None
    if root is None or root.depth != 0:
        return ["QuickSliders.qml has no root object"]

    # --- the wave, and its members in order ------------------------------
    waves = [b for b in blocks if b.header.startswith("StaggerWave")]
    if len(waves) != 1:
        problems.append(f"expected exactly one StaggerWave, found {len(waves)}")
    else:
        wave = waves[0]
        if wave.id != WAVE_ID:
            problems.append(f"the wave is `{wave.id}`, not `{WAVE_ID}`")
        targets = [TARGET_LINE.match(t).group(1) for _, t in wave.own_lines()
                   if TARGET_LINE.match(t)]
        if targets != [root.id]:
            problems.append(
                f"the wave's target is {targets}, not the card ({root.id}) - the "
                f"runner waits on its target being on screen before starting")
        items = [ITEMS_LINE.match(t) for _, t in wave.own_lines()]
        items = [m for m in items if m]
        if not items:
            problems.append("the wave has no `items:` list - its members are not "
                            "one container's children")
        else:
            listed = [s.strip() for s in items[0].group(1).split(",") if s.strip()]
            if listed != MEMBERS:
                problems.append(
                    f"the wave's members are {listed}; expected bottom-up "
                    f"{MEMBERS}")

    # --- each member: appear, its own dresser, no second channel writer ---
    dressers = [b for b in blocks if b.header.startswith("StaggerEntrance")]
    dressed = set()
    for dresser in dressers:
        for _, t in dresser.own_lines():
            match = TARGET_LINE.match(t)
            if match:
                dressed.add(match.group(1))
    for member in MEMBERS:
        found = by_id(blocks, member)
        if len(found) != 1:
            problems.append(f"`{member}` is declared {len(found)} times")
            continue
        block = found[0]
        own = block.own_lines()
        if not any(APPEAR_LINE.match(t) for _, t in own):
            problems.append(f"`{member}` declares no `property real appear` - "
                            f"it is not a wave member")
        for _, t in own:
            if CHANNEL_WRITE.match(t):
                problems.append(f"`{member}` writes `{t.strip()}` itself; the "
                                f"dresser owns that channel")
        container = block.enclosing_id()
        if container not in dressed:
            problems.append(
                f"`{member}` sits in `{container}`, which no StaggerEntrance "
                f"targets - the wave moves its `appear` and nothing on screen "
                f"follows")

    # --- the trigger runs the wave -----------------------------------------
    handlers = [b for b in blocks
                if b.header.startswith("onEntranceTriggerChanged:")
                and b.parent is root]
    if len(handlers) != 1:
        problems.append("the root declares no onEntranceTriggerChanged handler")
    else:
        body = "\n".join(t for _, t, _ in handlers[0].lines)
        for call in (f"{WAVE_ID}.park()", f"{WAVE_ID}.enter()"):
            if call not in body:
                problems.append(f"the trigger handler does not call {call}")

    # --- no second animation on the dressing's channels -------------------
    for number, raw in enumerate(text.splitlines(), start=1):
        if BEHAVIOR_ON.match(strip_comments(raw)):
            problems.append(f"line {number}: {raw.strip()} - a Behavior on a "
                            f"channel the wave animates")

    # --- the fill sweep is still there -------------------------------------
    for token in ("sweepTimer", "entranceParked", "valueVelocity"):
        if token not in text:
            problems.append(f"the fill sweep is gone (`{token}` not found) - "
                            f"the card entrance is in addition to it")
    return problems


def real() -> str:
    return QUICK_SLIDERS.read_text(encoding="utf-8")


def mutated(before: str, after: str, count: int = 1) -> str:
    text = real()
    assert text.count(before) == count, \
        f"the mutation's anchor `{before}` appears {text.count(before)} times"
    return text.replace(before, after)


def expect(problems, fragment):
    assert any(fragment in p for p in problems), \
        f"expected a problem mentioning `{fragment}`, got {problems}"


def test_the_quick_sliders_pass():
    problems = check(real())
    assert not problems, "\n  ".join(["QuickSliders.qml:"] + problems)


def test_a_card_without_appear_is_not_a_member():
    text = real()
    block = next(b for b in parse(text) if b.id == "brightnessLoader")
    line = next(t for _, t in block.own_lines() if APPEAR_LINE.match(t))
    expect(check(text.replace(line + "\n", "", 1)), "`brightnessLoader` declares no")


def test_the_members_are_listed_bottom_up():
    text = mutated("items: [volumeLoader, micLoader, brightnessLoader]",
                   "items: [brightnessLoader, volumeLoader, micLoader]")
    expect(check(text), "expected bottom-up")


def test_a_member_dropped_from_the_list_is_caught():
    text = mutated("items: [volumeLoader, micLoader, brightnessLoader]",
                   "items: [volumeLoader, brightnessLoader]")
    expect(check(text), "expected bottom-up")


def test_a_container_without_its_dresser_is_caught():
    text = real()
    blocks = parse(text)
    row = next(b for b in blocks if b.id == "bottomRow")
    dresser = next(b for b in blocks
                   if b.header.startswith("StaggerEntrance") and b.parent is row)
    lines = text.splitlines()
    del lines[dresser.start - 1:dresser.end]
    expect(check("\n".join(lines)), "which no StaggerEntrance targets")


def test_a_behavior_on_a_channel_is_caught():
    text = mutated(
        "                id: volumeLoader\n",
        "                id: volumeLoader\n"
        "                Behavior on opacity {}\n")
    expect(check(text), "a Behavior on a channel the wave animates")


def test_a_member_writing_its_own_opacity_is_caught():
    text = mutated(
        "                id: micLoader\n",
        "                id: micLoader\n"
        "                opacity: 1\n")
    expect(check(text), "`micLoader` writes")


def test_the_trigger_must_run_the_wave():
    text = mutated(f"        {WAVE_ID}.enter();\n", "")
    expect(check(text), f"does not call {WAVE_ID}.enter()")


def test_the_wave_waits_on_the_card():
    text = mutated("        target: root\n        items:",
                   "        target: contentItem\n        items:")
    expect(check(text), "the wave's target is")


def test_the_fill_sweep_stays():
    text = real().replace("sweepTimer", "gone")
    expect(check(text), "the fill sweep is gone")


def test_the_walker_reads_the_file_it_is_pointed_at():
    """A parse that finds no members passes every per-member check for the
    wrong reason; pin the shape it must recover from the real file."""
    blocks = parse(real())
    ids = {b.id for b in blocks if b.id}
    assert set(MEMBERS) <= ids, f"members not found by the walker: {ids}"
    assert next(b for b in blocks if b.id == "volumeLoader").enclosing_id() == "bottomRow"
    assert next(b for b in blocks if b.id == "brightnessLoader").enclosing_id() == "contentItem"


if __name__ == "__main__":
    sys.exit(run(globals()))
