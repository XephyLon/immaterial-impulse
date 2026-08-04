#!/usr/bin/env python3
"""The uninstaller must not delete the login shell out from under the user.

`fish` is a `depends` of immaterial-impulse-fonts-themes, so the `yay -Rns` loop
in sdata/dist-arch/uninstall-deps.sh removes it with the meta package. If it is
also the user's login shell, the next login fails *after* a correct password:
SDDM's /usr/share/sddm/scripts/wayland-session has a `*/fish)` branch that runs
`exec $SHELL --login -c ...`, and with fish gone that exec fails and the script
falls through to `exit 1`. The session dies as it starts and the greeter returns,
which reads as a rejected password rather than a missing program.

These tests run the real shell functions against stub `pacman`/`getent`/`chsh`
binaries rather than grepping the source, because every interesting case here is
a decision the code makes at runtime — in particular the two where it must do
*nothing*, since imi never set anyone's login shell and a package the user owns
is not ours to work around.
"""
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
SCRIPT = ROOT / "sdata/dist-arch/uninstall-deps.sh"
SOURCE = SCRIPT.read_text(encoding="utf-8")


def run_uninstall_deps(*, login_shell, install_reason="Installed as a dependency for another package",
                       required_by="immaterial-impulse-fonts-themes", fish_installed=True,
                       fallback="/bin/bash", other_users=()):
    """Source uninstall-deps.sh with the world stubbed out; return the call log.

    Nothing here touches the real system: pacman, getent, chsh, sudo and yay are
    all fakes on PATH, and the log records what the script *tried* to do.
    """
    tmp = Path(tempfile.mkdtemp(prefix="imi-uninstall-shell-"))
    binv, log = tmp / "bin", tmp / "calls.log"
    binv.mkdir()

    passwd = [f"tester:x:1000:1000::/home/tester:{login_shell}"]
    passwd += [f"{n}:x:{1001 + i}:1001::/home/{n}:{s}" for i, (n, s) in enumerate(other_users)]
    # root must never be picked up by the "other users" warning (uid < 1000)
    passwd.insert(0, "root:x:0:0::/root:/bin/bash")

    def stub(name, body):
        p = binv / name
        p.write_text("#!/usr/bin/env bash\n" + textwrap.dedent(body))
        p.chmod(0o755)

    stub("getent", f"""
        [[ "$1" == passwd ]] || exit 2
        printf '%s\\n' {' '.join(repr(x).replace("'", '"') for x in passwd)} > /tmp/.imi-passwd-$$
        if [[ -n "$2" ]]; then grep "^$2:" /tmp/.imi-passwd-$$; else cat /tmp/.imi-passwd-$$; fi
        rc=$?; rm -f /tmp/.imi-passwd-$$; exit $rc
    """)
    stub("pacman", f"""
        if [[ "$1" == -Qi && "$2" == fish ]]; then
          [[ "{fish_installed}" == "True" ]] || exit 1
          echo "Name            : fish"
          echo "Install Reason  : {install_reason}"
          echo "Required By     : {required_by}"
          exit 0
        fi
        exit 1
    """)
    stub("whoami", "echo tester")
    stub("chsh", f'echo "chsh $*" >> "{log}"')
    stub("sudo", '"$@"')
    stub("yay", f'echo "yay $*" >> "{log}"')

    harness = tmp / "harness.sh"
    harness.write_text(textwrap.dedent(f"""
        #!/usr/bin/env bash
        STY_RED=; STY_YELLOW=; STY_CYAN=; STY_RST=; STY_GREEN=; STY_BLUE=
        ask=false
        FALLBACK_LOGIN_SHELL={fallback}
        showfun(){{ :; }}
        v(){{ "$@"; }}
        x(){{ "$@"; }}
        cd "{ROOT}"
        source "{SCRIPT}"
    """))
    harness.chmod(0o755)

    env = dict(os.environ, PATH=f"{binv}:{os.environ['PATH']}")
    proc = subprocess.run(["bash", str(harness)], env=env, capture_output=True, text=True, timeout=60)
    calls = log.read_text(encoding="utf-8") if log.exists() else ""
    shutil.rmtree(tmp, ignore_errors=True)
    return calls, proc.stdout + proc.stderr


