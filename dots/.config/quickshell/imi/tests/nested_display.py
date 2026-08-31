"""A headless compositor of the harness's own, so a test never draws on the
developer's screen.

Every `run_*_probe.sh` already starts its own weston; the Python harnesses did
not, so a suite run opened and closed a dozen real windows across whatever the
user was doing - `qs -p` on the session's `WAYLAND_DISPLAY` maps its surfaces
on the session's compositor. That is not only a nuisance: a harness that maps
a layer surface on the live display is one keystroke away from covering the
user's screen, and the lock-screen harness had to be nested for exactly that
reason (a real `WlSessionLock` on this machine suspends the laptop).

Isolation is three environment variables and a process, and getting any one of
them wrong is silent:

  - `XDG_RUNTIME_DIR` must be the harness's own, or the nested weston's socket
    lands beside the session's and `qs` can pick either.
  - `WAYLAND_DISPLAY` names the nested socket. libwayland prefixes the runtime
    dir onto a relative name, which is why the two must move together.
  - `HYPRLAND_INSTANCE_SIGNATURE` must go, because `hyprctl` reads it and
    NOTHING else - a harness that leaves it set talks to the user's
    compositor even with every other variable redirected (AGENT.md records
    this one; `tests/run_notification_blur_probe.sh` shipped it as a bug).

`DISPLAY` is dropped too, so nothing falls back to XWayland on the real X
server.
"""

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

BINARIES = ("qs", "weston", "dbus-run-session")


def available():
    """Whether a nested display can be started at all.

    Deliberately NOT a check for `WAYLAND_DISPLAY`: a harness that nests its
    own compositor does not need the caller to be in a graphical session, and
    gating on one is what tied these tests to the developer's screen.
    """
    return all(shutil.which(binary) is not None for binary in BINARIES)


def start(case, prefix, width=1500, height=900):
    """Start a headless weston for `case` and return the env pointing at it.

    `case` is the TestCase: the compositor and its runtime directory are
    registered as its cleanups, so a failing assertion still takes them down.
    """
    base = Path(tempfile.mkdtemp(prefix=f"imi-{prefix}-display-"))
    case.addCleanup(shutil.rmtree, base, ignore_errors=True)

    runtime = base / "runtime"
    runtime.mkdir(mode=0o700)
    socket = f"wayland-imi-{prefix}"

    env = dict(os.environ)
    env["XDG_RUNTIME_DIR"] = str(runtime)
    env["WAYLAND_DISPLAY"] = socket
    env.pop("DISPLAY", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    # Software everywhere: a headless weston has no GPU context worth using,
    # and the pixman renderer is what makes this run on a machine with no
    # display at all (CI).
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    env["QT_QUICK_BACKEND"] = "software"

    weston = subprocess.Popen(
        ["weston", "--backend=headless", "--renderer=pixman",
         f"--socket={socket}", f"--width={width}", f"--height={height}"],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    case.addCleanup(_stop, weston)

    socket_path = runtime / socket
    deadline = time.monotonic() + 15
    while not socket_path.exists() and time.monotonic() < deadline:
        time.sleep(0.2)
    if not socket_path.exists():
        raise AssertionError("headless weston never came up")
    return env


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


def run_harness_with_bus_retry(args, *, env, cwd, timeout, marker, retries=1):
    """Run a qs harness, retrying once when the nested dbus collapsed.

    Two different runtime suites have now failed the same way (notes
    migration 2026-08-31, phone preview lifetime 2026-09-01): every check
    printed "ok", then "A connection to the bus can't be made" and the
    summary line never arrived - the session bus died under the harness
    during teardown. That is the environment failing, not the code under
    test, and it reproduces neither solo nor on the next full run. The
    retry triggers ONLY on that signature: the marker missing AND the bus
    complaint present. A real failure - a check printing FAIL, a summary
    reporting failures - returns immediately.
    """
    import subprocess
    for attempt in range(retries + 1):
        proc = subprocess.run(args, cwd=cwd, env=env,
                              capture_output=True, text=True, timeout=timeout)
        output = proc.stdout + proc.stderr
        bus_died = ("connection to the bus" in output.lower()
                    and marker not in output)
        if not bus_died or attempt == retries:
            return proc
        print(f"[nested_display] session bus collapsed under the harness; retrying ({attempt + 1}/{retries})")
    return proc
