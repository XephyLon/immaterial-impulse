#!/usr/bin/env python3
"""Stream one colour to every RGB device through the OpenRGB SDK server.

The way the OpenRGB Effects plugin drives hardware, as a process the shell
can keep open: connect ONCE, put each controller into its Direct mode ONCE,
then send nothing but UpdateLEDs frames. The `openrgb` CLI cannot do this -
every invocation is a fresh client handshake (a second per call, measured)
followed by a mode command, and a mode command re-initialises the
controller, which is the white blink the lights showed on every write.

Protocol: stdin takes one colour per line, `RRGGBB`. Each is a TARGET; a
tick loop at `--fps` interpolates the colour actually on the devices toward
it (`--smoothing` is the fraction of the remaining distance covered per
tick, so a new target arrives as a ramp rather than a step) and writes a
frame only while something is still moving. On the same connection a
server that rescans (DEVICE_LIST_UPDATED) is answered by re-reading its
controllers; a server that goes away is retried until stdin closes.

stdout, one line each: `ready <n>` once the devices are set up (the shell
starts writing when it sees it), `lost` when the connection drops. stderr
carries the reasons. Stdlib-only on purpose, like sync_openrgb_detectors.py.

Protocol notes (OpenRGB NetworkProtocol.h, RGBController.cpp):
  header   "ORGB" u32 dev_id  u32 packet_id  u32 payload_size, all LE
  strings  u16 length (including the NUL), bytes, NUL
  colours  u32 = r | g << 8 | b << 16
  UPDATELEDS payload  u32 size, u16 count, colours
  UPDATEMODE payload  u32 size, i32 mode_idx, the mode's description bytes
We speak protocol version 2: everything needed is in it, nothing after it
(brightness in 3, segments in 4, per-LED names in 5) is, and a mode echoed
back in the version it came in is a mode the server parses with no drift.
"""
import argparse
import os
import select
import socket
import struct
import sys
import time

MAGIC = b"ORGB"
PROTOCOL_VERSION = 2
HEADER = struct.Struct("<4sIII")

REQUEST_CONTROLLER_COUNT = 0
REQUEST_CONTROLLER_DATA = 1
REQUEST_PROTOCOL_VERSION = 40
SET_CLIENT_NAME = 50
DEVICE_LIST_UPDATED = 100
RGBCONTROLLER_UPDATELEDS = 1050
RGBCONTROLLER_UPDATEMODE = 1101

CLIENT_NAME = b"immaterial-impulse\0"

# device_type, in enum order (RGBControllerInterface.h), spelled the way
# `openrgb --list-devices` prints them - which is how the shell's exclusion
# lists name them.
DEVICE_TYPES = [
    "Motherboard", "DRAM", "GPU", "Cooler", "LED Strip", "Keyboard", "Mouse",
    "Mouse Mat", "Headset", "Headset Stand", "Gamepad", "Light", "Speaker",
    "Virtual", "Storage", "Case", "Microphone", "Accessory", "Keypad",
    "Laptop", "Monitor", "Unknown",
]

# Modes we will stream to, in order of preference. Direct is what the
# Effects plugin uses: colours go to the LEDs and nowhere else, so nothing
# is flashed to a controller's memory on every frame.
STREAM_MODES = ("Direct", "Static")


# ---- wire format ---------------------------------------------------------

def type_name(index):
    return DEVICE_TYPES[index] if 0 <= index < len(DEVICE_TYPES) else "Unknown"


def pack_color(hex6):
    r, g, b = int(hex6[0:2], 16), int(hex6[2:4], 16), int(hex6[4:6], 16)
    return struct.pack("<BBBx", r, g, b)


def pack_update_leds(count, hex6):
    body = struct.pack("<H", count) + pack_color(hex6) * count
    return struct.pack("<I", len(body) + 4) + body


def pack_update_mode(mode_index, mode_bytes):
    body = struct.pack("<i", mode_index) + mode_bytes
    return struct.pack("<I", len(body) + 4) + body


def read_string(buf, pos):
    (length,) = struct.unpack_from("<H", buf, pos)
    pos += 2
    raw = buf[pos:pos + length]
    return raw.rstrip(b"\0").decode("utf-8", "replace"), pos + length


def parse_mode(buf, pos, version):
    """Returns (name, active-colour count, end) - and the caller slices the
    bytes between start and end to echo the mode back untouched."""
    name, pos = read_string(buf, pos)
    pos += 4 * 2  # value, flags
    pos += 4 * 2  # speed_min, speed_max
    if version >= 3:
        pos += 4 * 2  # brightness_min, brightness_max
    pos += 4 * 2  # colors_min, colors_max
    pos += 4  # speed
    if version >= 3:
        pos += 4  # brightness
    pos += 4 * 2  # direction, color_mode
    (num_colors,) = struct.unpack_from("<H", buf, pos)
    pos += 2 + 4 * num_colors
    return name, pos


