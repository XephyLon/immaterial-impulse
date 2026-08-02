#!/usr/bin/env python3
"""Settings controls must not write to the config just because they were built.

Every ranged settings control (`ConfigSpinBox`, `ConfigSlider`) used to hang its
write-back off `onValueChanged`. That signal fires for changes the user never
made: QQC2 bounds `SpinBox.value` to `[from, to]` when the component completes,
and `Slider` does the same, so a config value outside the control's declared
range was clamped and written straight back the moment a settings page was
instantiated. `Config.qml` declares no ranges at all - `osd.timeout` is a plain
`int` and the shell honours whatever is in it - so `osd.timeout: 4321` silently
became 3000 on the first look at the Sidebars & Panels page. The same signal
also fired for `Slider`'s smoothing animation, writing every intermediate frame.

There are two halves here because neither is sufficient alone:

- `ConfigControlWriteBackRuntimeTest.qml` builds the real page against a real
  `Config` holding a real out-of-range value and reads the file back. It is the
  only thing that can prove the bug is gone rather than merely relocated.
- The source contract stops the pattern coming back at a call site the runtime
  test does not open. There are 69 of these controls across 16 files; the
  runtime test exercises one.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "ConfigControlWriteBackRuntimeTest.qml"
SOCKET = "wayland-imi-config-control-write-back"

RANGED_CONTROLS = ("ConfigSpinBox", "ConfigSlider")
# Where the controls are declared, as opposed to used.
WIDGET_DIR = ROOT / "modules/common/widgets"


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return shutil.which("qs") is not None and shutil.which("weston") is not None


def _qml_sources():
    for path in ROOT.rglob("*.qml"):
        if "/tests/" in str(path):
            continue
        yield path


def _control_blocks(text, typename):
    """Yield (line_number, body) for each `typename { ... }` block in `text`."""
    lines = text.split("\n")
    opener = re.compile(r"\b%s\s*\{" % typename)
    for index, line in enumerate(lines):
        if not opener.search(line):
            continue
        depth = 0
        started = False
        body = []
        cursor = index
        while cursor < len(lines):
            depth += lines[cursor].count("{") - lines[cursor].count("}")
            body.append(lines[cursor])
            if "{" in lines[cursor]:
                started = True
            if started and depth <= 0:
                break
            cursor += 1
        yield index + 1, "\n".join(body)


class ConfigControlWriteBackSourceTest(unittest.TestCase):
    def test_no_ranged_control_writes_from_on_value_changed(self):
        offenders = []
        for path in _qml_sources():
            text = path.read_text(encoding="utf-8")
            for control in RANGED_CONTROLS:
                if control + " {" not in text:
                    continue
                for line, body in _control_blocks(text, control):
                    if "onValueChanged" in body:
                        offenders.append(
                            f"{path.relative_to(ROOT)}:{line} ({control})")
        self.assertEqual(
            offenders, [],
            "these controls write back from onValueChanged, which fires when "
            "the control is merely built; use onValueModified:\n  "
            + "\n  ".join(offenders))

    def test_ranged_controls_expose_a_user_only_signal(self):
        for name in RANGED_CONTROLS:
            source = (WIDGET_DIR / f"{name}.qml").read_text(encoding="utf-8")
            with self.subTest(control=name):
                self.assertRegex(
                    source, r"signal\s+valueModified\s*\(",
                    f"{name}.qml must declare the user-only valueModified signal")

    def test_spin_box_text_field_reports_only_real_edits(self):
        source = (WIDGET_DIR / "StyledSpinBox.qml").read_text(encoding="utf-8")
        # onTextChanged also fires when the `text: root.value` binding
        # refreshes, which made the field write its own value back out. Match
        # the handler, not the word - the comment explaining this names it.
        self.assertNotRegex(source, r"(?m)^\s*onTextChanged\s*:")
        self.assertRegex(source, r"(?m)^\s*onTextEdited\s*:")

    def test_ranged_controls_never_narrow_the_stored_value(self):
        for name in RANGED_CONTROLS:
            source = (WIDGET_DIR / f"{name}.qml").read_text(encoding="utf-8")
            with self.subTest(control=name):
                self.assertIn("Math.min(root.from, root.value)", source)
                self.assertIn("Math.max(root.to, root.value)", source)

    def test_spin_box_decrement_button_is_not_covered_by_the_text_field(self):
        # The style sizes padding for a skin with both indicators on one side;
        # this one puts decrement at the left end, so without explicit padding
        # the editable field lands on top of it and eats its clicks.
        source = (WIDGET_DIR / "StyledSpinBox.qml").read_text(encoding="utf-8")
        self.assertIn("leftPadding: root.down.indicator", source)
        self.assertIn("rightPadding: root.up.indicator", source)


@unittest.skipUnless(_runtime_available(), "needs qs and weston on PATH")
class ConfigControlWriteBackRuntimeTest(unittest.TestCase):
    # Deliberately outside the OSD timeout control's declared 100..3000, and
    # not a multiple of its 100 step either.
    STORED_TIMEOUT = 4321
    STEP = 100

    @classmethod
    def setUpClass(cls):
        cls.env = dict(os.environ)
        cls.env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        cls.env["WAYLAND_DISPLAY"] = SOCKET
        cls.env.pop("DISPLAY", None)
        cls.weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=1000", "--height=800"],
            env=cls.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        socket_path = Path(cls.env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        if not socket_path.exists():
            _stop(cls.weston)
            raise AssertionError("headless weston never came up")

        # This box's headless EGL has no driver, so force software rendering.
        cls.env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        cls.env["QT_QUICK_BACKEND"] = "software"

    @classmethod
    def tearDownClass(cls):
        _stop(cls.weston)

    def test_opening_a_settings_page_does_not_rewrite_the_config(self):
        home = Path(tempfile.mkdtemp(prefix="imi-config-control-write-back-"))
        self.addCleanup(shutil.rmtree, home, ignore_errors=True)
        config_file = home / "config" / "immaterial-impulse" / "config.json"
        config_file.parent.mkdir(parents=True)
        config_file.write_text(json.dumps({"osd": {"timeout": self.STORED_TIMEOUT}}))

        env = dict(self.env)
        env["XDG_CONFIG_HOME"] = str(home / "config")
        env["XDG_STATE_HOME"] = str(home / "state")

        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn("[ConfigControlWriteBack] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # The harness asserts against the in-memory Config; this asserts
        # against the file, which is what the user actually loses. The single
        # deliberate click is the only thing that may have moved it.
        written = json.loads(config_file.read_text())
        self.assertEqual(written["osd"]["timeout"],
                         self.STORED_TIMEOUT - self.STEP)

        # Widening a control's range to admit a stored value must not put the
        # inner control's bounds in a loop with its own value.
        self.assertNotIn("Binding loop", output,
                         f"the control tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
