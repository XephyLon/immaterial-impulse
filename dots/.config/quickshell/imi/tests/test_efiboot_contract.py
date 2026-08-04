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


def strip_comments(text):
    """Code only. Prose naming a symbol is not a use of it, and several checks
    below assert a symbol is ABSENT - which a comment explaining its absence
    would otherwise defeat."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


def handler_body(text, proc_id):
    """The onExited body of the Process with `id: <proc_id>`, by brace matching.
    Asserting against the whole file cannot tell 'disarm on failure' from
    'disarm unconditionally' - the strings are identical, only the enclosing
    handler differs."""
    start = text.index(f"id: {proc_id}")
    handler = text.index("onExited:", start)
    brace = text.index("{", handler)
    depth, i = 1, brace + 1
    while depth:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    return text[brace:i]


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
        self.screen = (ROOT / "modules/imi/sessionScreen/SessionScreen.qml").read_text()

    def test_bootnext_set_via_pkexec(self):
        self.assertIn('["pkexec", "efibootmgr", "-n", root.pendingNum]', self.service)

    def test_reboot_is_observable_not_fire_and_forget(self):
        # #104: this called Session.reboot(), which is execDetached - no exit
        # code, so a reboot that never happened could not be detected and the
        # BootNext just armed could not be rolled back. It was an unresolved
        # identifier here as well (Session is declared in
        # qs.modules.common.functions, which this file does not import), so it
        # threw ReferenceError and did nothing whatsoever. Owning the reboot as
        # a Process fixes both.
        self.assertNotIn("Session.reboot()", strip_comments(self.service),
                         "reboot must not be execDetached: rollback needs an exit code")
        self.assertRegex(self.service,
                         r"id:\s*rebootProc\s*\n\s*command:\s*\[[^\]]*reboot[^\]]*\]")

    def test_arming_bootnext_is_followed_by_the_reboot(self):
        # The one edge #104 actually broke. The cases either side of it pin that
        # rebootProc exists and that it behaves correctly once it runs - but
        # nothing pinned that anything *starts* it, which is precisely the state
        # the bug left behind: pkexec returned 0, the success branch threw before
        # reaching the reboot, and BootNext stayed armed. Replacing this
        # assignment with a no-op keeps every other case in this file green.
        body = handler_body(strip_comments(self.service), "setNextProc")
        self.assertIn("rebootProc.running = true", body,
                      "a successful pkexec must start the reboot it just armed BootNext for")

    def test_failed_reboot_clears_bootnext(self):
        # A failed action must not leave the machine armed to boot another OS.
        self.assertIn('["pkexec", "efibootmgr", "-N"]', self.service)
        body = handler_body(strip_comments(self.service), "rebootProc")
        self.assertIn("disarmProc.running = true", body,
                      "a non-zero reboot exit must trigger the disarm")
        self.assertIn("if (exitCode === 0) return", body,
                      "a successful reboot must not disarm the BootNext it just armed")

    def test_disarm_failure_names_the_manual_command(self):
        # Armed, could not reboot, could not disarm. Nothing else on screen
        # would ever hint that the next restart boots a different OS.
        self.assertIn("efibootmgr -N",
                      handler_body(strip_comments(self.service), "disarmProc"))

    def test_reboot_command_matches_the_plain_reboot_button(self):
        # Drift guard. EfiBoot owns its reboot only because it needs the exit
        # code, not because it wants different semantics from Session.reboot().
        session = (ROOT / "modules/common/functions/Session.qml").read_text()
        self.assertIn("reboot || loginctl reboot", self.service)
        self.assertIn("reboot || loginctl reboot", session)

    def test_import_lint_still_covers_session_and_services(self):
        # The lint that should have caught #104 knew only about Appearance and
        # walked only modules/. Narrowing it back reopens the hole silently.
        lint = (ROOT / "tests/lint_qml_imports.sh").read_text()
        self.assertIn("Session:qs.modules.common.functions", lint)
        self.assertRegex(lint, r"SEARCH_DIRS=\([^)]*/services")

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


class SessionTransitionOrderTests(unittest.TestCase):
    """The plain Reboot button does NOT share #104's ReferenceError -
    SessionScreen.qml imports qs.modules.common.functions correctly - but it did
    share the shape: closeAllWindows() ran BEFORE the transition was issued, so a
    transition that never happened had already SIGTERMed every one of the user's
    applications. Empty desktop, still logged in, nothing explaining why."""

    ORDERED = ("reboot", "poweroff", "rebootToFirmware")

    def setUp(self):
        self.session = strip_comments(
            (ROOT / "modules/common/functions/Session.qml").read_text())

    def body(self, name):
        start = self.session.index(f"function {name}(")
        brace = self.session.index("{", start)
        depth, i = 1, brace + 1
        while depth:
            if self.session[i] == "{":
                depth += 1
            elif self.session[i] == "}":
                depth -= 1
            i += 1
        return self.session[brace:i]

    def test_transition_is_issued_before_windows_are_closed(self):
        for name in self.ORDERED:
            with self.subTest(function=name):
                body = self.body(name)
                self.assertIn("closeAllWindows()", body)
                self.assertIn("execDetached", body)
                self.assertLess(
                    body.index("execDetached"), body.index("closeAllWindows()"),
                    f"{name}() must issue the transition before killing the user's windows")

    def test_logout_is_deliberately_left_alone(self):
        # pkill -i Hyprland does not fail the way a polkit-gated transition can,
        # so there is no failure path here that could strand the user. Pinned so
        # a later tidy-up does not "make it consistent" without that argument.
        body = self.body("logout")
        self.assertLess(body.index("closeAllWindows()"), body.index("execDetached"))


if __name__ == "__main__":
    unittest.main()
