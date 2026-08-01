#!/usr/bin/env python3
"""Hermetic tests for the installer's legacy-package migration path.

Targets sdata/subcmd-install/1.deps-router.sh (+ the sdata/lib/migrate-existing.sh
helper it sources):
  - legacy_packages / has_legacy_packages: only ^illogical-impulse-* packages
    are selected, never near-misses (illogical-impulsive-*, illogical-impulses,
    prefix-embedded names, the bare "illogical-impulse").
  - migrate_remove_legacy: on Arch invoked as `sudo pacman -Rn --noconfirm
    <exact legacy set>` (NOT -Rns: shared deps must survive); never invoked
    when detection finds nothing; Fedora uses `dnf remove -y`; Gentoo and
    unknown distros never call sudo and tell the user to remove manually.
  - IMI_PKG_QUERY_CMD: the per-distro override case in 1.deps-router.sh is
    honored (fedora -> rpm), and an env/`VAR=... source` override survives
    sourcing migrate-existing.sh (its declare -g contract).

No real package manager is ever touched: `pacman`, `rpm` and `sudo` are PATH
stubs inside a sandbox tempdir that log their argv and print a controlled
package list. 1.deps-router.sh is meant to be *sourced* mid-install and ends
by sourcing the real dist-*/install-deps.sh, so the tests extract only the
`migrate_remove_legacy` function and the IMI_PKG_QUERY_CMD case block from it
and drive them in a bash harness with the real shared helpers.
"""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
DEPS_SH = ROOT / "sdata/subcmd-install/1.deps-router.sh"
MIGRATE_SH = ROOT / "sdata/lib/migrate-existing.sh"
ENV_SH = ROOT / "sdata/lib/environment-variables.sh"
FUNCS_SH = ROOT / "sdata/lib/functions.sh"

DEPS_TEXT = DEPS_SH.read_text(encoding="utf-8")
MIGRATE_TEXT = MIGRATE_SH.read_text(encoding="utf-8")


def extract(pattern, text, what):
    m = re.search(pattern, text, re.M | re.S)
    assert m, f"could not extract {what} — did the script move?"
    return m.group(0)


# The function that runs the actual removal.
REMOVE_FN = extract(r"^function migrate_remove_legacy\(\)\{.*?^\}",
                    DEPS_TEXT, "migrate_remove_legacy()")
# The per-distro IMI_PKG_QUERY_CMD override (first case block in the file).
QUERY_CASE = extract(r'^case "\$OS_GROUP_ID" in\n.*?^esac',
                     DEPS_TEXT, "IMI_PKG_QUERY_CMD per-distro case")

# A package list full of near-misses; only the two real legacy names may match.
MIXED_PKG_LIST = """\
firefox
illogical-impulse-audio
illogical-impulsive-fake
illogical-impulse
illogical-impulses
not-illogical-impulse-thing
xillogical-impulse-nope
illogical-impulse-hyprland
zzz-tools
"""
LEGACY_SET = ["illogical-impulse-audio", "illogical-impulse-hyprland"]
CLEAN_PKG_LIST = "firefox\nillogical-impulsive-fake\nillogical-impulses\n"

STUB_TEMPLATE = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "${log}"
cat "${pkglist}"
"""
SUDO_STUB = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "${log}"
exit 0
"""


class InstallerLegacyMigrationTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.sandbox = Path(self._tmp.name)
        self.home = self.sandbox / "home"
        self.home.mkdir()
        self.stub = self.sandbox / "stub"
        self.stub.mkdir()
        self.pkglist = self.sandbox / "pkglist.txt"
        self.pacman_log = self.sandbox / "pacman.log"
        self.rpm_log = self.sandbox / "rpm.log"
        self.sudo_log = self.sandbox / "sudo.log"
        self._write_stub("pacman", STUB_TEMPLATE, self.pacman_log)
        self._write_stub("rpm", STUB_TEMPLATE, self.rpm_log)
        self._write_stub("sudo", SUDO_STUB, self.sudo_log)
        # Snippets can source these to get the extracted pieces.
        (self.sandbox / "remove_fn.sh").write_text(REMOVE_FN + "\n")
        (self.sandbox / "query_case.sh").write_text(QUERY_CASE + "\n")

    def tearDown(self):
        self._tmp.cleanup()

    def _write_stub(self, name, template, log):
        p = self.stub / name
        p.write_text(template.replace("${log}", str(log))
                             .replace("${pkglist}", str(self.pkglist)))
        p.chmod(0o755)

    def run_harness(self, snippet, pkg_list=MIXED_PKG_LIST, extra_env=None):
        self.pkglist.write_text(pkg_list)
        env = dict(
            os.environ,
            HOME=str(self.home),
            XDG_CONFIG_HOME=str(self.home / ".config"),
            XDG_DATA_HOME=str(self.home / ".local/share"),
            PATH=f"{self.stub}:{os.environ['PATH']}",
            MIGRATE_SH=str(MIGRATE_SH),
            REMOVE_FN_FILE=str(self.sandbox / "remove_fn.sh"),
            QUERY_CASE_FILE=str(self.sandbox / "query_case.sh"),
        )
        if extra_env:
            env.update(extra_env)
        script = "\n".join([
            "ask=false",
            f'source "{ENV_SH}"',
            f'source "{FUNCS_SH}"',
            snippet,
        ])
        return subprocess.run(["bash", "-c", script], cwd=str(self.sandbox),
                              env=env, capture_output=True, text=True)

    def assert_ok(self, r):
        self.assertEqual(r.returncode, 0,
                         f"harness failed\nstdout:\n{r.stdout}\nstderr:\n{r.stderr}")

    def sudo_calls(self):
        if not self.sudo_log.exists():
            return []
        return self.sudo_log.read_text().splitlines()

    # -------------------------------------------------------------- detection
    def test_legacy_packages_selects_only_true_legacy_names(self):
        r = self.run_harness('source "$MIGRATE_SH"\nlegacy_packages')
        self.assert_ok(r)
        self.assertEqual(r.stdout.split(), LEGACY_SET)
        # The default query went through the stubbed pacman with -Qq only.
        self.assertEqual(set(self.pacman_log.read_text().splitlines()), {"-Qq"})

    def test_has_legacy_packages_false_on_near_misses_only(self):
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'if has_legacy_packages; then echo DETECTED; else echo CLEAN; fi',
            pkg_list=CLEAN_PKG_LIST)
        self.assert_ok(r)
        self.assertEqual(r.stdout.strip().splitlines()[-1], "CLEAN")

    def test_has_legacy_packages_true_when_legacy_present(self):
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'if has_legacy_packages; then echo DETECTED; else echo CLEAN; fi')
        self.assert_ok(r)
        self.assertEqual(r.stdout.strip().splitlines()[-1], "DETECTED")

    def test_missing_query_tool_is_a_safe_noop(self):
        # Documented contract: if the query tool isn't present the eval fails
        # silently and detection just reports false.
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'if has_legacy_packages; then echo DETECTED; else echo CLEAN; fi',
            extra_env={"IMI_PKG_QUERY_CMD":
                       "definitely-not-a-real-command-imi-test -Qq"})
        self.assert_ok(r)
        self.assertEqual(r.stdout.strip().splitlines()[-1], "CLEAN")

    # ---------------------------------------------------------------- removal
    def test_remove_legacy_arch_uses_rn_with_exact_detected_set(self):
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'source "$REMOVE_FN_FILE"\n'
            'OS_GROUP_ID=arch\n'
            'migrate_remove_legacy')
        self.assert_ok(r)
        calls = self.sudo_calls()
        self.assertEqual(
            calls, [f"pacman -Rn --noconfirm {' '.join(LEGACY_SET)}"],
            f"unexpected sudo invocation(s): {calls}")
        # Never the cascading -Rns/-Rs (would orphan-remove shared deps).
        self.assertNotIn("-Rns", calls[0])
        self.assertNotIn("-Rs ", calls[0])
        # pacman itself was only ever used for querying, never for removal.
        for line in self.pacman_log.read_text().splitlines():
            self.assertEqual(line, "-Qq")

    def test_remove_legacy_not_invoked_when_nothing_detected(self):
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'source "$REMOVE_FN_FILE"\n'
            'OS_GROUP_ID=arch\n'
            'migrate_remove_legacy',
            pkg_list=CLEAN_PKG_LIST)
        self.assert_ok(r)
        self.assertEqual(self.sudo_calls(), [],
                         "sudo was invoked although no legacy packages exist")

    def test_remove_legacy_fedora_uses_dnf_remove(self):
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'source "$REMOVE_FN_FILE"\n'
            'OS_GROUP_ID=fedora\n'
            'migrate_remove_legacy')
        self.assert_ok(r)
        self.assertEqual(self.sudo_calls(),
                         [f"dnf remove -y {' '.join(LEGACY_SET)}"])

    def test_remove_legacy_gentoo_never_removes_automatically(self):
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'source "$REMOVE_FN_FILE"\n'
            'OS_GROUP_ID=gentoo\n'
            'migrate_remove_legacy')
        self.assert_ok(r)
        self.assertEqual(self.sudo_calls(), [],
                         "gentoo path must not auto-remove")
        self.assertIn("emerge -C", r.stdout)
        for pkg in LEGACY_SET:
            self.assertIn(pkg, r.stdout)

    def test_remove_legacy_unknown_distro_never_calls_sudo(self):
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'source "$REMOVE_FN_FILE"\n'
            'OS_GROUP_ID=beos\n'
            'migrate_remove_legacy')
        self.assert_ok(r)
        self.assertEqual(self.sudo_calls(), [])
        self.assertIn("manually", r.stdout)

    # -------------------------------------------------------------- overrides
    def test_per_distro_query_override_fedora_uses_rpm(self):
        # Mirrors the real sourcing order in 1.deps-router.sh: migrate helper
        # first, then the per-distro case overrides IMI_PKG_QUERY_CMD.
        r = self.run_harness(
            'source "$MIGRATE_SH"\n'
            'OS_GROUP_ID=fedora\n'
            'source "$QUERY_CASE_FILE"\n'
            'echo "QUERY=$IMI_PKG_QUERY_CMD"\n'
            'legacy_packages')
        self.assert_ok(r)
        self.assertIn("QUERY=rpm -qa --qf '%{NAME}\\n'", r.stdout)
        lines = r.stdout.strip().splitlines()
        self.assertEqual(lines[-2:], LEGACY_SET)
        # rpm stub was queried with the real flags; pacman never touched.
        self.assertEqual(self.rpm_log.read_text().splitlines(),
                         ["-qa --qf %{NAME}\\n"])
        self.assertFalse(self.pacman_log.exists(),
                         "fedora override still queried pacman")

    def test_per_distro_query_override_gentoo_is_declared(self):
        # No qlist stub needed to pin the contract: the case block must map
        # gentoo to portage-utils' qlist.
        self.assertRegex(QUERY_CASE,
                         r'gentoo\)\s*IMI_PKG_QUERY_CMD="qlist -I -C"')

    def test_env_override_survives_prefix_source_scope(self):
        # The `VAR=val source file` form is exactly what migrate-existing.sh's
        # declare -g comment defends against: the override must still be live
        # for calls made after the source statement.
        r = self.run_harness(
            "printf 'illogical-impulse-custom\\nrandom-pkg\\n' > mypkgs.txt\n"
            'IMI_PKG_QUERY_CMD="cat mypkgs.txt" source "$MIGRATE_SH"\n'
            'legacy_packages')
        self.assert_ok(r)
        self.assertEqual(r.stdout.split(), ["illogical-impulse-custom"])
        self.assertFalse(self.pacman_log.exists(),
                         "override ignored: fell back to pacman")
        self.assertFalse(self.rpm_log.exists())

    # ------------------------------------------------------- static guardrails
    def test_default_query_is_injectable_pacman_qq(self):
        self.assertIn(
            'declare -g IMI_PKG_QUERY_CMD="${IMI_PKG_QUERY_CMD:-pacman -Qq}"',
            MIGRATE_TEXT)

    def test_arch_removal_flags_pinned_in_source(self):
        # The exact non-cascading removal invocation, wrapped in the v() echo
        # wrapper so it is shown before running.
        self.assertIn("v sudo pacman -Rn --noconfirm $pkgs", REMOVE_FN)
        code = "\n".join(l.split("#", 1)[0] for l in REMOVE_FN.splitlines())
        self.assertNotIn("-Rns", code, "-Rns crept back into the removal path")


if __name__ == "__main__":
    unittest.main()
