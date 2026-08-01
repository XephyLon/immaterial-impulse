#!/usr/bin/env python3
"""Sync OpenRGB detector toggles with the shell's excluded-devices list.

Excluding a device from the color sync is not enough on its own: a running
OpenRGB server *claims* every detected device, which overrides its firmware
lighting (e.g. a Wooting keyboard's own per-key effects die the moment
OpenRGB opens it) even if the shell never writes a color to it. The only
sanctioned way to keep OpenRGB's hands off a device is its own config's
"Detectors" map, so this script flips the detectors matching excluded
devices to false before the shell spawns its managed server.

Matching: OpenRGB device names are the detector name plus an optional
suffix ("Wooting Two HE (ARM) zone" comes from detector "Wooting Two HE
(ARM)"), so a detector is disabled when an excluded name equals it or
starts with it plus a space. Detectors this script disabled are recorded in
a state file and restored to true once no excluded name matches them any
more - detectors the user disabled themselves are never touched.

Usage: sync_openrgb_detectors.py STATE_FILE [EXCLUDED_NAME...]
Prints "changed" when the OpenRGB config was modified (the server must be
restarted for it to take effect), else "unchanged". Missing OpenRGB config
is a no-op: OpenRGB has never run, so there is nothing to claim devices.
Stdlib-only on purpose.
"""

import json
import os
import sys

OPENRGB_CONFIG = os.path.expanduser("~/.config/OpenRGB/OpenRGB.json")


def detector_matches(detector, excluded_names):
    """True when any excluded device name comes from this detector."""
    return any(e == detector or e.startswith(detector + " ") for e in excluded_names)


def compute_changes(detectors, excluded_names, ours):
    """Pure core: which detector flags to flip, and the new record.

    detectors: {name: enabled} from OpenRGB.json
    excluded_names: device names excluded in the shell config
    ours: detector names this script disabled on earlier runs

    Returns (changes {name: new_value}, new_ours sorted list). Detectors
    already disabled by the user are left alone (and never recorded); only
    detectors in `ours` are ever re-enabled.
    """
    changes = {}
    new_ours = set(ours) & set(detectors)
    for name, enabled in detectors.items():
        if detector_matches(name, excluded_names):
            if enabled:
                changes[name] = False
                new_ours.add(name)
        elif name in new_ours:
            changes[name] = True
            new_ours.discard(name)
    return changes, sorted(new_ours)


def load_json(path, fallback):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return fallback


def main(argv):
    if len(argv) < 2:
        print("usage: sync_openrgb_detectors.py STATE_FILE [EXCLUDED_NAME...]",
              file=sys.stderr)
        return 2
    state_file = argv[1]
    excluded_names = argv[2:]

    config = load_json(OPENRGB_CONFIG, None)
    # OpenRGB nests the map as Detectors.detectors; older configs used a
    # flat Detectors object. Support both, mutating in place either way.
    detectors = (config or {}).get("Detectors", {})
    if isinstance(detectors, dict) and isinstance(detectors.get("detectors"), dict):
        detectors = detectors["detectors"]
    if not isinstance(detectors, dict) or not detectors:
        print("unchanged")
        return 0

    state = load_json(state_file, {})
    ours = state.get("disabledDetectors", []) if isinstance(state, dict) else []

    changes, new_ours = compute_changes(detectors, excluded_names, ours)

    if sorted(new_ours) != sorted(set(ours) & set(detectors)) or changes:
        os.makedirs(os.path.dirname(state_file) or ".", exist_ok=True)
        with open(state_file, "w") as handle:
            json.dump({"disabledDetectors": new_ours}, handle, indent=2)
            handle.write("\n")

    if not changes:
        print("unchanged")
        return 0

    detectors.update(changes)
    tmp_path = OPENRGB_CONFIG + ".tmp"
    with open(tmp_path, "w") as handle:
        json.dump(config, handle, indent=4)
        handle.write("\n")
    os.replace(tmp_path, OPENRGB_CONFIG)
    print("changed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