def parse_controller(buf, version=PROTOCOL_VERSION):
    """The parts of a controller description this streamer needs: type,
    name, the index and bytes of its stream mode, and how many colours a
    frame carries. Zones and LEDs are walked past, not kept."""
    pos = 0
    (size,) = struct.unpack_from("<I", buf, pos)
    if size == len(buf):
        pos += 4  # the description is prefixed with its own length
    (dev_type,) = struct.unpack_from("<i", buf, pos)
    pos += 4
    name, pos = read_string(buf, pos)
    if version >= 1:
        _vendor, pos = read_string(buf, pos)
    for _ in range(4):  # description, version, serial, location
        _, pos = read_string(buf, pos)
    (num_modes,) = struct.unpack_from("<H", buf, pos)
    pos += 2
    (active_mode,) = struct.unpack_from("<i", buf, pos)
    pos += 4
    modes = []
    for _ in range(num_modes):
        start = pos
        mode_name, pos = parse_mode(buf, pos, version)
        modes.append((mode_name, buf[start:pos]))
    (num_zones,) = struct.unpack_from("<H", buf, pos)
    pos += 2
    for _ in range(num_zones):
        _, pos = read_string(buf, pos)
        pos += 4 + 4 * 3  # type, leds_min, leds_max, leds_count
        (matrix_len,) = struct.unpack_from("<H", buf, pos)
        pos += 2 + matrix_len
        if version >= 4:
            (num_segments,) = struct.unpack_from("<H", buf, pos)
            pos += 2
            for _ in range(num_segments):
                _, pos = read_string(buf, pos)
                pos += 4 * 3  # type, start_idx, leds_count
    (num_leds,) = struct.unpack_from("<H", buf, pos)
    pos += 2
    for _ in range(num_leds):
        _, pos = read_string(buf, pos)
        pos += 4  # value
    (num_colors,) = struct.unpack_from("<H", buf, pos)
    stream_mode = None
    for wanted in STREAM_MODES:
        for index, (mode_name, mode_bytes) in enumerate(modes):
            if mode_name == wanted:
                stream_mode = (index, mode_bytes)
                break
        if stream_mode:
            break
    return {
        "type": type_name(dev_type),
        "name": name,
        "active_mode": active_mode,
        "stream_mode": stream_mode,
        "num_colors": num_colors,
    }


# ---- colour ---------------------------------------------------------------

def split_hex(hex6):
    return [int(hex6[i:i + 2], 16) for i in (0, 2, 4)]


def join_hex(rgb):
    return "".join(f"{max(0, min(255, int(round(c)))):02X}" for c in rgb)


def step_toward(current, target, smoothing):
    """One tick of the ramp: cover `smoothing` of what is left, and snap
    when what is left rounds to nothing - a ramp that only ever halves
    never arrives, and a frame that changes nothing is a frame wasted."""
    out = []
    for c, t in zip(current, target):
        delta = t - c
        if abs(delta) < 1.0:
            out.append(float(t))
        else:
            out.append(c + delta * smoothing)
    return out


# ---- the client -------------------------------------------------------------

