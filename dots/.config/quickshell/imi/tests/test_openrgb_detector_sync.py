"""Tests for scripts/rgb/sync_openrgb_detectors.py.

The pure core (compute_changes / detector_matches) is exercised directly;
main() is run against a temp OpenRGB.json to pin the read-modify-write and
the changed/unchanged report the service keys its server restart on.
"""

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "rgb" / "sync_openrgb_detectors.py"

spec = importlib.util.spec_from_file_location("sync_openrgb_detectors", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_matches_exact_and_zone_suffix():
    assert mod.detector_matches("Wooting Two HE (ARM)", ["Wooting Two HE (ARM) zone"])
    assert mod.detector_matches("Sony DualSense Edge", ["Sony DualSense Edge"])
    # A prefix without a space boundary is a different product, not a match.
    assert not mod.detector_matches("Wooting Two HE", ["Wooting Two HE+ zone"])
    assert not mod.detector_matches("Wooting Two", [])


def test_compute_disables_matching_enabled_detectors():
    changes, ours = mod.compute_changes(
        {"Wooting Two HE (ARM)": True, "Sony DualSense Edge": True},
        ["Wooting Two HE (ARM) zone"],
        [],
    )
    assert changes == {"Wooting Two HE (ARM)": False}
    assert ours == ["Wooting Two HE (ARM)"]


def test_compute_leaves_user_disabled_detectors_alone():
    # Already false and not ours: no change recorded, never restored later.
    changes, ours = mod.compute_changes(
        {"Wooting Two HE (ARM)": False}, ["Wooting Two HE (ARM) zone"], []
    )
    assert changes == {}
    assert ours == []
    changes, ours = mod.compute_changes({"Wooting Two HE (ARM)": False}, [], [])
    assert changes == {}
    assert ours == []


def test_compute_restores_only_our_detectors_on_unexclude():
    changes, ours = mod.compute_changes(
        {"Wooting Two HE (ARM)": False, "Corsair Dominator Platinum": False},
        [],
        ["Wooting Two HE (ARM)"],
    )
    assert changes == {"Wooting Two HE (ARM)": True}
    assert ours == []


def test_compute_keeps_ours_while_still_excluded():
    changes, ours = mod.compute_changes(
        {"Wooting Two HE (ARM)": False},
        ["Wooting Two HE (ARM) zone"],
        ["Wooting Two HE (ARM)"],
    )
    assert changes == {}
    assert ours == ["Wooting Two HE (ARM)"]


def test_stale_record_entries_for_unknown_detectors_are_dropped():
    changes, ours = mod.compute_changes(
        {"Something Else": True}, [], ["Removed Detector"]
    )
    assert changes == {}
    assert ours == []


def test_main_roundtrip_writes_config_and_state():
    # Real OpenRGB nests the map as Detectors.detectors.
    with tempfile.TemporaryDirectory() as tmp:
        cfg_path = os.path.join(tmp, "OpenRGB.json")
        state_path = os.path.join(tmp, "state.json")
        json.dump(
            {"Detectors": {"detectors":
                {"Wooting Two HE (ARM)": True, "Other": True}},
             "Theme": "dark"},
            open(cfg_path, "w"),
        )
        mod.OPENRGB_CONFIG = cfg_path

        # Exclude: detector flips off, state records it, report says changed.
        assert mod.main([SCRIPT.name, state_path, "Wooting Two HE (ARM) zone"]) == 0
        cfg = json.load(open(cfg_path))
        assert cfg["Detectors"]["detectors"]["Wooting Two HE (ARM)"] is False
        assert cfg["Detectors"]["detectors"]["Other"] is True
        assert cfg["Theme"] == "dark"  # untouched keys survive
        state = json.load(open(state_path))
        assert state == {"disabledDetectors": ["Wooting Two HE (ARM)"]}

        # Same exclusions again: nothing to do.
        assert mod.main([SCRIPT.name, state_path, "Wooting Two HE (ARM) zone"]) == 0
        assert json.load(open(cfg_path))["Detectors"]["detectors"]["Wooting Two HE (ARM)"] is False

        # Un-exclude: restored and forgotten.
        assert mod.main([SCRIPT.name, state_path]) == 0
        assert json.load(open(cfg_path))["Detectors"]["detectors"]["Wooting Two HE (ARM)"] is True
        assert json.load(open(state_path)) == {"disabledDetectors": []}


def test_main_supports_flat_detectors_shape():
    with tempfile.TemporaryDirectory() as tmp:
        cfg_path = os.path.join(tmp, "OpenRGB.json")
        state_path = os.path.join(tmp, "state.json")
        json.dump({"Detectors": {"Wooting Two HE (ARM)": True}}, open(cfg_path, "w"))
        mod.OPENRGB_CONFIG = cfg_path
        assert mod.main([SCRIPT.name, state_path, "Wooting Two HE (ARM) zone"]) == 0
        assert json.load(open(cfg_path))["Detectors"]["Wooting Two HE (ARM)"] is False


def test_main_missing_openrgb_config_is_a_noop():
    with tempfile.TemporaryDirectory() as tmp:
        mod.OPENRGB_CONFIG = os.path.join(tmp, "does-not-exist.json")
        state_path = os.path.join(tmp, "state.json")
        assert mod.main([SCRIPT.name, state_path, "Whatever"]) == 0
        assert not os.path.exists(state_path)


if __name__ == "__main__":
    from contract_runner import run
    sys.exit(run(globals()))
