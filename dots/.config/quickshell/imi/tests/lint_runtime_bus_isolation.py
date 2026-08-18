#!/usr/bin/env python3
#
# Regression guard: a harness that launches `qs` must decide which session bus
# it talks to. One that inherits `DBUS_SESSION_BUS_ADDRESS` is not testing the
# shell - it is testing the shell plus whatever the developer happens to be
# running, and the answer changes between their machine and CI.
#
# The failure that bought this check, in full, because it is the exact shape
# the register below is about.
#
# `test_lock_island_reorder_runtime.py` drags the lock screen's left island.
# `LockSurface.islandItemVisible` hides `username` and `keyboardLayout` while a
# media player is registered, so the slots the drag names exist only when
# nothing holds an MPRIS name. The harness already took great care to be
# isolated - its own XDG_RUNTIME_DIR, its own weston, its own config and state
# home, HYPRLAND_INSTANCE_SIGNATURE popped so it can never reach the user's
# compositor - and then inherited the session bus, where the maintainer's
# browser was registered as a player. The drag landed on two invisible slots,
# committed nothing, and the check failed. CI never saw it: the runner has no
# player, and it skips this test for want of `qs` anyway.
#
# So the same measurement passed on one machine and failed on another while the
# shell's own code was identical. That is the class AGENT.md records as "a
# measurement needs a control": the variable under test was the reorder, and
# the thing that actually moved was a browser tab.
#
# THE REGISTER, and why it is a ratchet rather than a bulk fix.
#
# Thirty-three harnesses in the tree launch `qs` on the inherited bus. Most
# read nothing off it and are fine today by luck rather than by design, and
# wrapping all of them in one branch means thirty-three unverified changes to
# tests whose whole job is to be trustworthy - `dbus-run-session` starts a bus
# with no services on it at all, so a harness that quietly depended on one
# (UPower, a portal, a notification daemon) would start failing for a new
# reason. They are fixed one at a time, each verified by running it.
#
# EXISTING is therefore the list of harnesses still on the inherited bus, and
# the check fails two ways:
#
#   - a harness outside the register launches `qs` without deciding its bus
#     (new code cannot add one);
#   - a registered harness now decides its bus (fixing one is required to take
#     it OUT of the list, so the register cannot rot into a permanent
#     allowlist nobody rechecks).
#
# "Decides" means either `dbus-run-session` (a private bus with nothing on it)
# or an explicit `DBUS_SESSION_BUS_ADDRESS` in the harness's env - pointing at
# a bus the test starts itself is as deliberate as isolating from it, and
# `test_notification_cards_runtime.py` needs exactly that.
#
# Lints are exempt: they read source, they start no shell.

import pathlib
import re
import sys

TESTS = pathlib.Path(__file__).resolve().parent

LAUNCHES_QS = re.compile(r'"qs"|\bqs\s+-[pc]\b')
DECIDES_BUS = re.compile(r"dbus-run-session|DBUS_SESSION_BUS_ADDRESS")

EXISTING = frozenset({
    "test_app_usage_runtime.py",
    "test_bar_edit_runtime.py",
    "test_calendar_card.py",
    "test_card_shadow.py",
    "test_clight_integration_runtime.py",
    "test_clock_depth_compositing.py",
    "test_clock_depth_noop.py",
    "test_config_control_write_back.py",
    "test_config_dir_migration_runtime.py",
    "test_conflict_killer_contract.py",
    "test_dock_edge_runtime.py",
    "test_edit_mode_chrome.py",
    "test_edit_mode_runtime.py",
    "test_get_keybinds.py",
    "test_kboptions_migration_runtime.py",
    "test_keybind_overrides_runtime.py",
    "test_launcher_qalc_runtime.py",
    "test_motion_multiplier_runtime.py",
    "test_nightlight_state_runtime.py",
    "test_notes_migration_runtime.py",
    "test_notes_surfaces_runtime.py",
    "test_parallax_migration_runtime.py",
    "test_quick_toggles_layout_runtime.py",
    "test_widget_edge_snap_runtime.py",
    "test_widget_elevation.py",
    "test_widget_grip_lock.py",
    "test_widget_group_drag_runtime.py",
    "test_widget_group_selection.py",
    "test_widget_interaction_modes.py",
    "test_widget_interaction_runtime.py",
    "test_widget_parallax_optout.py",
    "test_widget_resize_grip_runtime.py",
    "test_widget_resize_motion_runtime.py",
})


def main():
    failures = []
    inherited = set()
    scanned = 0

    for path in sorted(TESTS.glob("*.py")):
        if path.name.startswith("lint_"):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if not LAUNCHES_QS.search(text):
            continue
        scanned += 1
        if DECIDES_BUS.search(text):
            continue
        inherited.add(path.name)
        if path.name in EXISTING:
            continue
        failures.append(
            f"{path.name}: launches `qs` on the inherited session bus. Wrap the "
            f"launch in `dbus-run-session --` (and skip unless it is on PATH) "
            f"so the harness sees the services it declares, never the ones the "
            f"developer is running - a shell that reads MPRIS, UPower or a "
            f"portal off the user's bus measures their session, not this tree.")

    for name in sorted(EXISTING - inherited):
        if not (TESTS / name).exists():
            failures.append(
                f"{name}: registered in tests/lint_runtime_bus_isolation.py and "
                f"no longer present. Drop it from EXISTING.")
            continue
        failures.append(
            f"{name}: now decides its own session bus. Remove it from EXISTING "
            f"in tests/lint_runtime_bus_isolation.py - the register is a "
            f"ratchet, and one that is not tightened stops being read.")

    if failures:
        print("Runtime bus isolation lint failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(f"Runtime bus isolation lint passed ({scanned} qs harnesses, "
          f"{len(inherited)} still on the inherited bus)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
