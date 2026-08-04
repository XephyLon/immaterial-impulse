#!/usr/bin/env python3
"""Uninstall step 5 must only remove an SDDM theme we installed.

`sdata/subcmd-uninstall/0.run.sh` hands the machine to the theme's own
uninstaller, which removes the theme directory, the drop-in carrying `Current=`,
the user's `~/.config/<theme>` directory, its fonts, its matugen block and its
`/etc/sudoers.d` rule.

It used to decide that on nothing but a directory existing - *either* name:

    if [[ -d .../imi-sddm-theme || -d .../ii-sddm-theme ]]; then

`ii-sddm-theme` is upstream 3d3f/ii-sddm-theme's install name. Somebody who
installed upstream's theme themselves, years before ImI, then installed ImI
without the SDDM extra (`INSTALL_SDDM=0`, the default), had all of the above
deleted by an ImI uninstall - and losing the theme directory while a `Current=`
in `kde_settings.conf` or `/etc/sddm.conf` still names it is a machine with no
graphical login. Step 4, immediately below, already models the right shape:
prove ownership, don't infer it (issue #100).

So install step 5 now records a marker on a successful hand-off, and uninstall
fires on evidence: the marker, or the current theme name, which only this fork
installs. A bare pre-fork directory is reported, never acted on.

Hermetic: the gate is extracted from 0.run.sh with the themes directory
rewritten into a tempdir, and driven for each combination. Nothing runs the real
uninstaller and nothing looks at /usr/share.
"""
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    if ROOT.parent == ROOT:
        raise AssertionError("could not locate the repo root")
    ROOT = ROOT.parent

UNINSTALL = ROOT / "sdata/subcmd-uninstall/0.run.sh"
INSTALL_5 = ROOT / "sdata/subcmd-install/5.sddm-theme.sh"
UNINSTALL_TEXT = UNINSTALL.read_text(encoding="utf-8")
INSTALL_5_TEXT = INSTALL_5.read_text(encoding="utf-8")

THEMES_DIR = "/usr/share/sddm/themes"
MARKER_REL = "immaterial-impulse/sddm-theme-installed"

# Everything from the marker path down to the end of the ownership decision.
GATE = re.search(r'^_sddm_marker=.*?^fi$', UNINSTALL_TEXT, re.M | re.S)
assert GATE, "could not extract the step-5 ownership gate — did it move?"
GATE_TEXT = GATE.group(0)


