#!/usr/bin/env python3
"""The Wallpaper Engine wrapper must not leak library paths to launched apps.

The wrapper installed at /usr/local/bin/quickshell used to `export
LD_LIBRARY_PATH` with the linux-wallpaperengine lib dirs on it. That variable
is inherited by every process the shell spawns, and those dirs ship CEF's own
libEGL.so / libGLESv2.so - so any app launched from the launcher resolved those
instead of the system ones. Firefox died during GPU init ~0.5s in, reporting
StartupCrash with nothing useful in the log, and only when launched from the
shell.

The built binary already carries a RUNPATH to its lib dir, so the export buys
nothing. These pin the shape of the fix.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # sdata/
SCRIPT = ROOT / "subcmd-install/4.wallpaperengine.sh"
TUI = ROOT / "subcmd-install/tui-whiptail.sh"


class WallpaperEngineWrapperEnv(unittest.TestCase):
    def setUp(self):
        self.src = SCRIPT.read_text(encoding="utf-8")

    def test_export_is_conditional_not_unconditional(self):
        """No bare `export LD_LIBRARY_PATH=` may sit in the heredoc body."""
        # The fallback assigns it to a shell variable that the heredoc
        # interpolates; a literal export line in the template is the bug.
        heredoc = self.src[self.src.index("<<WRAPPER"):self.src.index("WRAPPER\n  maybe_sudo")]
        self.assertNotRegex(
            heredoc, r"(?m)^export\s+LD_LIBRARY_PATH=",
            "the wrapper template must not unconditionally export LD_LIBRARY_PATH")

    def test_standalone_resolution_is_checked(self):
        for token in ("libs_resolve_standalone", "ensure_standalone_libs",
                      "env -u LD_LIBRARY_PATH ldd"):
            self.assertIn(token, self.src, f"missing standalone-resolution check: {token}")

    def test_falls_back_rather_than_shipping_a_dead_shell(self):
        """If the binary genuinely cannot resolve its libs, still start."""
        self.assertIn("ld_line=", self.src)
        self.assertRegex(self.src, r"patchelf --set-rpath")
        # A missing patchelf must degrade, not abort.
        self.assertIn("patchelf not present", self.src)

    def test_rerunning_the_installer_refreshes_the_wrapper(self):
        """The stamp guards the expensive rebuild, never the wrapper.

        Skipping the wrapper on an up-to-date install meant a wrapper-only fix
        could not reach anyone: the stamp matched, the script exited, and the
        leaky wrapper stayed on disk through an update and a restart.
        """
        tail = self.src[self.src.index("if up_to_date; then"):]
        self.assertIn("install_wrapper", tail,
                      "the up-to-date path must still reinstall the wrapper")
        self.assertLess(tail.index("install_wrapper"), tail.index("exit 0"),
                        "the wrapper must be reinstalled before exiting")

    def test_installed_components_are_preselected(self):
        """The installer doubles as the updater, via Settings > Update Dots.

        An optional component defaulting to OFF means an update silently skips
        it, so a fix living in that step never reaches anyone who does not know
        to re-tick a box they already ticked once.
        """
        tui = TUI.read_text(encoding="utf-8")
        self.assertIn("we-installed-ref", tui,
                      "the checklist must detect an existing WE install")
        self.assertRegex(tui, r'"WE".*\$we_state',
                         "the WE row must use the detected state, not a literal OFF")
        for var in ("we_state", "sddm_state", "plymouth_state"):
            self.assertIn(var, tui)

    def test_reason_is_recorded_for_the_next_reader(self):
        """The wrapper explains itself; this bug cost a long hunt."""
        self.assertIn("libEGL", self.src)
        self.assertRegex(self.src, r"inherited by every")

class WallpaperEngineWrapperEglVendor(unittest.TestCase):
    """The wrapper pins glvnd to the NVIDIA vendor only when NVIDIA is the
    only render device; otherwise Mesa's llvmpipe stack loads into every
    Quickshell process (136 MB on a trivial window) or, on a mixed box, is
    needed for the other GPU."""

    def setUp(self):
        src = SCRIPT.read_text(encoding="utf-8")
        heredoc = src[src.index("<<WRAPPER") + len("<<WRAPPER\n"):src.index("\nWRAPPER\n")]
        gate = heredoc[heredoc.index("# --- egl vendor gate ---"):heredoc.index("# --- end egl vendor gate ---")]
        # The heredoc escapes its own expansions; the wrapper on disk has them unescaped.
        self.gate = gate.replace("\\$", "$")

    def _decide(self, vendors):
        import subprocess, tempfile, os
        from pathlib import Path as P
        with tempfile.TemporaryDirectory() as tmp:
            for i, v in enumerate(vendors):
                d = P(tmp) / f"card{i}" / "device"; d.mkdir(parents=True)
                (d / "vendor").write_text(v + "\n")
            # a connector dir must not count as a GPU
            (P(tmp) / "card0-DP-1").mkdir(exist_ok=True)
            script = self.gate + '\necho "${__EGL_VENDOR_LIBRARY_FILENAMES:-unset}"\n'
            out = subprocess.run(["bash", "-c", script], env={"PATH": os.environ["PATH"], "IMI_DRM_SYSFS": tmp},
                                 capture_output=True, text=True, check=True).stdout.strip()
            return out

    def test_nvidia_only_pins_the_nvidia_vendor(self):
        if not Path("/usr/share/glvnd/egl_vendor.d/10_nvidia.json").is_file():
            self.skipTest("no NVIDIA vendor file on this machine")
        self.assertEqual(self._decide(["0x10de"]), "/usr/share/glvnd/egl_vendor.d/10_nvidia.json")
        self.assertEqual(self._decide(["0x10de", "0x10de"]), "/usr/share/glvnd/egl_vendor.d/10_nvidia.json")

    def test_a_mixed_or_non_nvidia_box_keeps_the_default(self):
        self.assertEqual(self._decide(["0x10de", "0x1002"]), "unset")
        self.assertEqual(self._decide(["0x8086"]), "unset")
        self.assertEqual(self._decide([]), "unset")

    def test_the_export_is_gated_not_unconditional(self):
        self.assertNotRegex(self.gate, r"(?m)^export __EGL_VENDOR_LIBRARY_FILENAMES")
        self.assertIn('[ "$gpus_seen" = 1 ] && [ "$nvidia_only" = 1 ]', self.gate)



if __name__ == "__main__":
    unittest.main()
