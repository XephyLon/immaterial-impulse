#!/usr/bin/env python3
"""The SNI watcher watchdog.

The tray's weak joint, observed live on 2026-08-31: the DBus watcher
(org.kde.StatusNotifierWatcher, owned by kded6 here) occasionally dies,
and Electron apps never re-register their StatusNotifierItems afterwards
- the icons are gone until each app is restarted. Steam and other
libayatana clients re-register themselves.

So this daemon, started by the shell and flock-guarded so restarts never
stack copies:

  - polls the watcher's owner and its RegisteredStatusNotifierItems;
  - remembers every registration it has seen, per owning service;
  - if the watcher is ABSENT, reactivates it (kded6's module - a
    persistent watcher that outlives shell restarts is the architecture,
    the shell is host-only);
  - when the watcher RETURNS with a new owner, re-registers the
    remembered items whose owning service still exists on the bus.
    Only standard-path items (bare service, or /StatusNotifierItem) are
    resurrected: an explicit ayatana path in the stored entry marks a
    client that re-registers itself, and third-party registration cannot
    carry a custom path anyway.

All bus work goes through busctl; the decision logic is pure
(plan_actions) and unit-tested without a bus.
"""
import fcntl
import json
import os
import select
import subprocess
import sys
import time

WATCHER = "org.kde.StatusNotifierWatcher"
# The loop is event-driven (busctl monitor on the watcher's name and its
# item signals); POLL_S is the heartbeat behind it. It was a 3 s poll of
# three busctl calls plus a pgrep - four processes every three seconds, all
# day, forked from a shell that weighs gigabytes - for a watcher that
# changes owner a few times a week.
POLL_S = 60
ABSENT_GRACE_S = 6
# Debounce: a watcher rebirth is a burst of signals; one tick answers them.
EVENT_SETTLE_S = 0.5


# ---------------------------------------------------------------- pure ----
def parse_items(busctl_output):
    """`busctl get-property` prints: as N ":1.5/path" ":1.7/path" ..."""
    parts = busctl_output.strip().split('"')
    return [parts[i] for i in range(1, len(parts), 2)]


def service_of(item):
    return item.split("/", 1)[0]


def resurrectable(item):
    """Standard-path items only; ayatana-path clients re-register themselves."""
    if "/" not in item:
        return True
    return item.split("/", 1)[1] == "StatusNotifierItem"


def relevant_event(line, watcher=WATCHER):
    """One `busctl monitor --json=short` line: is it about the watcher?
    NameOwnerChanged for the watcher's name (born, died, replaced), or one
    of the watcher's own item signals. Anything else - other names, noise,
    a non-JSON line - is not a reason to poll."""
    try:
        msg = json.loads(line)
    except (TypeError, ValueError):
        return False
    if not isinstance(msg, dict) or msg.get("type") != "signal":
        return False
    member = msg.get("member", "")
    iface = msg.get("interface", "")
    if iface == "org.freedesktop.DBus" and member == "NameOwnerChanged":
        data = (msg.get("payload") or {}).get("data") or []
        return bool(data) and data[0] == watcher
    if iface == watcher and member in ("StatusNotifierItemRegistered",
                                       "StatusNotifierItemUnregistered",
                                       "StatusNotifierHostRegistered"):
        return True
    return False


def plan_actions(state, owner, items, live_services, now):
    """One poll tick. Returns (new_state, actions).

    state: {"owner": str|None, "absent_since": float|None,
            "remembered": {service: item}}
    actions: list of ("activate",) | ("register", service) tuples.
    """
    remembered = dict(state.get("remembered", {}))
    actions = []

    if owner:
        for item in items:
            if resurrectable(item):
                remembered[service_of(item)] = item
        # A service that left the bus has nothing to resurrect.
        remembered = {s: i for s, i in remembered.items() if s in live_services}

        prev_owner = state.get("owner")
        if prev_owner and prev_owner != owner:
            # The watcher was reborn: hand it everything it should know.
            registered = {service_of(i) for i in items}
            for service, _ in sorted(remembered.items()):
                if service in live_services and service not in registered:
                    actions.append(("register", service))
        return ({"owner": owner, "absent_since": None,
                 "remembered": remembered}, actions)

    absent_since = state.get("absent_since") or now
    if now - absent_since >= ABSENT_GRACE_S:
        actions.append(("activate",))
        absent_since = now  # do not spam every tick
    return ({"owner": None, "absent_since": absent_since,
             "remembered": remembered}, actions)


