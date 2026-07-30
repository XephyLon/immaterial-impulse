#!/usr/bin/env python3
"""Cursor-shake detector for the drop shelf.

Polls the Hyprland request socket for the cursor position (raw socket, ~0.03ms
per query - never fork hyprctl per poll) and prints "SHAKE <x> <y>" when a
shake gesture is recognized: several long, fast horizontal direction reversals
inside a short sliding window.

Wayland offers no global "drag in progress" signal, but every pointer drag
holds the primary button - so the gesture is armed only while BTN_LEFT is
down, read via the EVIOCGKEY evdev ioctl (state poll, no event stream, no
grab). Requires 'input' group membership; without it the detector degrades
to always-armed and says so on stderr.
"""

import argparse
import array
import fcntl
import glob
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

    def reset(self):
        """Forget the gesture in progress (e.g. the drag button was released)."""
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


class ButtonWatcher:
    """Global BTN_LEFT state via the EVIOCGKEY evdev ioctl.

    A state poll per tick on each pointer device - no event stream to drain,
    no exclusive grab, and closing the fd leaves the device untouched.
    """

    EV_KEY = 0x01
    BTN_LEFT = 0x110
    KEY_BITMAP_BYTES = 96  # ceil((KEY_MAX=0x2ff + 1) / 8)
    RESCAN_S = 3.0

    def __init__(self):
        self.fds = {}
        self.last_scan = 0.0
        self.scan()
        self.available = bool(self.fds)

    @classmethod
    def _ioc(cls, nr, length):
        return (2 << 30) | (0x45 << 8) | nr | (length << 16)

    def scan(self):
        self.last_scan = time.monotonic()
        for path in glob.glob("/dev/input/event*"):
            if path in self.fds:
                continue
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            except OSError:
                continue
            buf = array.array("B", bytes(self.KEY_BITMAP_BYTES))
            try:
                fcntl.ioctl(fd, self._ioc(0x20 + self.EV_KEY, len(buf)), buf)
            except OSError:
                os.close(fd)
                continue
            if buf[self.BTN_LEFT // 8] & (1 << (self.BTN_LEFT % 8)):
                self.fds[path] = fd
            else:
                os.close(fd)

    def pressed(self):
        buf = array.array("B", bytes(self.KEY_BITMAP_BYTES))
        for path, fd in list(self.fds.items()):
            try:
                fcntl.ioctl(fd, self._ioc(0x18, len(buf)), buf)  # EVIOCGKEY
            except OSError:  # device unplugged
                os.close(fd)
                del self.fds[path]
                continue
            if buf[self.BTN_LEFT // 8] & (1 << (self.BTN_LEFT % 8)):
                return True
        if not self.fds and time.monotonic() - self.last_scan > self.RESCAN_S:
            self.scan()
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
    buttons = ButtonWatcher()
    if not buttons.available:
        print("no readable BTN_LEFT device (needs 'input' group); "
              "shake armed even outside drags", file=sys.stderr, flush=True)
    interval = 1.0 / max(1.0, args.hz)

    while True:
        started = time.monotonic()
        # Only a held primary button can be a drag; while it is up the
        # gesture is disarmed and the compositor socket is left alone.
        if buttons.available and not buttons.pressed():
            detector.reset()
            time.sleep(interval)
            continue
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
