#!/usr/bin/env python3
"""Static contracts for the installer's cancel/SIGINT machinery and prompts.

Targets ./setup, sdata/subcmd-install/0.greeting.sh, sdata/subcmd-install/tui.sh
and the shared sdata/lib/functions.sh wrappers. These are cheap textual pins on
behavior that is dangerous to lose silently:

  - tui.sh cancel-button machinery: on_cancel + trap INT TERM + trap cleanup
    EXIT, process-GROUP kills (kill -TERM/-KILL -"$INSTALL_PGID", plus the
    sudo -n variants for root-owned children), job-control isolation via
    `set -m` — and NO setsid (a setsid child loses the controlling tty and
    breaks sudo's tty-bound timestamp; see the comment block in tui.sh).
  - Every command is echoed before it runs: the v() wrapper prints the command
    and defers to x(); x() aborts instead of blocking when stdin is no tty.
  - A non-interactive `./setup install` path exists: --force maps to ask=false,
    the quiet TUI runs `setup install ... --force </dev/null`, and the no-tty
    fallback execs the whiptail front-end.
  - setup's sudo-keepalive is always cleaned up via trap on EXIT INT TERM.
  - 0.greeting.sh honors ask=false (no prompts) and offers a real abort.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
SETUP = (ROOT / "setup").read_text(encoding="utf-8")
GREETING = (ROOT / "sdata/subcmd-install/0.greeting.sh").read_text(encoding="utf-8")
TUI = (ROOT / "sdata/subcmd-install/tui.sh").read_text(encoding="utf-8")
FUNCS = (ROOT / "sdata/lib/functions.sh").read_text(encoding="utf-8")
OPTIONS = (ROOT / "sdata/subcmd-install/options.sh").read_text(encoding="utf-8")


def code_only(text: str) -> str:
    """Drop comments (everything from '#' to EOL) so contracts about *code*
    aren't satisfied — or violated — by prose. Crude but sufficient here:
    none of these scripts embed '#' in string literals that matter."""
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


class TuiCancelMachineryTests(unittest.TestCase):
    def test_on_cancel_handler_and_traps_present(self):
        self.assertIn("on_cancel(){", TUI)
        self.assertIn("trap on_cancel INT TERM", TUI)
        self.assertIn("trap - INT TERM", TUI)          # reset after the wait
        self.assertIn("trap cleanup EXIT", TUI)
        self.assertIn("CANCELLED_INSTALL=1", TUI)
        self.assertIn("INSTALL_RET=130", TUI)          # cancel maps to 130

    def test_cancel_kills_the_whole_process_group(self):
        # The dash before $INSTALL_PGID is the process-group kill — losing it
        # would orphan the make/ninja/cc tree of a running WE build.
        self.assertIn('kill -TERM -"$INSTALL_PGID"', TUI)
        self.assertIn('kill -KILL -"$INSTALL_PGID"', TUI)
        # Root-owned children (in-flight pacman) need the sudo -n variants.
        self.assertIn('sudo -n kill -TERM -"$INSTALL_PGID"', TUI)
        self.assertIn('sudo -n kill -KILL -"$INSTALL_PGID"', TUI)
        # cleanup on EXIT also reaps a still-running group.
        self.assertRegex(TUI,
            r'\[\[ -n "\$INSTALL_PGID" \]\] && kill -TERM -"\$INSTALL_PGID"')

    def test_group_isolation_uses_job_control_not_setsid(self):
        code = code_only(TUI)
        self.assertIn("set -m", code)
        self.assertIn('INSTALL_PGID="$pid"', TUI)
        # setsid must never come back: it detaches the child from the
        # controlling tty and breaks sudo's tty-scoped credential. (It is
        # allowed to appear in comments explaining exactly this.)
        self.assertNotIn("setsid", code,
                         "setsid reintroduced into tui.sh code")

    def test_quiet_install_is_noninteractive_and_backgrounded(self):
        # --force (ask=false) + </dev/null (x() aborts rather than prompts),
        # backgrounded so it becomes its own process-group leader under set -m.
        self.assertRegex(
            TUI,
            r'"\$SETUP_BIN" install "\$\{INSTALL_FLAGS\[@\]\}" --force '
            r'</dev/null >"\$log" 2>&1 &')

    def test_toggle_cursor_restore_binds_the_load_event(self):
        # The toggle menu re-invokes fzf per toggle and restores the cursor
        # with pos($pos). That bind must hang off `load`, not `start`: with
        # piped input, `start` fires before the reader has delivered any
        # items, so pos() acts on an empty list and silently no-ops — the
        # cursor snaps back to the top on most toggles, timing-dependent
        # (measured on fzf 0.74.2: start:pos(3) lands on row 1, load:pos(3)
        # on row 3). This regressed once already; keep it pinned.
        self.assertIn('--bind "load:pos($pos)"', TUI)
        self.assertNotIn('--bind "start:pos', TUI)

    def test_esc_and_decline_paths_cancel_cleanly(self):
        self.assertIn("cancelled(){", TUI)
        # Both toggle menus and the fontset picker bail out through cancelled().
        self.assertGreaterEqual(len(re.findall(r"\|\| cancelled\b", TUI)), 2)
        # The final confirm defaults to NOT installing.
        self.assertRegex(TUI, r"\*\)\s*cancelled\s*;;")
        # No-tty entry never reaches fzf: exec the whiptail fallback.
        self.assertRegex(TUI, r"\[\[ ! -t 1 \]\]")
        self.assertIn('exec bash "$WHIPTAIL_TUI"', TUI)


class SetupEntrypointTests(unittest.TestCase):
    def test_sudo_keepalive_always_cleaned_up(self):
        # Every sudo_init_keepalive must be paired with the cleanup trap.
        inits = SETUP.count("sudo_init_keepalive")
        traps = SETUP.count("trap sudo_stop_keepalive EXIT INT TERM")
        self.assertGreater(inits, 0)
        self.assertEqual(inits, traps,
                         "sudo keepalive started without an EXIT/INT/TERM trap")

    def test_greeting_is_skippable_for_noninteractive_runs(self):
        self.assertRegex(
            SETUP,
            r'if \[\[ "\$\{SKIP_ALLGREETING\}" != true \]\]; then\s*\n'
            r'\s*source \$\{SUBCMD_DIR\}/0\.greeting\.sh')

    def test_force_flag_disables_all_prompts(self):
        # `./setup install --force` is the documented non-interactive path.
        self.assertRegex(OPTIONS, r"-f\|--force\)\s*ask=false")
        self.assertIn("--skip-allgreeting) SKIP_ALLGREETING=true", OPTIONS)

    def test_bare_setup_launches_the_tui(self):
        self.assertRegex(
            SETUP, r'""\)bash "\$\{REPO_ROOT\}/sdata/subcmd-install/tui\.sh"')


class EchoWrapperContractTests(unittest.TestCase):
    def test_v_echoes_the_command_before_running_it(self):
        v_body = re.search(r"^function v\(\)\{\n(.*?)^\}", FUNCS, re.M | re.S)
        self.assertIsNotNone(v_body)
        body = v_body.group(1)
        echo_pos = body.find('echo -e "${STY_GREEN}$*${STY_RST}"')
        run_pos = body.find('x "$@"')
        self.assertGreaterEqual(echo_pos, 0, "v() no longer echoes the command")
        self.assertGreaterEqual(run_pos, 0, "v() no longer defers to x()")
        self.assertLess(echo_pos, run_pos, "v() must echo BEFORE executing")
        # ask=false skips the confirm loop but never the echo.
        self.assertIn("if $ask;then", body)

    def test_x_aborts_instead_of_blocking_without_a_tty(self):
        x_body = re.search(r"^function x\(\)\{\n(.*?)^\}", FUNCS, re.M | re.S)
        self.assertIsNotNone(x_body)
        body = x_body.group(1)
        self.assertIn("if [ ! -t 0 ]; then", body)
        self.assertIn("cmdstatus=1; break", body)

    def test_pause_is_a_noop_when_ask_false(self):
        pause_body = re.search(r"^function pause\(\)\{\n(.*?)^\}",
                               FUNCS, re.M | re.S)
        self.assertIsNotNone(pause_body)
        self.assertIn('if [ ! "$ask" == "false" ];then', pause_body.group(1))

    def test_destructive_file_steps_go_through_v(self):
        files_sh = (ROOT / "sdata/subcmd-install/3.files.sh").read_text(
            encoding="utf-8")
        # The overwrite/backup/install helpers all announce via v().
        self.assertIn("v rsync_dir__sync", files_sh)
        self.assertIn("v mv $t $t.old", files_sh)
        self.assertIn("v cp_file $s $t", files_sh)


class GreetingPromptTests(unittest.TestCase):
    def test_ask_false_skips_the_confirm_prompt(self):
        self.assertRegex(GREETING, r"case \$ask in\s*\n\s*false\) true ;;")

    def test_interactive_prompt_offers_abort_and_autopilot(self):
        self.assertRegex(GREETING, r"a\) exit 1")
        self.assertRegex(GREETING, r"n\) ask=false")
        # Prompts flow through pause(), which ask=false neutralizes.
        self.assertGreaterEqual(GREETING.count("pause"), 3)


if __name__ == "__main__":
    unittest.main()
