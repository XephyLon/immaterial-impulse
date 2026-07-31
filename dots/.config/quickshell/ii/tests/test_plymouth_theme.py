#!/usr/bin/env python3
"""Plymouth boot-splash pins: theme files + opt-in installer step.

The theme can only be truly verified on a reboot, so these pins hold the
statically checkable contract: theme structure, script-plugin API usage,
and the installer step's safety guards (opt-in gate, mkinitcpio backup,
no automatic kernel-cmdline edits).
"""
import configparser
import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]
THEME = REPO / "sdata/plymouth-theme/immaterial-impulse"
STEP = REPO / "sdata/subcmd-install/6.plymouth.sh"


class ThemeFileTests(unittest.TestCase):
    def test_assets_present(self):
        for name in ("immaterial-impulse.plymouth", "immaterial-impulse.script",
                     "logo.png", "spinner.png", "bullet.png", "entry.png", "lock.png"):
            self.assertTrue((THEME / name).exists(), name)

    def test_plymouth_ini_shape(self):
        cp = configparser.ConfigParser()
        cp.read(THEME / "immaterial-impulse.plymouth")
        self.assertEqual(cp["Plymouth Theme"]["ModuleName"], "script")
        self.assertEqual(cp["script"]["ImageDir"],
                         "/usr/share/plymouth/themes/immaterial-impulse")
        self.assertTrue(cp["script"]["ScriptFile"].endswith("immaterial-impulse.script"))

    def test_script_uses_required_callbacks(self):
        script = (THEME / "immaterial-impulse.script").read_text()
        for pin in ("Plymouth.SetRefreshFunction",
                    "Plymouth.SetDisplayPasswordFunction",
                    "Plymouth.SetDisplayNormalFunction",
                    "Window.SetBackgroundTopColor"):
            self.assertIn(pin, script)
        # Text-free by design: Image.Text depends on the label plugin inside
        # the initramfs, which is exactly the fragile part we avoid.
        self.assertNotIn("Image.Text", script)
        self.assertEqual(script.count("{"), script.count("}"))

    def test_script_references_only_shipped_images(self):
        script = (THEME / "immaterial-impulse.script").read_text()
        for name in re.findall(r'Image\("([^"]+)"\)', script):
            self.assertTrue((THEME / name).exists(), name)


class InstallerStepTests(unittest.TestCase):
    def setUp(self):
        self.step = STEP.read_text()

    def test_bash_syntax(self):
        proc = subprocess.run(["bash", "-n", str(STEP)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_opt_in_gate(self):
        self.assertIn('[[ "${INSTALL_PLYMOUTH:-0}" == "1" ]] ||', self.step)

    def test_mkinitcpio_edit_is_guarded_and_backed_up(self):
        self.assertIn("mkinitcpio.conf.pre-imi-plymouth", self.step)
        # Never re-add the hook when present, and self-restore on failure.
        self.assertIn("plymouth hook already present", self.step)
        self.assertIn("restoring backup", self.step)

    def test_never_edits_kernel_cmdline(self):
        # The cmdline instructions must be printed, not applied.
        self.assertNotRegex(self.step, r"sed[^\n]*GRUB_CMDLINE")
        self.assertIn("GRUB_CMDLINE_LINUX_DEFAULT", self.step)

    def test_rebuilds_initramfs_via_set_default_theme(self):
        self.assertIn("plymouth-set-default-theme -R immaterial-impulse", self.step)

    def test_wired_into_setup_and_tui(self):
        setup = (REPO / "setup").read_text()
        self.assertIn("6.plymouth.sh", setup)
        tui = (REPO / "sdata/subcmd-install/tui-whiptail.sh").read_text()
        self.assertIn("INSTALL_PLYMOUTH=1", tui)
        self.assertIn('"PLYMOUTH"', tui)


if __name__ == "__main__":
    unittest.main()
