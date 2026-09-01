#!/usr/bin/env python3
"""The RGB streamer talks to the SDK server the way the Effects plugin does.

A fake server on a loopback port speaks just enough of the OpenRGB protocol
to serve controller descriptions and record what the streamer sends. The
contract, in the order the blink taught it:

  - the mode command is sent ONCE per controller, at connect, and not at
    all to a controller that is already in Direct - it is the command that
    re-initialises a controller, which is the white blink;
  - after that, only UpdateLEDs frames, one per streaming controller per
    tick, and none once the colour has arrived - a frame that changes
    nothing is i2c traffic for nothing;
  - a new target is reached as a ramp (several frames), not a step;
  - exclusions by name and by type, spelled as `openrgb --list-devices`
    spells them, are never written to and never mode-switched;
  - the wire format is the one RGBController.cpp parses.

Stdlib only, no OpenRGB needed: the point is the protocol, not the lights.
"""
import os
import socket
import struct
import subprocess
import sys
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/rgb/openrgb_stream.py"
sys.path.insert(0, str(SCRIPT.parent))
import openrgb_stream as stream  # noqa: E402

HEADER = struct.Struct("<4sIII")


def pstr(text):
    raw = text.encode() + b"\0"
    return struct.pack("<H", len(raw)) + raw


def mode_bytes(name, num_colors=0):
    # protocol 2: name, value, flags, speed_min, speed_max, colors_min,
    # colors_max, speed, direction, color_mode, num_colors, colors
    return (pstr(name) + struct.pack("<iIIIIIIII", 0, 0x20, 0, 0, 0, 0, 0, 0, 1)
            + struct.pack("<H", num_colors) + b"\0\0\0\0" * num_colors)


def controller(dev_type, name, modes, active_mode, num_leds):
    body = struct.pack("<i", dev_type) + pstr(name) + pstr("vendor") + pstr("desc") + pstr("1.0") + pstr("") + pstr("loc")
    body += struct.pack("<H", len(modes)) + struct.pack("<i", active_mode)
    for mode in modes:
        body += mode_bytes(mode)
    # one zone, no matrix
    body += struct.pack("<H", 1) + pstr("Zone") + struct.pack("<iIII", 0, num_leds, num_leds, num_leds) + struct.pack("<H", 0)
    body += struct.pack("<H", num_leds)
    for i in range(num_leds):
        body += pstr(f"LED {i}") + struct.pack("<I", 0)
    body += struct.pack("<H", num_leds) + b"\0\0\0\0" * num_leds
    return struct.pack("<I", len(body) + 4) + body


DEVICES = [
    controller(1, "Corsair DRAM", ["Static", "Direct"], 0, 12),   # DRAM, in Static: needs the switch
    controller(2, "GPU Thing", ["Direct"], 0, 4),                 # GPU, already Direct
    controller(0, "Board", ["Direct", "Breathing"], 0, 8),        # already Direct
    controller(10, "Sony DualSense Edge", ["Direct"], 0, 2),      # excluded by name
]