class SddmUninstallOwnershipTest(unittest.TestCase):

    def decide(self, *, marker=False, imi_dir=False, legacy_dir=False):
        """Run the gate; return (fires, stdout)."""
        tmp = Path(tempfile.mkdtemp(prefix="imi-sddm-own-"))
        self.addCleanup(__import__("shutil").rmtree, tmp, ignore_errors=True)
        themes, state = tmp / "themes", tmp / "state"
        themes.mkdir()
        (state / "immaterial-impulse").mkdir(parents=True)
        if imi_dir:
            (themes / "imi-sddm-theme").mkdir()
        if legacy_dir:
            (themes / "ii-sddm-theme").mkdir()
        if marker:
            (state / MARKER_REL).write_text("ref=deadbeef\n")

        gate = GATE_TEXT.replace(THEMES_DIR, str(themes))
        script = tmp / "drive.sh"
        script.write_text(textwrap.dedent(f"""\
            #!/usr/bin/env bash
            set -uo pipefail
            XDG_STATE_HOME="{state}"
            STY_YELLOW=""; STY_CYAN=""; STY_RST=""
            {gate}
            printf 'DECISION=%s\\n' "$_sddm_ours"
            """))
        proc = subprocess.run(["bash", str(script)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("DECISION=", proc.stdout)
        fires = proc.stdout.rsplit("DECISION=", 1)[1].strip() == "true"
        return fires, proc.stdout

    # --- the case that cost somebody their login screen ---------------------

    def test_a_foreign_pre_fork_install_is_never_touched(self):
        """Upstream's theme, installed by the user, with no record of ours."""
        fires, out = self.decide(legacy_dir=True)
        self.assertFalse(fires)
        self.assertIn("ii-sddm-theme", out)
        self.assertIn("no record that we installed it", out)

    def test_the_untouched_case_says_what_it_found_and_why_it_stopped(self):
        """Silence would read as "there was no SDDM theme". The hint has to name
        the directory and warn that deleting it while a Current= names it is the
        login-blocking case."""
        _, out = self.decide(legacy_dir=True)
        self.assertIn("Leaving it alone", out)
        self.assertIn("no graphical login", out)

    def test_nothing_installed_at_all_is_silent(self):
        fires, out = self.decide()
        self.assertFalse(fires)
        self.assertEqual(out.strip(), "DECISION=false")

    # --- the cases that are ours --------------------------------------------

    def test_our_own_theme_name_is_enough(self):
        """Installs predating the marker have nothing else, and only this fork
        installs under imi-sddm-theme."""
        fires, _ = self.decide(imi_dir=True)
        self.assertTrue(fires)

    def test_the_marker_authorises_the_pre_fork_name(self):
        """We installed it before the theme renamed itself and its migration has
        not run since - still ours, and the only evidence that says so."""
        fires, _ = self.decide(marker=True, legacy_dir=True)
        self.assertTrue(fires)

    def test_the_marker_alone_does_not_fire(self):
        """A marker with no theme on disk means it is already gone."""
        fires, _ = self.decide(marker=True)
        self.assertFalse(fires)

    def test_a_migrating_install_with_both_names_fires(self):
        fires, _ = self.decide(marker=True, imi_dir=True, legacy_dir=True)
        self.assertTrue(fires)

    # --- the two halves have to agree ---------------------------------------

    def test_install_step_5_writes_the_marker_the_uninstaller_reads(self):
        self.assertIn(MARKER_REL.split("/")[-1], INSTALL_5_TEXT)
        self.assertIn('${XDG_STATE_HOME:-$HOME/.local/state}/immaterial-impulse',
                      INSTALL_5_TEXT)
        self.assertIn('${XDG_STATE_HOME:-$HOME/.local/state}/immaterial-impulse/'
                      + MARKER_REL.split("/")[-1], UNINSTALL_TEXT)

    def test_the_marker_is_only_written_on_a_successful_handoff(self):
        """A declined or failed theme install must not leave a marker claiming
        we installed something."""
        handoff = INSTALL_5_TEXT.split("handing off to the theme installer")[1]
        marker_at = handoff.index("sddm-theme-installed")
        else_at = handoff.index("\nelse\n")
        self.assertLess(marker_at, else_at,
                        "the marker is written outside the success branch")

    def test_the_marker_is_removed_only_when_the_uninstall_succeeded(self):
        """The theme's uninstaller exits non-zero when it removes nothing, so a
        declined uninstall must leave the marker in place."""
        self.assertIn('if bash "$_sddm_un"; then', UNINSTALL_TEXT)
        after = UNINSTALL_TEXT.split('if bash "$_sddm_un"; then')[1]
        self.assertLess(after.index('rm -f "$_sddm_marker"'), after.index("else"))

    def test_the_handoff_is_gated_on_the_decision(self):
        """The gate is worthless if the fetch-and-run below is not inside it."""
        after = UNINSTALL_TEXT.split(GATE_TEXT, 1)[1]
        self.assertIn('if [[ "$_sddm_ours" == true ]]; then',
                      after[:after.index("uninstall.sh")])

    def test_the_themes_directory_is_where_we_think_it_is(self):
        """This literal is what the harness rewrites into the sandbox."""
        self.assertIn(f"{THEMES_DIR}/imi-sddm-theme", GATE_TEXT)
        self.assertIn(f"{THEMES_DIR}/ii-sddm-theme", GATE_TEXT)


if __name__ == "__main__":
    unittest.main()
