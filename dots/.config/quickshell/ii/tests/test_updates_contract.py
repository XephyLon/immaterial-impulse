"""Contract + behavioral checks for services/Updates.qml.

The update count is produced by an inline bash pipeline inside a Process and
parsed by a StdioCollector, so the parse cannot be unit-tested from QML. These
checks (a) extract the actual pipeline from the QML and execute it against
stub checkupdates/yay/paru binaries to pin its output shape, and (b) pin the
wiring invariants around it (availability gate, parseInt parse, strict-`>`
advise thresholds so a count of 0 never advises an update).
"""

import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UPDATES = ROOT / "services" / "Updates.qml"


def _count_pipeline() -> str:
    source = UPDATES.read_text()
    match = re.search(r'command:\s*\["bash",\s*"-c",\s*"(.*)"\]', source)
    assert match, "checkUpdatesProc bash pipeline not found in Updates.qml"
    pipeline = match.group(1)
    # The extraction above is only faithful while the QML string stays free of
    # escape sequences; fail loudly if someone adds any.
    assert "\\" not in pipeline, "pipeline now contains escapes; update the test extraction"
    return pipeline


def _run_pipeline(stubs: dict) -> str:
    pipeline = _count_pipeline()
    with tempfile.TemporaryDirectory() as tmp:
        for name, body in stubs.items():
            stub = Path(tmp) / name
            stub.write_text("#!/bin/bash\n" + body + "\n")
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        env = dict(os.environ)
        env["PATH"] = f"{tmp}:{env.get('PATH', '')}"
        result = subprocess.run(
            ["bash", "-c", pipeline],
            env=env, capture_output=True, text=True, timeout=30,
        )
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()


def test_pipeline_sums_pacman_and_aur_counts():
    out = _run_pipeline({
        "checkupdates": "printf 'a 1 -> 2\\nb 1 -> 2\\nc 1 -> 2\\n'",
        "yay": "printf 'aur1 1 -> 2\\naur2 1 -> 2\\n'",
        "paru": "exit 1",
    })
    assert out == "5"


def test_pipeline_reports_zero_when_everything_is_current():
    out = _run_pipeline({
        "checkupdates": "exit 2",  # checkupdates exits 2 when no updates
        "yay": "exit 0",
        "paru": "exit 1",
    })
    assert out == "0"


def test_pipeline_survives_missing_pacman_helper():
    # checkupdates failing (or absent: same empty-stdout shape thanks to
    # 2>/dev/null) must not poison the AUR count.
    out = _run_pipeline({
        "checkupdates": "exit 127",
        "yay": "printf 'one 1 -> 2\\ntwo 1 -> 2\\nthree 1 -> 2\\nfour 1 -> 2\\n'",
        "paru": "exit 1",
    })
    assert out == "4"


def test_pipeline_output_is_a_bare_integer_for_parseInt():
    out = _run_pipeline({
        "checkupdates": "printf 'a 1 -> 2\\n'",
        "yay": "exit 0",
        "paru": "exit 1",
    })
    assert re.fullmatch(r"\d+", out), f"pipeline output {out!r} is not parseInt-safe"
    # And the QML side actually parses it that way.
    assert "root.count = parseInt(text.trim())" in UPDATES.read_text()


def test_availability_is_gated_on_checkupdates_binary():
    source = UPDATES.read_text()
    assert 'command: ["which", "checkupdates"]' in source
    assert "root.available = (exitCode === 0)" in source
    # refresh() must be a no-op while unavailable so the pipeline never runs
    # on distros without checkupdates.
    assert re.search(r"function refresh\(\)\s*\{\s*if \(!available\)\s*return;", source)


def test_zero_count_never_advises_updates():
    source = UPDATES.read_text()
    # Strict `>` against the thresholds: count == 0 (or an unavailable
    # checker) must keep both advise flags false, which is what keeps the
    # bar widget in its quiet state.
    assert re.search(
        r"readonly property bool updateAdvised:\s*"
        r"available && count > Config\.options\.updates\.adviseUpdateThreshold",
        source,
    )
    assert re.search(
        r"readonly property bool updateStronglyAdvised:\s*"
        r"available && count > Config\.options\.updates\.stronglyAdviseUpdateThreshold",
        source,
    )


def test_periodic_check_is_config_gated():
    source = UPDATES.read_text()
    assert re.search(
        r"running:\s*Config\.ready && Config\.options\.updates\.enableCheck", source
    ), "periodic Timer / availability probe must stay behind the enableCheck option"


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