class FakeServer(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.received = []  # (dev_id, packet_id, payload)
        self.lock = threading.Lock()
        self.connections = 0

    def run(self):
        while True:
            try:
                conn, _ = self.listener.accept()
            except OSError:
                return
            self.connections += 1
            threading.Thread(target=self.serve, args=(conn,), daemon=True).start()

    def serve(self, conn):
        def read_exact(n):
            buf = b""
            while len(buf) < n:
                chunk = conn.recv(n - len(buf))
                if not chunk:
                    raise ConnectionError
                buf += chunk
            return buf

        def reply(dev_id, packet_id, payload):
            conn.sendall(HEADER.pack(b"ORGB", dev_id, packet_id, len(payload)) + payload)

        try:
            while True:
                magic, dev_id, packet_id, size = HEADER.unpack(read_exact(HEADER.size))
                payload = read_exact(size)
                with self.lock:
                    self.received.append((dev_id, packet_id, payload))
                if packet_id == stream.REQUEST_PROTOCOL_VERSION:
                    reply(0, packet_id, struct.pack("<I", 5))
                elif packet_id == stream.REQUEST_CONTROLLER_COUNT:
                    reply(0, packet_id, struct.pack("<I", len(DEVICES)))
                elif packet_id == stream.REQUEST_CONTROLLER_DATA:
                    reply(dev_id, packet_id, DEVICES[dev_id])
        except (ConnectionError, OSError):
            conn.close()

    def packets(self, packet_id):
        with self.lock:
            return [(d, p) for d, pid, p in self.received if pid == packet_id]

    def stop(self):
        self.listener.close()


def run_streamer(port, lines, wait, extra=()):
    proc = subprocess.Popen(
        [sys.executable, str(SCRIPT), "--port", str(port), "--fps", "60", "--smoothing", "0.5",
         "--exclude-name", "Sony DualSense Edge", *extra],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for line, pause in lines:
        proc.stdin.write(line + "\n")
        proc.stdin.flush()
        time.sleep(pause)
    time.sleep(wait)
    # Let communicate() flush and close stdin itself. Closing it here first
    # made communicate() flush an already-closed pipe, which is a hard
    # ValueError on Python 3.12 (the CI runner) though a no-op on older
    # builds; the EOF the streamer waits on is identical either way.
    out, err = proc.communicate(timeout=10)
    return out, err


class WireFormatTests(unittest.TestCase):
    def test_update_leds_is_size_count_colours(self):
        payload = stream.pack_update_leds(2, "FF8001")
        self.assertEqual(payload, struct.pack("<IH", 4 + 2 + 8, 2) + b"\xff\x80\x01\x00" * 2)

    def test_colour_packs_r_g_b_pad(self):
        self.assertEqual(stream.pack_color("010203"), b"\x01\x02\x03\x00")

    def test_controller_parse_finds_the_stream_mode(self):
        info = stream.parse_controller(DEVICES[0])
        self.assertEqual(info["type"], "DRAM")
        self.assertEqual(info["name"], "Corsair DRAM")
        self.assertEqual(info["active_mode"], 0)
        self.assertEqual(info["stream_mode"][0], 1, "Direct is preferred over Static")
        self.assertEqual(info["stream_mode"][1], mode_bytes("Direct"))
        self.assertEqual(info["num_colors"], 12)

    def test_ramp_arrives_and_stops(self):
        current = [0.0, 0.0, 0.0]
        target = [255, 128, 0]
        steps = 0
        while current != target and steps < 100:
            current = stream.step_toward(current, target, 0.5)
            steps += 1
        self.assertLess(steps, 12, "a ramp that only ever halves never arrives")
        self.assertEqual(current, target)


class FakeServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = FakeServer()
        cls.server.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        with self.server.lock:
            self.server.received.clear()

    def test_mode_once_frames_ramp_then_silence(self):
        out, err = run_streamer(self.server.port, [("FF0000", 0.5), ("0000FF", 0.5)], wait=0.3)
        self.assertIn("ready 3", out, err)
        modes = self.server.packets(stream.RGBCONTROLLER_UPDATEMODE)
        self.assertEqual([d for d, _ in modes], [0],
                         "the mode command goes once to the one controller not already in Direct")
        (size, index) = struct.unpack_from("<Ii", modes[0][1])
        self.assertEqual(index, 1)
        self.assertEqual(size, len(modes[0][1]))
        self.assertEqual(modes[0][1][8:], mode_bytes("Direct"), "the mode is echoed back as received")
        frames = self.server.packets(stream.RGBCONTROLLER_UPDATELEDS)
        targets = {d for d, _ in frames}
        self.assertEqual(targets, {0, 1, 2}, "every streaming controller gets frames; the excluded one none")
        dram = [p for d, p in frames if d == 0]
        self.assertGreater(len(dram), 4, "a new target is a ramp of several frames, not a step")
        first_count = struct.unpack_from("<H", dram[0], 4)[0]
        self.assertEqual(first_count, 12, "a frame carries one colour per LED")
        # First frame lands the first target directly; the last frame is the
        # second target, and nothing follows it during the quiet period.
        self.assertEqual(dram[0][6:10], b"\xff\x00\x00\x00")
        self.assertEqual(dram[-1][6:10], b"\x00\x00\xff\x00")
        # 60 fps for 0.3 s of silence would be ~18 more frames if it kept going.
        self.assertLess(len(dram), 40, "frames keep flowing after the colour has arrived")

    def test_type_exclusion_skips_the_gpu(self):
        out, err = run_streamer(self.server.port, [("00FF00", 0.3)], wait=0.1, extra=("--exclude-type", "GPU"))
        self.assertIn("ready 2", out, err)
        targets = {d for d, _ in self.server.packets(stream.RGBCONTROLLER_UPDATELEDS)}
        self.assertEqual(targets, {0, 2})

    def test_stdin_close_ends_the_process(self):
        out, err = run_streamer(self.server.port, [], wait=0.1)
        self.assertIn("ready", out)


if __name__ == "__main__":
    unittest.main()
