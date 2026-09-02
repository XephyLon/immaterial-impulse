#!/usr/bin/env python3
"""The install TUI's progress spinner survives the moment nothing can exec.

The install it animates runs `pacman -Syu`, and while pacman replaces glibc
there is a window in which no external program can start. The spinner forked
`sleep` and `date` every tick: each tick printed "cannot execute: required
file not found" on the user's screen and an empty `date` made the elapsed
clock negative ("-29806108m-8s"). The loop keeps time with EPOCHSECONDS and
sleeps with `read -t` on a held fd, tolerates a log read that fails, and
never moves a milestone backwards.

The runtime test runs the extracted loop with an EMPTY PATH against a short
lived child: nothing may reach stderr and the clock may not go negative.
"""

from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
TUI = ROOT / "sdata/subcmd-install/tui.sh"


def function_source(name, text):
    match = re.search(r"^" + re.escape(name) + r"\(\)\{\n.*?^\}", text, re.S | re.M)
    assert match, f"{name}() not found in tui.sh"
    return match.group(0)


class SpinnerStaticTests(unittest.TestCase):
    def setUp(self):
        self.loop = function_source("progress_loop", TUI.read_text(encoding="utf-8"))

    def test_the_loop_forks_nothing_for_time_or_sleep(self):
        code = "\n".join(l for l in self.loop.splitlines() if not l.lstrip().startswith("#"))
        self.assertNotRegex(code, r"\bsleep\b", "sleep is a process; use read -t on the held fd")
        self.assertNotIn("date +%s", code, "date is a process; use EPOCHSECONDS")
        self.assertIn("EPOCHSECONDS", code)
        self.assertRegex(code, r"read -rt 0\.12 -u \"\$sleep_fd\"")

    def test_a_milestone_only_moves_forward_and_a_failed_read_keeps_the_last_line(self):
        self.assertIn("(( next >= target ))", self.loop)
        self.assertIn('log_milestone "$log" 2>/dev/null', self.loop)
        self.assertRegex(self.loop, r'\[\[ -n "\$line" \]\]; then\s*last=\$line')


class SpinnerRuntimeTests(unittest.TestCase):
    def test_the_loop_runs_clean_with_no_external_programs(self):
        text = TUI.read_text(encoding="utf-8")
        funcs = "\n".join(function_source(n, text) for n in ("draw_bar", "log_milestone", "draw_progress", "progress_loop"))
        script = f"""
set -u
C_TEAL= C_DIM= C_BOLD= C_RST=
SPIN=(a b c d e f g h i j)
{funcs}
log=$(mktemp); printf '1. Install dependencies\\nupgrading glibc...\\n' > "$log"
# the child: alive for ~0.5s, via builtins only
bash -c 'read -t 0.5 -u 9 9<> <(:) || true' & pid=$!
PATH=/nonexistent
progress_loop "$pid" "$log"
rm -f "$log"
"""
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr.strip(), "", "a tick reached stderr - something forked and failed")
        self.assertNotRegex(result.stdout, r"-\d+m", "the elapsed clock went negative")
        self.assertGreaterEqual(result.stdout.count("Ctrl-C to cancel"), 2, "the loop should have ticked more than once")


if __name__ == "__main__":
    unittest.main()
