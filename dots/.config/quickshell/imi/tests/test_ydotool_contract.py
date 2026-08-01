"""Contract checks for services/Ydotool.qml.

Ydotool synthesizes key events for the on-screen keyboard. The service is a
thin execDetached wrapper, so these checks pin its safety envelope:

- every command is an argv array invoking `ydotool` directly — no shell, so
  nothing can be spliced into a `bash -c` string (repo hard rule),
- the only string interpolation is the internal integer `keycode`,
- the keycode lists are fixed literals,
- there are no Process/Timer members at all, hence no restart loop to
  throttle: each call is a one-shot detached exec.

KNOWN GAP (pinned deliberately): the service does not manage or verify
YDOTOOL_SOCKET / the ydotoold daemon; if the daemon is down, key injection
fails silently. If socket handling is ever added, update the last test.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "Ydotool.qml"


def _source() -> str:
    return SERVICE.read_text()


def test_every_command_is_a_direct_ydotool_argv_array():
    source = _source()
    total = source.count("Quickshell.execDetached(")
    direct = len(re.findall(r'Quickshell\.execDetached\(\[\s*"ydotool"', source))
    assert total == direct == 4, (
        f"{direct}/{total} execDetached calls start with a literal ydotool argv"
    )


def test_no_shell_is_ever_involved():
    source = _source()
    assert '"bash"' not in source
    assert '"sh"' not in source
    assert '"-c"' not in source


def test_only_interpolated_value_is_the_internal_keycode():
    # The repo hard rule is "no external data spliced into bash -c"; here
    # there is no shell at all, and the only template interpolation is the
    # integer keycode from internal lists / typed parameters.
    interpolations = set(re.findall(r"\$\{([^}]*)\}", _source()))
    assert interpolations == {"keycode"}, f"unexpected interpolations: {interpolations}"


def test_keycode_lists_are_fixed_literals():
    source = _source()
    assert "property list<int> shiftKeys: [42, 54]" in source
    assert "property list<int> altKeys: [56, 100]" in source
    assert "property list<int> ctrlKeys: [29, 97]" in source
    # releaseAllKeys releases the whole evdev range in one call.
    assert "Array.from(Array(249).keys())" in source


def test_release_helpers_reset_shift_mode():
    source = _source()
    assert source.count("root.shiftMode = 0") >= 2, (
        "releaseAllKeys/releaseShiftKeys must reset shiftMode so the OSK "
        "does not believe shift is still held"
    )


def test_no_process_members_so_no_restart_loops():
    source = _source()
    assert "Process" not in source
    assert "Timer" not in source
    assert "import Quickshell.Io" not in source
    assert "running" not in source


def test_no_socket_or_env_management_yet():
    # Pins the current (known-gap) behavior: no environment or socket
    # handling exists. See module docstring.
    source = _source()
    assert "YDOTOOL_SOCKET" not in source
    assert "environment" not in source


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
