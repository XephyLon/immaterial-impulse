"""ResourceUsage's polling stays cheap, and never wakes a sleeping dGPU.

perf(resources): poll through files, and stop waking a sleeping dGPU
moved every per-tick reading the kernel exposes as a file onto FileViews
and gated the one remaining nvidia-smi spawn on the dGPU's
power/runtime_status. These are wiring facts a QML unit test cannot see
(the timers and Process objects never run under qmltestrunner), so the
source shape is pinned here:

- the nvidia-smi Process is only ever started under the
  nvidiaShouldPoll() gate, because on a hybrid laptop an ungated poll is
  what holds the dGPU out of runtime suspend for the whole session;
- the `sensors` subprocess fallback only runs while the probe found no
  hwmon CPU temperature file;
- df does not ride the fast updateInterval tick - disk usage moves on
  the scale of minutes and df was the last per-tick subprocess.
"""

import re
from pathlib import Path

SERVICE = Path(__file__).resolve().parent.parent / "services" / "ResourceUsage.qml"


def _handler_bodies(source, signal_name):
    """Every `<signal_name>: {...}` block body in the file, by brace count."""
    bodies = []
    for match in re.finditer(rf"{signal_name}\s*:\s*{{", source):
        depth = 0
        start = source.index("{", match.start())
        for i in range(start, len(source)):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    bodies.append(source[start:i + 1])
                    break
    return bodies


def _fast_tick_body(source):
    """The onTriggered body of the timer clocked on updateInterval."""
    bodies = [b for b in _handler_bodies(source, "onTriggered")
              if "updateInterval" in b or "gpuVendor" in b]
    assert bodies, "no updateInterval tick found in ResourceUsage.qml"
    return "\n".join(bodies)


def _checks(source):
    tick = _fast_tick_body(source)

    # nvidia-smi may only be started under the runtime-status gate.
    gpu_starts = [m.start() for m in re.finditer(r"gpuProc\.running\s*=\s*true", source)]
    assert gpu_starts, "nvidia-smi is never started - the GPU reading is gone"
    for pos in gpu_starts:
        window = source[max(0, pos - 400):pos]
        assert "nvidiaShouldPoll(" in window, (
            "gpuProc started outside the nvidiaShouldPoll() gate - this is "
            "the spawn that wakes a runtime-suspended dGPU every tick")

    # The sensors fallback only runs while no hwmon temp file was resolved.
    temp_starts = [m.start() for m in re.finditer(r"tempProc\.running\s*=\s*true", source)]
    assert temp_starts, "the sensors fallback is gone entirely"
    for pos in temp_starts:
        window = source[max(0, pos - 400):pos]
        assert re.search(r'cpuTempPath\s*[!=]==?\s*""', window), (
            "the sensors subprocess runs unconditionally - the hwmon "
            "FileView read is supposed to be the primary source")

    # df stays off the fast tick.
    assert "diskProc" not in tick, (
        "diskProc is triggered from the updateInterval tick - df is a "
        "subprocess per tick again")
    assert "diskProc.running = true" in source, "the df poll is gone entirely"

    # The per-tick GPU sysfs reads go through FileViews, not a bash walk.
    assert "fileGpuBusy.reload()" in tick, (
        "the amd/intel branch stopped reading its sysfs files per tick")


def test_resource_usage_polling_contract():
    _checks(SERVICE.read_text())


def test_the_checks_can_fail():
    source = SERVICE.read_text()

    # Planted: an ungated nvidia-smi start.
    planted = source.replace(
        "if (root.nvidiaShouldPoll(fileNvidiaPm.text())) {",
        "if (true) { // planted")
    # Removing the gate call must trip the window check.
    try:
        _checks(planted)
    except AssertionError:
        pass
    else:
        raise AssertionError("an ungated gpuProc start passed the contract")

    # Planted: df back on the fast tick.
    planted = source.replace(
        'if (root.gpuVendor === "nvidia") {',
        'diskProc.running = true\n            if (root.gpuVendor === "nvidia") {')
    try:
        _checks(planted)
    except AssertionError:
        pass
    else:
        raise AssertionError("df on the fast tick passed the contract")


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