class LoginShellRescueTests(unittest.TestCase):
    def test_fish_login_shell_is_moved_to_the_fallback_before_removal(self):
        calls, _ = run_uninstall_deps(login_shell="/usr/bin/fish")
        self.assertIn("chsh -s /bin/bash tester", calls,
                      "a login shell about to be uninstalled must be moved first")
        self.assertLess(calls.index("chsh"), calls.index("yay"),
                        "the shell must change BEFORE the packages are removed, "
                        "or the user is already locked out when it runs")

    def test_a_shell_we_are_not_removing_is_left_alone(self):
        for shell in ("/bin/bash", "/usr/bin/zsh", "/bin/sh"):
            with self.subTest(shell=shell):
                calls, _ = run_uninstall_deps(login_shell=shell)
                self.assertNotIn("chsh", calls,
                                 f"{shell} survives the uninstall; changing it is gratuitous")

    def test_an_explicitly_installed_fish_is_not_touched(self):
        """`pacman -Rs` keeps explicitly-installed packages, so fish stays and
        the user's chosen shell must stay with it."""
        calls, _ = run_uninstall_deps(login_shell="/usr/bin/fish",
                                      install_reason="Explicitly installed")
        self.assertNotIn("chsh", calls)

    def test_fish_kept_alive_by_a_foreign_package_is_not_touched(self):
        calls, _ = run_uninstall_deps(login_shell="/usr/bin/fish",
                                      required_by="immaterial-impulse-fonts-themes  some-other-pkg")
        self.assertNotIn("chsh", calls)

    def test_fish_not_installed_at_all_is_a_no_op(self):
        calls, _ = run_uninstall_deps(login_shell="/usr/bin/fish", fish_installed=False)
        self.assertNotIn("chsh", calls)

    def test_a_missing_fallback_shell_warns_instead_of_setting_it(self):
        """Pointing a login shell at something that does not exist would cause
        exactly the lockout this code prevents."""
        calls, out = run_uninstall_deps(login_shell="/usr/bin/fish",
                                        fallback="/nonexistent/shell")
        self.assertNotIn("chsh", calls)
        self.assertIn("does not exist", out)

    def test_other_accounts_on_the_doomed_shell_are_reported(self):
        _, out = run_uninstall_deps(login_shell="/usr/bin/fish",
                                    other_users=(("someone", "/usr/bin/fish"),))
        self.assertIn("someone", out)
        self.assertIn("chsh -s /bin/bash someone", out,
                      "tell the admin the exact command; we do not edit other accounts")

    def test_root_is_never_reported_as_an_affected_account(self):
        _, out = run_uninstall_deps(login_shell="/usr/bin/fish")
        self.assertNotIn("user \"root\"", out)

    def test_the_removal_loop_still_runs(self):
        """Guards the harness: if the stubs broke sourcing, every assertion
        about *not* calling chsh above would pass vacuously."""
        calls, _ = run_uninstall_deps(login_shell="/bin/bash")
        self.assertIn("yay -Rns immaterial-impulse-fonts-themes", calls)
        self.assertIn("yay -Rns immaterial-impulse-quickshell-git", calls)


class SourceContractTests(unittest.TestCase):
    def test_rescue_runs_before_the_removal_loop_in_source_order(self):
        # Compare against the *code*, not the prose: the comment block above the
        # rescue mentions `yay -Rns` too, and matching that would pass no matter
        # where the rescue actually sits.
        code = "\n".join(line for line in SOURCE.splitlines()
                         if not line.lstrip().startswith("#"))
        self.assertLess(code.index("v rescue_login_shell"), code.index("yay -Rns"),
                        "source order matters: the rescue is useless after the removal")

    def test_fish_is_still_the_shell_this_guards(self):
        """If fonts-themes ever stops depending on fish, or starts depending on
        another shell, this guard needs revisiting rather than silently aging."""
        pkgbuild = (ROOT / "sdata/dist-arch/immaterial-impulse-fonts-themes/PKGBUILD").read_text()
        self.assertRegex(pkgbuild, r"(?m)^\s*fish\s*$",
                         "fonts-themes no longer depends on fish — update the rescue in "
                         "uninstall-deps.sh (and this test) to match what it does depend on")


if __name__ == "__main__":
    unittest.main()
