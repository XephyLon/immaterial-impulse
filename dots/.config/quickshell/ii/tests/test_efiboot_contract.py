#!/usr/bin/env python3
"""Selective EFI reboot pins: entry parser + privilege/reboot wiring.

parseEntries is pure JS inside services/EfiBoot.qml; it is extracted by brace
matching and executed in node against captured efibootmgr output, so the QML
and the test can never drift apart (same byte-sync idea as the other
extracted-double contracts). Skips parser execution cleanly without node.
"""
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services/EfiBoot.qml"

FIXTURE = """BootCurrent: 0001
Timeout: 1 seconds
BootOrder: 0001,0000,0003,0004,0002,0005,0006,0007
Boot0000* Windows Boot Manager\tHD(1,GPT,e3b229ce)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi
Boot0001* arch\tHD(1,GPT,e3b229ce)/\\EFI\\arch\\grubx64.efi
Boot0002* UEFI OS\tHD(1,GPT,19408110)/\\EFI\\BOOT\\BOOTX64.EFI0000424f
Boot0003* UEFI: Lexar USB Flash Drive, Partition 1\tPciRoot(0x0)/Pci(0x2,0x1)/USB(0,0)/HD(1,MBR,0xae02edad)
Boot0005* UEFI:CD/DVD Drive\tBBS(129,,0x0)
Boot0006  disabled entry\tHD(1,GPT,aa)/x.efi
Boot0007* glued-path entryHD(1,GPT,bb)/y.efi
"""


def extract_function(name):
    text = SERVICE.read_text()
    start = text.index(f"function {name}(")
    brace = text.index("{", start)
    depth, i = 1, brace + 1
    while depth:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    return text[start:i]


class ParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("node") is None:
            raise unittest.SkipTest("node not installed")
        script = extract_function("parseEntries") + f"""
console.log(JSON.stringify(parseEntries({json.dumps(FIXTURE)})))
"""
        out = subprocess.run(["node", "-e", script], capture_output=True, text=True)
        assert out.returncode == 0, out.stderr
        cls.entries = json.loads(out.stdout)

    def test_keeps_real_os_entries_in_boot_order(self):
        self.assertEqual([e["num"] for e in self.entries],
                         ["0001", "0000", "0002", "0007"])
        self.assertEqual(self.entries[1]["label"], "Windows Boot Manager")

    def test_current_entry_flagged(self):
        flags = {e["num"]: e["current"] for e in self.entries}
        self.assertTrue(flags["0001"])
        self.assertFalse(flags["0000"])

    def test_drops_transient_media_and_inactive_entries(self):
        nums = [e["num"] for e in self.entries]
        self.assertNotIn("0003", nums)  # UEFI: USB stick
        self.assertNotIn("0005", nums)  # UEFI: CD/DVD
        self.assertNotIn("0006", nums)  # inactive (no asterisk)

    def test_keeps_uefi_os_but_strips_glued_device_path(self):
        labels = {e["num"]: e["label"] for e in self.entries}
        self.assertEqual(labels["0002"], "UEFI OS")     # colon-less survives
        self.assertEqual(labels["0007"], "glued-path entry")


class WiringTests(unittest.TestCase):
    def setUp(self):
        self.service = SERVICE.read_text()
        self.screen = (ROOT / "modules/ii/sessionScreen/SessionScreen.qml").read_text()

    def test_bootnext_via_pkexec_then_reboot(self):
        self.assertIn('["pkexec", "efibootmgr", "-n", root.pendingNum]', self.service)
        self.assertIn("Session.reboot()", self.service)

    def test_polkit_dismissal_stays_quiet(self):
        self.assertIn("exitCode !== 126 && exitCode !== 127", self.service)

    def test_session_screen_button_gated_on_real_choice(self):
        self.assertIn("visible: EfiBoot.entries.length > 1", self.screen)
        self.assertIn('buttonText: Translation.tr("Reboot into...")', self.screen)
        # Picker resets and entries refresh on every open.
        self.assertIn("if (visible) EfiBoot.refresh()", self.screen)
        # Session screen closes before pkexec so the polkit dialog gets focus.
        self.assertRegex(self.screen,
                         r"sessionRoot\.hide\(\);\s*\n\s*EfiBoot\.rebootInto")


if __name__ == "__main__":
    unittest.main()
