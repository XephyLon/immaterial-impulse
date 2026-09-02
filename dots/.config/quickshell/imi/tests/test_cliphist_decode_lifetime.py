#!/usr/bin/env python3
"""A decoded clipboard preview lives while anything shows it.

The launcher drew empty boxes for image entries. The log said why: `Cannot
open: file:///tmp/quickshell/media/cliphist/<id>` eight times, each just before
a `Configuration Loaded` - a hot reload rebuilt the Directories singleton, whose
"cleanup on init" `rm -rf`d the decode dir under the live previews, and a row
rebuilt by the same reload trusted `[ -f ]` on a file a detached rm was about to
take. The same hole one row down: every CliphistImage deleted "its" file on
destruction, while the launcher rebuilds its rows on every keystroke. And the
dir was one path for every shell process, so a nested harness beside the
session wiped the session's previews on start.

Reproduced in a nested Hyprland: a content change to Config.qml took the dir
from 6 files to 0 while the images were on screen.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / "modules/imi/overview/CliphistImage.qml"
SERVICE = ROOT / "services/Cliphist.qml"
DIRS = ROOT / "modules/common/Directories.qml"


class CliphistDecodeLifetimeTests(unittest.TestCase):
    def setUp(self):
        self.image = IMAGE.read_text(encoding="utf-8")
        self.service = SERVICE.read_text(encoding="utf-8")
        self.dirs = DIRS.read_text(encoding="utf-8")

    def test_a_row_holds_its_file_and_never_removes_it(self):
        self.assertIn("Cliphist.acquireDecode(root.imageDecodeFilePath)", self.image)
        self.assertIn("Cliphist.releaseDecode(root.imageDecodeFilePath)", self.image)
        self.assertNotRegex(self.image, r"\brm\s+-r?f\b",
                            "a row that removes the shared file takes it from the row built a frame later")

    def test_the_decode_is_atomic_and_distrusts_an_empty_file(self):
        command = re.search(r'command: \["bash", "-c", `(.*?)`\]', self.image, re.S)
        self.assertIsNotNone(command)
        command = command.group(1)
        self.assertIn("[ -s '${imageDecodeFilePath}' ]", command)
        self.assertIn(".part'", command)
        self.assertRegex(command, r"mv -f '\$\{imageDecodeFilePath\}\.part' '\$\{imageDecodeFilePath\}'")
        self.assertNotIn("[ -f", command)

    def test_the_service_removes_only_what_nothing_holds_and_only_after_a_beat(self):
        self.assertIn("function acquireDecode(path: string)", self.service)
        self.assertIn("function releaseDecode(path: string)", self.service)
        sweep = re.search(r"Timer \{\s*id: decodeSweep(.*?)\n    \}", self.service, re.S)
        self.assertIsNotNone(sweep, "the removal has to sit on a timer, not on the release")
        sweep = sweep.group(1)
        self.assertIn("!(path in root.decodeHolders)", sweep)
        self.assertRegex(sweep, r"interval: \d{4,}")
        # The only rm the service runs is the sweep's.
        self.assertEqual(len(re.findall(r'"rm"', self.service)), 1)

    def test_the_decode_dir_is_per_process_and_the_cleanup_spares_the_living(self):
        self.assertRegex(self.dirs, r"property string cliphistDecode: `\$\{cliphistDecodeRoot\}/\$\{Quickshell\.processId\}`")
        self.assertNotRegex(self.dirs, r"rm -rf '\$\{cliphistDecode\}'",
                            "the singleton's onCompleted re-runs on a reload that rebuilds it - it must not wipe the live dir")
        completed = self.dirs.split("Component.onCompleted: {", 1)[1]
        self.assertIn('[ -d "/proc/$n" ] && continue', completed)
        self.assertIn("[ \"$n\" = '${Quickshell.processId}' ] && continue", completed)


if __name__ == "__main__":
    unittest.main()
