#!/usr/bin/env python3
"""The bar popups' sections cascade below the fold, and the hero never does.

BarPopupOverlay unrolls the card from the height of the content's FIRST drawn
section so that section is legible on frame one - that is the hero unroll's
whole point. The section wave (gated on the card's own progress, see
tests/lint_bar_popup_overlay_static.py) therefore must not park or dim the
hero: only the sections below the fold cascade, and a popup opts each of those
in by declaring `property real appear: 1` and folding it into the measured
three-channel entrance (docs/p3drovfx-motion-measured-2026-08-22.md §3 -
opacity, a slight scale, a small rise, all driven by the one scalar).

What decays here, and what this file pins:

  - A hero that grows an `appear` is parked at zero for the run up to the
    gate, so the card opens at the height of a section that is not drawn -
    the unroll rendered meaningless, with nothing in any log.
  - A section that declares `appear` but binds only its opacity is the plain
    fade the survey found lacking; the three channels are one scalar so they
    cannot land on different schedules, and dropping two of them is silent.
  - A section that quietly stops opting in arrives in a single frame again,
    which reads on screen as the shell being flat rather than as a bug - the
    same decay STAGGER_ADOPTERS exists for, one level down.

The registers are RATCHETS: a new cascading section is a line here, and one
that disappears reddens instead of going quiet. Popups deliberately absent
(the tray overflow's homogeneous icon grid, the privacy card's one-tree depth
morph whose entrance channels would composite with its own morph) simply
declare no `appear` and keep today's behaviour - the wave is opt-in by
construction.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BAR = "modules/imi/bar"
STYLED_POPUP = ROOT / "modules/common/widgets/StyledPopup.qml"

# Per popup: the hero band's markers (ids or objectNames that must NOT declare
# `appear` - the card opens at the first drawn section's height, and anything
# sharing that band rides with it), and the ids of the sections that cascade.
SECTION_WAVES = {
    f"{BAR}/WeatherPopup.qml": {
        "hero_band": ["weatherHero"],
        "cascades": ["hourlyChart", "gridLayout"],
    },
    f"{BAR}/ClockWidgetPopup.qml": {
        # The year label anchors its baseline to the month's, so the two are
        # one visual band and neither may cascade out from under the other.
        "hero_band": ["monthLabel", "yearLabel"],
        "cascades": ["weekRow", "taskSection", "pendingLabel", "uptimeLabel"],
    },
    f"{BAR}/NetworkSpeedPopup.qml": {
        "hero_band": ["connectionRow"],
        "cascades": ["speedRow", "detailsList"],
    },
    f"{BAR}/BatteryPopup.qml": {
        "hero_band": ["batteryHeaderRow"],
        "cascades": ["batteryCards"],
    },
    f"{BAR}/BluetoothBatteryPopup.qml": {
        "hero_band": ["bluetoothHeaderRow"],
        "cascades": ["deviceCards"],
    },
    f"{BAR}/ResourcesPopup.qml": {
        "hero_band": ["ramCpuColumn"],
        "cascades": ["swapDiskColumn", "gpuColumn"],
    },
}


def block_declaring(text, ident):
    """The body of the object declaring `id: <ident>` or objectName <ident>."""
    marker = re.search(rf'\bid:\s*{ident}\b|\bobjectName:\s*"{ident}"', text)
    if not marker:
        return None
    brace = text.rfind("{", 0, marker.start())
    if brace < 0:
        return None
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    return None


def stripped(path):
    return re.sub(r"//.*", "", (ROOT / path).read_text(encoding="utf-8"))


def test_every_registered_popup_is_on_disk_and_reaches_the_helpers():
    for relative in SECTION_WAVES:
        assert (ROOT / relative).is_file(), (
            f"{relative} is registered and not on disk. Point the entry at "
            f"wherever the popup moved to - a register naming nothing passes.")
        text = stripped(relative)
        assert re.search(r'import\s+"bar_popup_unroll\.js"', text), (
            f"{relative} no longer imports bar_popup_unroll.js; the entrance "
            f"channels live there so ten popups cannot each derive their own "
            f"scale floor.")


def test_the_hero_band_never_declares_appear():
    for relative, spec in SECTION_WAVES.items():
        text = stripped(relative)
        for ident in spec["hero_band"]:
            block = block_declaring(text, ident)
            assert block is not None, (
                f"{relative} no longer declares `{ident}`; the register names "
                f"the hero band so a renamed hero is a line here, not a hole.")
            assert "appear" not in block, (
                f"{relative}: `{ident}` is in the hero band and declares or "
                f"reads `appear`. The card opens at the first drawn section's "
                f"height precisely so it is legible on frame one; a parked "
                f"hero is a card opening at the height of nothing, and the "
                f"failure renders - it looks deliberate and is wrong.")


def test_each_cascading_section_takes_all_three_channels():
    for relative, spec in SECTION_WAVES.items():
        text = stripped(relative)
        for ident in spec["cascades"]:
            block = block_declaring(text, ident)
            assert block is not None, (
                f"{relative} no longer declares `{ident}`; it is registered "
                f"as a cascading section.")
            assert re.search(r"\bproperty real appear:\s*1\b", block), (
                f"{relative}: `{ident}` no longer opts into the wave with "
                f"`property real appear: 1`. Without it the section arrives "
                f"in a single frame again, which is invisible in the source.")
            assert re.search(rf"\bopacity:\s*{ident}\.appear\b", block), (
                f"{relative}: `{ident}`'s opacity is not its own `appear`; "
                f"the wave animates appear, never opacity, so a section that "
                f"does not fold it in simply never dims or arrives.")
            assert "BarPopupUnroll.entranceScale(" in block \
                and "root.entranceRise" in block, (
                f"{relative}: `{ident}` does not take its scale from "
                f"BarPopupUnroll.entranceScale(..., root.entranceRise, ...); "
                f"a section with opacity alone is the plain fade the survey "
                f"found lacking, and a hand-spelled factor is the drift the "
                f"helper exists to stop.")
            assert "BarPopupUnroll.entranceOffset(" in block, (
                f"{relative}: `{ident}` does not rise through "
                f"BarPopupUnroll.entranceOffset; the three channels are one "
                f"scalar so they cannot land on different schedules.")


def test_no_unregistered_section_opts_in():
    """Every `appear` in a popup file is a registered id, so review sees it."""
    for relative, spec in SECTION_WAVES.items():
        text = stripped(relative)
        declared = len(re.findall(r"\bproperty real appear:", text))
        assert declared == len(spec["cascades"]), (
            f"{relative} declares {declared} `appear` sections against "
            f"{len(spec['cascades'])} registered. A new cascading section is "
            f"a line in SECTION_WAVES - the register is what lets the hero "
            f"rule be checked against a named band rather than a guess.")


def test_no_appear_section_sits_above_the_hero():
    """The hero is decided by the BUILT tree - the first drawn section - and
    this repo keeps source order agreeing with it (the weather popup's hourly
    row sits below the hero for exactly that reason, pinned by
    test_weather_forecast_contract). So a cascading section declared above
    the hero band is a section that will BECOME the hero the moment it has
    height, parked at appear 0 - the card opening at the height of a section
    that is not drawn."""
    for relative, spec in SECTION_WAVES.items():
        text = stripped(relative)
        first_hero = min(
            m.start() for ident in spec["hero_band"]
            for m in [re.search(rf'\bid:\s*{ident}\b|\bobjectName:\s*"{ident}"', text)]
            if m)
        first_appear = re.search(r"\bproperty real appear:", text)
        assert first_appear and first_appear.start() > first_hero, (
            f"{relative}: an `appear` section is declared above the hero "
            f"band. The card unrolls from the first drawn section, so a "
            f"cascading section above the hero is one gate-length of opening "
            f"at the height of nothing.")


def test_the_rise_is_one_token_on_styled_popup():
    text = STYLED_POPUP.read_text(encoding="utf-8")
    assert re.search(
        r"readonly property real entranceRise:\s*Appearance\.spacing\.\w+", text), (
        "StyledPopup no longer declares `entranceRise` from a spacing token. "
        "Every popup's sections read it as root.entranceRise; five hand-spelled "
        "rises are five entrances that drift apart by a token nobody chose.")


if __name__ == "__main__":
    sys.exit(run(globals()))
