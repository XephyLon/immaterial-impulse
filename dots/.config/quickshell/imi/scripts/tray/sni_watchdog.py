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
import os
import subprocess
import sys
import time

WATCHER = "org.kde.StatusNotifierWatcher"
POLL_S = 3
ABSENT_GRACE_S = 6


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


def main():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock = open(os.path.join(runtime, "imi-sni-watchdog.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0  # a watchdog is already on duty

    state = {"owner": None, "absent_since": None, "remembered": {}}
    ensure_xapp()  # a queue-holder from the start
    while True:
        try:
            owner = get_owner()
            items = get_items() if owner else []
            live = get_live_services() if owner or state["remembered"] else set()
            state, actions = plan_actions(state, owner, items, live, time.time())
            for action in actions:
                print(f"[sni-watchdog] {action}", flush=True)
                run_action(action)
        except Exception as e:  # a poll may fail; the loop must not
            print(f"[sni-watchdog] tick failed: {e}", flush=True)
        time.sleep(POLL_S)


if __name__ == "__main__":
    sys.exit(main())
