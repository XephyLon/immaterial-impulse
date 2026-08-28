#!/usr/bin/env python3
"""scrcpy session supervisor for the Phone tab (services/PhoneScrcpy.qml).

One long-lived process speaking NDJSON on stdin/stdout. QML holds no scrcpy
process handles: it sends commands and reads events, and this supervisor owns
every scrcpy child, its window title and its exit.

Commands (one JSON object per line on stdin):
  {"cmd": "launch", "id": <session id>, "type": "mirror"|"app",
   "target_args": [...], "extra_args": [...]}
  {"cmd": "stop", "id": <session id>}
  {"cmd": "stop_all"}
  {"cmd": "focus", "id": <session id>}
  {"cmd": "list_apps", "target_args": [...], "deviceId": <cache key>}

Events (one JSON object per line on stdout):
  started    {id, pid, title[, alreadyRunning]}
  exited     {id, code, error}          error = scrcpy's last stderr line
  error      {id, message}
  apps_list  {deviceId, apps[, cached]} apps = [{package, name, system}]
  apps_error {message}

Every scrcpy child is spawned as
  scrcpy [-s <serial>] --window-title=imi-phone-<type>-<id> <extra_args...>
so that `focus` can address the window by its title and nothing else. The
`-s` target is resolved from `adb devices` on every launch: a USB serial (no
":" in it) wins over any ip:port, and only when adb lists nothing do the
caller's target_args stand. A wireless target the caller names is `adb
connect`ed first, bounded, so a phone on wireless debugging that adb has not
seen yet still resolves.

stdin closing means the shell went away; every session is stopped then, so a
shell restart never leaves headless scrcpy windows behind.
"""
import argparse
import collections
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

# scrcpy's last stderr line is what an `exited` event carries, so the drain
# below only has to keep the tail. Bounded because the drain runs for the
# life of the child and a chatty one is exactly the case it exists for.
STDERR_TAIL_LINES = 40
# How long to wait past the child's exit for the drain thread to see EOF.
STDERR_DRAIN_TIMEOUT = 2.0

CACHE_DIR = (Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
             / "immaterial-impulse" / "phone" / "apps")
TITLE_PREFIX = "imi-phone-"

# `scrcpy --list-apps` prints one app per line: `*` for a system app, `-` for
# a user app, then the label, then the package. The label may carry spaces.
APP_LINE = re.compile(r"^\s*([\*\-])\s+(.+?)\s+([a-zA-Z0-9_]+\.[a-zA-Z0-9_\.]+)\s*$")


def session_title(type_str, session_id):
    return TITLE_PREFIX + str(type_str) + "-" + str(session_id).replace(":", "_")


def parse_app_list(lines):
    apps = []
    for line in lines:
        match = APP_LINE.match(line)
        if match:
            symbol, name, pkg = match.groups()
            apps.append({"package": pkg.strip(), "name": name.strip(),
                         "system": symbol == "*"})
    return apps


def parse_pm_list(lines):
    apps = []
    for line in lines:
        line = line.strip()
        if line.startswith("package:"):
            pkg = line[len("package:"):].strip()
            apps.append({"package": pkg, "name": pkg.split(".")[-1].capitalize(),
                         "system": False})
    return apps


def dedupe_sorted(apps):
    seen = set()
    unique = []
    for app in apps:
        if app["package"] in seen:
            continue
        seen.add(app["package"])
        unique.append(app)
    unique.sort(key=lambda app: app["name"].lower())
    return unique


def cache_path(device_id):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", str(device_id) or "default")
    return CACHE_DIR / f"{safe}.json"


