#!/usr/bin/env python3
"""Source-presence / lint contracts for the keyring rebrand migration.

These are string checks against KeyringStorage.qml's source text, NOT
behavioral tests: they can't observe secret-tool being invoked, exit-code
handling, or that a legacy hit actually gets re-keyed. They only pin the
expected shape of the file (attribute names, label text, and the presence of
a fallback helper) so an accidental revert or a blind find-replace rename is
caught. Correctness of the fallback/re-key logic itself must be verified by
reading services/KeyringStorage.qml directly.
"""
import unittest
from pathlib import Path

SRC = (Path(__file__).resolve().parents[1] / "services/KeyringStorage.qml").read_text()


class KeyringMigrationTests(unittest.TestCase):
    def test_new_attribute_is_immaterial_impulse(self):
        self.assertIn('"application": "immaterial-impulse"', SRC)
        self.assertNotIn('"application": "illogical-impulse"', SRC)

    def test_label_rebranded(self):
        self.assertIn("Immaterial Impulse", SRC)

    def test_falls_back_to_old_attribute(self):
        self.assertIn("illogical-impulse", SRC)  # only survives as the fallback id

    def test_legacy_fallback_helper_present(self):
        # Presence only - does NOT verify that a legacy hit is actually
        # re-keyed or that a locked/ambiguous lookup is left untouched.
        self.assertIn("legacyLookup", SRC)


if __name__ == "__main__":
    unittest.main()