class Client:
    def __init__(self, host, port, excluded_names, excluded_types, log):
        self.host, self.port = host, port
        self.excluded_names = set(excluded_names)
        self.excluded_types = set(excluded_types)
        self.log = log
        self.sock = None
        self.devices = []  # [(dev_id, num_colors)] we stream to

    # -- framing --
    def send(self, dev_id, packet_id, payload=b""):
        self.sock.sendall(HEADER.pack(MAGIC, dev_id, packet_id, len(payload)) + payload)

    def read_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("server closed the connection")
            buf += chunk
        return buf

    def read_packet(self):
        magic, dev_id, packet_id, size = HEADER.unpack(self.read_exact(HEADER.size))
        if magic != MAGIC:
            raise ConnectionError("bad packet magic")
        return dev_id, packet_id, self.read_exact(size)

    def read_reply(self, packet_id):
        """The next reply of a kind, absorbing anything unsolicited."""
        while True:
            dev_id, got, payload = self.read_packet()
            if got == packet_id:
                return dev_id, payload
            self.unsolicited(got)

    def unsolicited(self, packet_id):
        if packet_id == DEVICE_LIST_UPDATED:
            self.log("device list changed; re-reading controllers")
            self.needs_refresh = True

    # -- lifecycle --
    def connect(self):
        self.sock = socket.create_connection((self.host, self.port), timeout=5)
        self.sock.settimeout(5)
        self.needs_refresh = False
        self.send(0, REQUEST_PROTOCOL_VERSION, struct.pack("<I", PROTOCOL_VERSION))
        try:
            _, payload = self.read_reply(REQUEST_PROTOCOL_VERSION)
            (server_version,) = struct.unpack("<I", payload)
        except socket.timeout:
            server_version = 0
        self.version = min(PROTOCOL_VERSION, server_version)
        self.send(0, SET_CLIENT_NAME, CLIENT_NAME)
        self.load_devices()

    def load_devices(self):
        self.needs_refresh = False
        self.send(0, REQUEST_CONTROLLER_COUNT)
        _, payload = self.read_reply(REQUEST_CONTROLLER_COUNT)
        (count,) = struct.unpack("<I", payload)
        self.devices = []
        for dev_id in range(count):
            self.send(dev_id, REQUEST_CONTROLLER_DATA, struct.pack("<I", self.version))
            _, payload = self.read_reply(REQUEST_CONTROLLER_DATA)
            info = parse_controller(payload, self.version)
            skip = None
            if info["name"] in self.excluded_names:
                skip = "excluded by name"
            elif info["type"] in self.excluded_types:
                skip = f"excluded by type {info['type']}"
            elif info["stream_mode"] is None:
                skip = "has neither a Direct nor a Static mode"
            elif info["num_colors"] == 0:
                skip = "has no LEDs"
            if skip:
                self.log(f"skipping {dev_id} {info['name']!r}: {skip}")
                continue
            mode_index, mode_bytes = info["stream_mode"]
            # ONCE, and only when the controller is not already there: the
            # mode command is the re-initialisation that blinks.
            if info["active_mode"] != mode_index:
                self.send(dev_id, RGBCONTROLLER_UPDATEMODE, pack_update_mode(mode_index, mode_bytes))
                self.log(f"{dev_id} {info['name']!r}: mode -> {mode_index}")
            self.devices.append((dev_id, info["num_colors"]))

    def drain(self):
        """Unsolicited packets between frames, without blocking."""
        while True:
            ready, _, _ = select.select([self.sock], [], [], 0)
            if not ready:
                return
            _, packet_id, _ = self.read_packet()
            self.unsolicited(packet_id)

    def write_frame(self, hex6):
        self.drain()
        if self.needs_refresh:
            self.load_devices()
        for dev_id, count in self.devices:
            self.send(dev_id, RGBCONTROLLER_UPDATELEDS, pack_update_leds(count, hex6))

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None


# ---- main loop --------------------------------------------------------------

def read_targets(stdin, timeout):
    """Every complete line waiting on stdin within `timeout`; the last one
    wins. None when stdin has closed."""
    ready, _, _ = select.select([stdin], [], [], timeout)
    if not ready:
        return []
    lines = []
    while True:
        line = stdin.readline()
        if line == "":
            return None if not lines else lines
        line = line.strip().lstrip("#")
        if len(line) == 6:
            try:
                int(line, 16)
                lines.append(line.upper())
            except ValueError:
                pass
        ready, _, _ = select.select([stdin], [], [], 0)
        if not ready:
            return lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6742)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--smoothing", type=float, default=0.25,
                        help="fraction of the remaining distance covered per tick")
    parser.add_argument("--exclude-name", action="append", default=[])
    parser.add_argument("--exclude-type", action="append", default=[])
    parser.add_argument("--retry", type=float, default=1.0, help="seconds between reconnects")
    args = parser.parse_args(argv)

    def log(message):
        print(f"[openrgb-stream] {message}", file=sys.stderr, flush=True)

    def say(message):
        print(message, flush=True)

    client = Client(args.host, args.port, args.exclude_name, args.exclude_type, log)
    tick = 1.0 / max(1.0, args.fps)
    target = None
    current = None
    stdin_open = True

    while stdin_open:
        try:
            client.connect()
        except (OSError, ConnectionError, struct.error) as error:
            log(f"connect failed: {error}; retrying in {args.retry}s")
            lines = read_targets(sys.stdin, args.retry)
            if lines is None:
                break
            if lines:
                target = split_hex(lines[-1])
            continue
        say(f"ready {len(client.devices)}")
        current = None  # a fresh connection starts from whatever the target is
        try:
            while True:
                moving = target is not None and current != target
                lines = read_targets(sys.stdin, tick if moving else None)
                if lines is None:
                    stdin_open = False
                    break
                if lines:
                    target = split_hex(lines[-1])
                if target is None:
                    continue
                if current is None:
                    current = list(target)
                    client.write_frame(join_hex(current))
                    continue
                if current == target:
                    continue
                current = step_toward(current, target, args.smoothing)
                client.write_frame(join_hex(current))
        except (OSError, ConnectionError, struct.error) as error:
            log(f"connection lost: {error}")
            say("lost")
            client.close()
            time.sleep(args.retry)
    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