class ScrcpySessionManager:
    def __init__(self):
        self.lock = threading.Lock()
        # A lock of its own, never `self.lock`: that one is held around the
        # process maps and an emit inside it would tie the two orders
        # together.
        self.emit_lock = threading.Lock()
        self.processes = {}     # session_id -> subprocess.Popen
        self.session_info = {}  # session_id -> {id, type, title, pid, startedAt}
        # The app scan runs on a worker of its own (see request_apps).
        self.apps_queue = queue.Queue()
        self.apps_worker = None

    def emit(self, event):
        """One lock around one write.

        `print(json.dumps(event), flush=True)` is two writes into a shared
        buffered stream, and every reaper thread emits `exited` concurrently
        with the main thread and with the app scan. An event large enough to
        flush part way through - an `apps_list` for a real phone is tens of
        kilobytes - can therefore be split by another thread's line, and
        interleaved NDJSON makes the QML parser return null and drop BOTH
        events. A lost `exited` leaves a session row live with no window
        behind it. Observed against real stdout at roughly one corruption in
        three runs of a stress harness.
        """
        line = json.dumps(event) + "\n"
        try:
            with self.emit_lock:
                sys.stdout.write(line)
                sys.stdout.flush()
        except Exception as error:  # a closed stdout: nothing left to tell
            sys.stderr.write(f"emit failed: {error}\n")

    # ---- adb -------------------------------------------------------------

    @staticmethod
    def wireless_serial(target_args):
        args = list(target_args or [])
        for index, arg in enumerate(args):
            if arg == "-s" and index + 1 < len(args) and ":" in args[index + 1]:
                return args[index + 1]
        return ""

    def connect_wireless(self, target_args):
        serial = self.wireless_serial(target_args)
        if not serial:
            return
        try:
            subprocess.run(["adb", "connect", serial], capture_output=True,
                           text=True, timeout=4)
        except Exception:
            pass

    def resolve_adb_target(self, target_args=None):
        self.connect_wireless(target_args)
        try:
            res = subprocess.run(["adb", "devices"], capture_output=True,
                                 text=True, timeout=4)
            usb_devices = []
            ip_devices = []
            for line in res.stdout.splitlines():
                line = line.strip()
                if not line or line.startswith("List of"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "device":
                    serial = parts[0]
                    (ip_devices if ":" in serial else usb_devices).append(serial)
            if usb_devices:
                return ["-s", usb_devices[0]]
            if ip_devices:
                return ["-s", ip_devices[0]]
        except Exception:
            pass
        return list(target_args or [])

    # ---- apps ------------------------------------------------------------

    def emit_cached_apps(self, device_id):
        path = cache_path(device_id)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            apps = data.get("apps")
        except Exception:
            return
        if isinstance(apps, list) and apps:
            self.emit({"event": "apps_list", "deviceId": device_id,
                       "apps": apps, "cached": True})

    def write_cache(self, device_id, apps):
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            path = cache_path(device_id)
            tmp = path.with_suffix(".json.tmp")
            tmp.write_text(json.dumps({"deviceId": device_id,
                                       "generatedAt": int(time.time()),
                                       "apps": apps}), encoding="utf-8")
            os.replace(tmp, path)
        except Exception as error:
            sys.stderr.write(f"cache write failed: {error}\n")

    def request_apps(self, target_args=None, device_id="default"):
        """Queue an app scan for the worker, and return to reading stdin.

        `list_apps` was called straight from the command loop, and it is
        worth up to ~26 seconds of blocking subprocesses: `adb connect` (4s)
        + `adb devices` (4s) + `scrcpy --list-apps` (10s) + `pm list` (8s).
        For all of that time `stop`, `stop_all` and `focus` were not even
        read off stdin, so a click on a live mirror did nothing until the
        scan the user had not asked about finished. Measured with a fake
        that sleeps 4s in `--list-apps`: a focus sent 0.3s in was acted on at
        4.01s.

        A queue with one worker rather than a thread per request, so two
        scans cannot run `adb` at each other, and so every request is
        answered in the order it arrived - a scan dropped as a duplicate is
        an `apps_list` the page waits for and never gets.
        """
        if self.apps_worker is None or not self.apps_worker.is_alive():
            self.apps_worker = threading.Thread(target=self._apps_loop, daemon=True)
            self.apps_worker.start()
        self.apps_queue.put((target_args, device_id))

    def _apps_loop(self):
        while True:
            target_args, device_id = self.apps_queue.get()
            try:
                self.list_apps(target_args, device_id)
            except Exception as error:
                self.emit({"event": "apps_error",
                           "message": f"Failed to list apps: {error}"})

    def list_apps(self, target_args=None, device_id="default"):
        device_id = device_id or "default"
        self.emit_cached_apps(device_id)
        target_args = self.resolve_adb_target(target_args)
        try:
            res = subprocess.run(["scrcpy"] + target_args + ["--list-apps"],
                                 capture_output=True, text=True, timeout=10)
            apps = parse_app_list(res.stdout.splitlines() + res.stderr.splitlines())

            device_ok = True
            if not apps:
                res_adb = subprocess.run(
                    ["adb"] + target_args + ["shell", "pm", "list", "packages", "-3"],
                    capture_output=True, text=True, timeout=8)
                device_ok = res_adb.returncode == 0
                if device_ok:
                    apps = parse_pm_list(res_adb.stdout.splitlines())

            # A phone that dropped off ADB is an error, not an empty catalog:
            # an empty list would wipe the apps already on screen.
            if not apps and not device_ok:
                self.emit({"event": "apps_error", "message": "Phone not reachable over ADB"})
                return

            unique = dedupe_sorted(apps)
            self.write_cache(device_id, unique)
            self.emit({"event": "apps_list", "deviceId": device_id, "apps": unique})
        except Exception as error:
            self.emit({"event": "apps_error", "message": f"Failed to list apps: {error}"})

    # ---- sessions --------------------------------------------------------

    def launch_session(self, session_id, type_str, target_args, extra_args):
        if not session_id:
            self.emit({"event": "error", "id": "", "message": "launch needs an id"})
            return
        with self.lock:
            proc = self.processes.get(session_id)
            if proc is not None and proc.poll() is None:
                pid = proc.pid
            else:
                pid = None
        if pid is not None:
            self.focus_session(session_id)
            self.emit({"event": "started", "id": session_id, "pid": pid,
                       "title": session_title(type_str, session_id),
                       "alreadyRunning": True})
            return

        title = session_title(type_str, session_id)
        cmd = (["scrcpy"] + self.resolve_adb_target(target_args)
               + ["--window-title=" + title] + list(extra_args or []))
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.PIPE, text=True)
        except Exception as error:
            self.emit({"event": "error", "id": session_id,
                       "message": f"Failed to launch scrcpy: {error}"})
            return

        with self.lock:
            self.processes[session_id] = proc
            self.session_info[session_id] = {
                "id": session_id, "type": type_str, "title": title,
                "pid": proc.pid, "startedAt": int(time.time())}
        self.emit({"event": "started", "id": session_id, "pid": proc.pid, "title": title})
        threading.Thread(target=self._wait_process, args=(session_id, proc),
                         daemon=True).start()

    @staticmethod
    def _drain_stderr(proc, tail):
        """Read the child's stderr for as long as it writes, keeping the tail.

        This used to be a single `proc.stderr.read()` AFTER `proc.wait()`.
        A pipe holds ~64 KiB: past that, scrcpy blocks in `write()` with
        nobody reading, so it never exits, `wait()` never returns, no
        `exited` event is ever emitted, and the card sits on "running" over a
        frozen mirror with nothing in any log. Draining while it runs is what
        `communicate()` does; a thread is used so the wait below still
        returns the moment the child is gone rather than when its stderr
        reaches EOF (a grandchild can hold that open).
        """
        stream = proc.stderr
        if stream is None:
            return
        try:
            for line in stream:
                stripped = line.strip()
                if stripped:
                    tail.append(stripped)
        except Exception:
            pass
        finally:
            try:
                stream.close()
            except Exception:
                pass

    def _wait_process(self, session_id, proc):
        tail = collections.deque(maxlen=STDERR_TAIL_LINES)
        drain = threading.Thread(target=self._drain_stderr, args=(proc, tail),
                                 daemon=True)
        drain.start()
        code = proc.wait()
        drain.join(timeout=STDERR_DRAIN_TIMEOUT)
        err_msg = tail[-1] if tail else ""
        with self.lock:
            if self.processes.get(session_id) is proc:
                del self.processes[session_id]
                self.session_info.pop(session_id, None)
        self.emit({"event": "exited", "id": session_id, "code": code, "error": err_msg})

    def stop_session(self, session_id):
        with self.lock:
            proc = self.processes.get(session_id)
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.terminate()
            for _ in range(20):
                if proc.poll() is not None:
                    return
                time.sleep(0.1)
            proc.kill()
        except Exception:
            pass

    def stop_all(self):
        with self.lock:
            ids = list(self.processes.keys())
        for session_id in ids:
            self.stop_session(session_id)

    def focus_session(self, session_id):
        with self.lock:
            info = self.session_info.get(session_id)
        if not info or not info.get("title"):
            return
        try:
            subprocess.run(["hyprctl", "dispatch", "focuswindow", f"title:^{info['title']}$"],
                           check=False, capture_output=True, timeout=4)
        except Exception:
            pass

    # ---- protocol --------------------------------------------------------

    def handle_line(self, line):
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line)
        except Exception as error:
            sys.stderr.write(f"command parse error: {error}\n")
            return
        cmd = msg.get("cmd")
        if cmd == "list_apps":
            self.request_apps(target_args=msg.get("target_args"),
                              device_id=msg.get("deviceId", "default"))
        elif cmd == "launch":
            self.launch_session(msg.get("id"), msg.get("type", "app"),
                                msg.get("target_args"), msg.get("extra_args"))
        elif cmd == "stop":
            self.stop_session(msg.get("id"))
        elif cmd == "stop_all":
            self.stop_all()
        elif cmd == "focus":
            self.focus_session(msg.get("id"))
        else:
            sys.stderr.write(f"unknown command: {cmd}\n")

    def run(self):
        for line in sys.stdin:
            self.handle_line(line)
        self.stop_all()


def main():
    parser = argparse.ArgumentParser(description="scrcpy session supervisor for Immaterial Impulse")
    parser.add_argument("--list-apps", action="store_true", help="list apps once and exit")
    parser.add_argument("--device-id", default="default", help="cache key for --list-apps")
    args = parser.parse_args()

    manager = ScrcpySessionManager()
    if args.list_apps:
        manager.list_apps(device_id=args.device_id)
        return 0
    manager.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
