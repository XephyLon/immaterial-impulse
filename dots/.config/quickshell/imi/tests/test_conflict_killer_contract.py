"""Safety-envelope contract for services/ConflictKiller.qml.

ConflictKiller kills processes that conflict with the shell (foreign tray and
notification daemons). Because a bug here terminates other people's software,
these checks pin the mechanism itself:

- detection is presence-only (`pidof` output is checked for emptiness, never
  reused as PIDs to signal),
- killing goes through `killall <exact-name>` with a fixed literal name set
  (killall matches on exact process name; no regex/substring matching like a
  bare pkill, and no interpolated names),
- the shell itself (`qs`) is never a kill target,
- it runs once when the config becomes ready — no polling Timer sweeping the
  process table.
"""

import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "ConflictKiller.qml"

# The conscious, reviewed list of processes this service may kill. Adding a
# name to ConflictKiller.qml must come with an update here.
ALLOWED_KILL_TARGETS = {"kded6", "mako", "dunst"}


def _source() -> str:
    return SERVICE.read_text()


def _exec_detached_calls() -> list:
    return re.findall(r"Quickshell\.execDetached\(\[(.*?)\]\)", _source())


def test_detection_uses_pidof_presence_only():
    source = _source()
    match = re.search(r'command:\s*\["bash",\s*"-c",\s*`(.*)`\]', source)
    assert match, "detection command not found"
    detection = match.group(1)
    assert detection == 'echo "$(pidof kded6);$(pidof mako dunst)"'
    # pidof appears nowhere else: its output can never leak into a kill.
    assert source.count("pidof") == detection.count("pidof") == 2
    # The collector only checks emptiness of each side of the ";".
    assert 'output.split(";")[0].trim().length > 0' in source
    assert 'output.split(";")[1].trim().length > 0' in source


def test_detection_output_shape_matches_parser():
    # Behavioral: run the actual detection command with a stubbed pidof and
    # confirm the "<trays>;<notifdaemons>" shape the collector splits on.
    source = _source()
    detection = re.search(r'command:\s*\["bash",\s*"-c",\s*`(.*)`\]', source).group(1)
    with tempfile.TemporaryDirectory() as tmp:
        stub = Path(tmp) / "pidof"
        stub.write_text(
            "#!/bin/bash\n"
            'if [[ "$1" == "kded6" ]]; then echo "1234"; exit 0; fi\n'
            "exit 1\n"
        )
        stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        env = dict(os.environ)
        env["PATH"] = f"{tmp}:{env.get('PATH', '')}"
        result = subprocess.run(["bash", "-c", detection],
                                env=env, capture_output=True, text=True, timeout=30)
    out = result.stdout.strip()
    parts = out.split(";")
    assert len(parts) == 2, f"expected exactly one ';' separator, got {out!r}"
    assert parts[0].strip() == "1234"  # conflicting tray present
    assert parts[1].strip() == ""      # no conflicting notification daemon


def test_kill_commands_are_exact_name_killall_with_fixed_literals():
    source = _source()
    assert '["killall", "kded6"]' in source
    assert '["killall", "mako", "dunst"]' in source

    kill_targets = set()
    for call in _exec_detached_calls():
        items = [item.strip() for item in call.split(",")]
        if items[0] != '"killall"':
            continue
        # Every argument must be a double-quoted literal: no ${...} splices,
        # no identifiers, no PIDs.
        for arg in items[1:]:
            assert re.fullmatch(r'"[a-z0-9]+"', arg), f"non-literal kill arg: {arg}"
            kill_targets.add(arg.strip('"'))
    assert kill_targets == ALLOWED_KILL_TARGETS, (
        f"kill list changed: {sorted(kill_targets)} — additions must be conscious"
    )


def test_no_pid_or_pattern_based_killing():
    source = _source()
    assert "pkill" not in source           # pkill default-matches by regex
    assert '"kill"' not in source          # no raw kill-by-PID
    assert "kill -" not in source
    assert "SIGKILL" not in source and "-9" not in source
    # No interpolation anywhere near killall: the argv is a compile-time literal.
    for call in _exec_detached_calls():
        if '"killall"' in call:
            assert "$" not in call and "`" not in call


def test_never_targets_the_shell_itself():
    for target in ALLOWED_KILL_TARGETS:
        assert "quickshell" not in target
        assert target != "qs"
    # `qs` only appears as the launcher of the conflict dialog, never as prey.
    assert '["qs", "-p", root.killDialogQmlPath]' in _source()


def test_kill_is_config_gated_and_runs_once():
    source = _source()
    # Auto-kill must remain opt-in per category; otherwise a dialog is shown.
    assert "if (!Config.options.conflictKiller.autoKillTrays) openDialog = true;" in source
    assert "if (!Config.options.conflictKiller.autoKillNotificationDaemons) openDialog = true;" in source
    # One-shot on config readiness — no Timer re-sweeping the process table.
    assert "Timer" not in source
    assert "if (Config.ready) checkConflictsProc.running = true" in source


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
