#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "plugin_installer", ROOT / "scripts/plugins/install_plugin.py")
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)


class PluginInstallerPathTests(unittest.TestCase):
    def test_accepts_nested_package_path(self):
        self.assertEqual(
            INSTALLER.safe_relative_path("components/Widget.qml"),
            Path("components/Widget.qml"))

    def test_rejects_parent_escape(self):
        with self.assertRaises(ValueError):
            INSTALLER.safe_relative_path("../Widget.qml")

    def test_rejects_absolute_path(self):
        with self.assertRaises(ValueError):
            INSTALLER.safe_relative_path("/tmp/Widget.qml")

    def test_rejects_url_smuggled_as_package_path(self):
        # The string entry form is joined against baseUrl, so an absolute URL
        # must not also be accepted as a destination path.
        with self.assertRaises(ValueError):
            INSTALLER.safe_relative_path("https://example.org/Widget.qml")

    def test_rejects_hidden_path(self):
        with self.assertRaises(ValueError):
            INSTALLER.safe_relative_path(".ssh/authorized_keys")


class PluginInstallerTransportTests(unittest.TestCase):
    ORIGIN = ("example.org", 443)

    def test_requires_https(self):
        with self.assertRaises(ValueError):
            INSTALLER.https_origin("http://example.org/manifest.json", "manifest URL")

    def test_https_origin_defaults_to_port_443(self):
        self.assertEqual(
            INSTALLER.https_origin("https://Example.org/manifest.json", "manifest URL"),
            self.ORIGIN)

    def test_rejects_cross_origin_file(self):
        with self.assertRaises(ValueError):
            INSTALLER.require_same_origin(
                "https://cdn.example.net/Widget.qml", self.ORIGIN, "package file URL")

    def test_accepts_same_origin_file(self):
        url = "https://example.org/pkg/Widget.qml"
        self.assertEqual(
            INSTALLER.require_same_origin(url, self.ORIGIN, "package file URL"), url)

    def test_download_limits_are_bounded(self):
        self.assertLessEqual(INSTALLER.MAX_FILE_BYTES, INSTALLER.MAX_TOTAL_BYTES)
        self.assertGreater(INSTALLER.MAX_FILE_COUNT, 0)


if __name__ == "__main__":
    unittest.main()
