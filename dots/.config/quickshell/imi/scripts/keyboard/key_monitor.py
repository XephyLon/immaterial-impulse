#!/usr/bin/env python3
"""Which physical keys are held down, as evdev keycodes and nothing else.

The on-screen keyboard shows what it types; this is what lets it also show what
the REAL keyboard is doing - a key lights up on screen while the finger is on
it. The keys the OSK draws already carry their evdev keycodes (that is how
ydotool types them), so a code off the wire lines up with a drawn key with no
table in between.

WHAT THIS DELIBERATELY DOES NOT DO, because a program that reads every key on
the machine has to be answerable for it:

  - It emits KEYCODES, never characters. There is no keymap here and no
    modifier state, so nothing it prints says what was typed - `30` is "the key
    at that position", the same number whether the user typed `a`, `A`, or a
    password's first letter.
  - It writes nothing to disk. One line per event to stdout, read by the shell
    and dropped.
  - It holds no history. The shell's consumer keeps a set of what is DOWN and
    forgets a key the moment it comes up.
  - It runs only while the on-screen keyboard is on screen. The service starts
    it on show and kills it on hide - see services/KeyMonitor.qml. A reader
    that ran all session would be a keylogger with a nice reason.

Reading /dev/input needs membership of the `input` group and nothing more - no
root, no setuid, no sudo. A machine whose user is not in that group gets no
readable device, this exits 0 saying so, and the OSK simply does not highlight.
That is the correct degradation: the feature is a nicety and the alternative is
asking for privilege the shell should not have.

The event struct is the kernel's `input_event`: two longs of timeval, then
type, code, value. It is stable ABI, which is why this needs no python-evdev.
"""

import argparse
import glob
import json
import os
import select
import struct
import sys

# struct input_event { struct timeval time; __u16 type; __u16 code; __s32 value; }
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY = 0x01
# A key repeat. Reported as 2 rather than 1, and the OSK wants it to change
# nothing: the key is already down and already lit.
VALUE_REPEAT = 2


def keyboard_devices(explicit=None):
    """Every readable keyboard event device, deduplicated by real path.

    `by-path` is used rather than `by-id` because a single keyboard can appear
    under several `by-id` names (this machine's shows up twice), and two file
    descriptors on one device report every press twice.
    """
    seen = []
    # Explicit devices are how this is tested: a test writes real
    # `input_event` structs into a file and points the reader at it, which
    # exercises the parse and the dedup without a keyboard or a fake /dev.
    for link in (explicit if explicit else
                 sorted(glob.glob("/dev/input/by-path/*-event-kbd"))):
        try:
            path = os.path.realpath(link)
        except OSError:
            continue
        if path not in seen and os.access(path, os.R_OK):
            seen.append(path)
    return seen


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", action="append", default=[],
                        help="read this device instead of discovering "
                             "keyboards (tests)")
    parser.add_argument("--once", action="store_true",
                        help="stop at end of input rather than blocking for "
                             "more (tests)")
    args = parser.parse_args(argv)

    devices = keyboard_devices(args.device)
    if not devices:
        # Not an error: the shell asks whether this works and draws
        # accordingly. Exiting non-zero would put a red herring in the log on
        # every machine whose user is not in the `input` group.
        json.dump({"state": "unavailable",
                   "reason": "no readable keyboard device in /dev/input"},
                  sys.stdout)
        sys.stdout.write("\n")
        return 0

    handles = {}
    for path in devices:
        try:
            handles[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
        except OSError:
            continue
    if not handles:
        json.dump({"state": "unavailable", "reason": "could not open any device"},
                  sys.stdout)
        sys.stdout.write("\n")
        return 0

    json.dump({"state": "watching", "devices": len(handles)}, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()

    exhausted = False
    while True:
        try:
            readable, _, _ = select.select(list(handles), [], [],
                                           0.2 if args.once else None)
        except (OSError, ValueError):
            return 0
        except KeyboardInterrupt:
            return 0
        for handle in readable:
            try:
                data = os.read(handle, EVENT_SIZE * 64)
            except BlockingIOError:
                continue
            except OSError:
                # The device went away - a keyboard was unplugged. Drop it and
                # keep the others rather than taking the whole monitor down.
                handles.pop(handle, None)
                exhausted = True
                try:
                    os.close(handle)
                except OSError:
                    pass
                if not handles:
                    return 0
                continue
            # A real device never reads empty - select said it was ready. A
            # FILE does, at EOF, which is how the tests feed it recorded
            # events: `--once` stops there instead of spinning on a fd that
            # will never have more.
            if not data and args.once:
                exhausted = True
            for offset in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                _, _, kind, code, value = struct.unpack(
                    EVENT_FORMAT, data[offset:offset + EVENT_SIZE])
                if kind != EV_KEY or value == VALUE_REPEAT:
                    continue
                sys.stdout.write(f'{{"code":{code},"down":{1 if value else 0}}}\n')
        sys.stdout.flush()
        if args.once and (exhausted or not readable):
            return 0


if __name__ == "__main__":
    sys.exit(main())