# ------------------------------------------------------------- bus glue ----
def busctl(*args):
    result = subprocess.run(["busctl", "--user", *args],
                            capture_output=True, text=True, timeout=10)
    return result.returncode, result.stdout


def get_owner():
    code, out = busctl("status", WATCHER)
    if code != 0:
        return None
    for line in out.splitlines():
        if line.startswith("PID="):
            return line.strip()
    return None


def get_items():
    code, out = busctl("get-property", f"{WATCHER}", "/StatusNotifierWatcher",
                       WATCHER, "RegisteredStatusNotifierItems")
    return parse_items(out) if code == 0 else []


def get_live_services():
    code, out = busctl("list", "--no-pager")
    if code != 0:
        return set()
    return {line.split()[0] for line in out.splitlines()
            if line.strip().startswith(":")}


XAPP_WATCHER = "/usr/lib/xapps/xapp-sn-watcher"


def ensure_xapp():
    """Keep xapp-sn-watcher present as the org.x watcher and fallback.

    Measured 2026-08-31: it does NOT claim or queue for the org.kde
    name - quickshell owns that when kded6 is out of the way. The
    session's real stabilizer was removing kded6 (SIGSEGV-looping, its
    user dbus activation masked, its zombie cgroup purged); this keeps
    the org.x side served for xapp-expecting clients. Needs 'Hyprland'
    in org.x.apps.statusicon status-notifier-enabled-desktops (set on
    this machine)."""
    if not os.path.exists(XAPP_WATCHER):
        return False
    probe = subprocess.run(["pgrep", "-x", "xapp-sn-watcher"],
                           capture_output=True)
    if probe.returncode != 0:
        subprocess.Popen([XAPP_WATCHER], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True


def run_action(action):
    if action[0] == "activate":
        if not ensure_xapp():
            # Fallback where xapp is absent: kded6's module.
            busctl("call", "org.kde.kded6", "/kded", "org.kde.kded6",
                   "loadModule", "s", "statusnotifierwatcher")
    elif action[0] == "register":
        busctl("call", WATCHER, "/StatusNotifierWatcher", WATCHER,
               "RegisterStatusNotifierItem", "s", action[1])


def tick(state):
    owner = get_owner()
    items = get_items() if owner else []
    live = get_live_services() if owner or state["remembered"] else set()
    state, actions = plan_actions(state, owner, items, live, time.time())
    for action in actions:
        print(f"[sni-watchdog] {action}", flush=True)
        run_action(action)
    return state


def start_monitor():
    """A resident `busctl monitor` filtered to the watcher: its name's owner
    changes and its item signals. Returns the Popen, or None."""
    matches = [
        "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',"
        f"member='NameOwnerChanged',arg0='{WATCHER}'",
        f"type='signal',interface='{WATCHER}'",
    ]
    args = ["busctl", "--user", "monitor", "--json=short"]
    for m in matches:
        args += ["--match", m]
    try:
        return subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, bufsize=1)
    except OSError:
        return None


def main():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock = open(os.path.join(runtime, "imi-sni-watchdog.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0  # a watchdog is already on duty
    state = {"owner": None, "absent_since": None, "remembered": {}}
    ensure_xapp()  # a queue-holder from the start
    monitor = None
    next_heartbeat = 0.0
    pending_since = None
    while True:
        try:
            if monitor is None or monitor.poll() is not None:
                monitor = start_monitor()
                if monitor is None:
                    time.sleep(POLL_S)  # no busctl monitor: heartbeat only
                    state = tick(state)
                    continue
            now = time.time()
            if pending_since is not None and now - pending_since >= EVENT_SETTLE_S:
                pending_since = None
                state = tick(state)
                next_heartbeat = now + POLL_S
            elif now >= next_heartbeat:
                state = tick(state)
                next_heartbeat = now + POLL_S
            wait = EVENT_SETTLE_S if pending_since is not None else max(0.0, next_heartbeat - now)
            ready, _, _ = select.select([monitor.stdout], [], [], wait)
            if ready:
                line = monitor.stdout.readline()
                if line == "":
                    continue  # monitor died; the loop restarts it
                if relevant_event(line) and pending_since is None:
                    pending_since = time.time()
        except Exception as e:  # a tick may fail; the loop must not
            print(f"[sni-watchdog] tick failed: {e}", flush=True)
            time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())
