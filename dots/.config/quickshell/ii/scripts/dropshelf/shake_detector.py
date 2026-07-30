#!/usr/bin/env python3
"""Cursor-shake detector for the drop shelf.

Polls the Hyprland request socket for the cursor position (raw socket, ~0.03ms
per query - never fork hyprctl per poll) and prints "SHAKE <x> <y>" when a
shake gesture is recognized: several long, fast horizontal direction reversals
inside a short sliding window.

Wayland offers no global "drag in progress" signal, so the caller decides when
this runs; the strict gesture keeps accidental triggers rare.
"""

import argparse
import json
import os
import socket
import sys
import time


class ShakeDetector:
    """Pure gesture recognizer - feed(t_ms, x, y) returns True on a shake.

    Tracks horizontal direction extrema: a reversal is recorded when the
    cursor backtracks JITTER_PX from the furthest point of the current
    sweep, and the completed leg is the sweep's total travel. A shake is
    MIN_LEGS completed legs, each at least min_leg_px, all inside
    window_ms. Per-sample deltas are never compared against thresholds, so
    the sampling rate and the slow instant at each turn don't matter.
    After a trigger the detector goes quiet for cooldown_ms.
    """

    WINDOW_MS = 700
    MIN_LEG_PX = 60.0
    JITTER_PX = 10.0
    MIN_LEGS = 3  # 3 completed legs = 3 direction reversals
    COOLDOWN_MS = 1500

    def __init__(self, sensitivity=1.0):
        sensitivity = max(0.1, float(sensitivity))
        self.min_leg_px = self.MIN_LEG_PX / sensitivity
        self.quiet_until = 0.0
        self._reset()

    def _reset(self):
        self.direction = 0
        self.sweep_start_x = None
        self.extreme_x = None
        self.legs = []  # (t_ms_of_reversal, travel_px)

    def feed(self, t_ms, x, y):
        if t_ms < self.quiet_until:
            self._reset()
            return False
        if self.extreme_x is None:
            self.sweep_start_x = self.extreme_x = x
            return False

        if self.direction >= 0 and x > self.extreme_x:
            self.extreme_x = x
            self.direction = self.direction or 1
        elif self.direction <= 0 and x < self.extreme_x:
            self.extreme_x = x
            self.direction = self.direction or -1
        elif self.direction != 0 and abs(self.extreme_x - x) >= self.JITTER_PX:
            # Backtracked past jitter: the sweep ended at extreme_x.
            self.legs.append((t_ms, abs(self.extreme_x - self.sweep_start_x)))
            self.sweep_start_x = self.extreme_x
            self.extreme_x = x
            self.direction = -self.direction

        cutoff = t_ms - self.WINDOW_MS
        self.legs = [leg for leg in self.legs if leg[0] >= cutoff]
        run = 0
        for _, travel in self.legs:
            run = run + 1 if travel >= self.min_leg_px else 0
        if run >= self.MIN_LEGS:
            self._reset()
            self.quiet_until = t_ms + self.COOLDOWN_MS
            return True
        return False


def hypr_socket_path():
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not signature:
        sys.exit("HYPRLAND_INSTANCE_SIGNATURE not set")
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{runtime}/hypr/{signature}/.socket.sock"


def query_cursorpos(path):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(1.0)
        sock.connect(path)
        sock.sendall(b"j/cursorpos")
        data = sock.recv(256)
    pos = json.loads(data)
    return float(pos["x"]), float(pos["y"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sensitivity", type=float, default=1.0,
                        help="higher = easier to trigger (divides leg travel threshold)")
    parser.add_argument("--hz", type=float, default=60.0, help="poll rate")
    args = parser.parse_args()

    path = hypr_socket_path()
    detector = ShakeDetector(sensitivity=args.sensitivity)
    interval = 1.0 / max(1.0, args.hz)

    while True:
        started = time.monotonic()
        try:
            x, y = query_cursorpos(path)
        except (OSError, ValueError, KeyError):
            time.sleep(1.0)  # compositor restarting or reply garbled
            continue
        if detector.feed(started * 1000.0, x, y):
            print(f"SHAKE {x:.0f} {y:.0f}", flush=True)
        remaining = interval - (time.monotonic() - started)
        if remaining > 0:
            time.sleep(remaining)


if __name__ == "__main__":
    main()
