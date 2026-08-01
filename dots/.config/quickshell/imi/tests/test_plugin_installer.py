#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import urljoin


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


class PluginInstallerInstallFlowTests(unittest.TestCase):
    """End-to-end install/upgrade runs with the network layer swapped out.

    `download` is the only function that touches the network, so replacing it on
    the loaded module turns `main()` into a pure filesystem exercise: a dict of
    url -> bytes stands in for the manifest's origin.
    """

    MANIFEST_URL = "https://example.org/plugins/demo/manifest.json"

    def setUp(self):
        self.addCleanup(setattr, INSTALLER, "download", INSTALLER.download)
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def serve(self, responses):
        def fake_download(url, limit=INSTALLER.MAX_FILE_BYTES):
            if url not in responses:
                raise AssertionError(f"unexpected download: {url}")
            payload = responses[url]
            if len(payload) > limit:
                raise ValueError(f"response exceeds {limit} bytes: {url}")
            return payload
        INSTALLER.download = fake_download

    def run_install(self, manifest, upgrade=False):
        responses = {self.MANIFEST_URL: json.dumps(manifest).encode()}
        for entry in manifest["package"]["files"]:
            path = entry if isinstance(entry, str) else entry["path"]
            content = f"{manifest.get('version')}:{path}".encode()
            responses[urljoin(self.MANIFEST_URL, path)] = content
        self.serve(responses)
        argv = [self.MANIFEST_URL, str(self.root)]
        if upgrade:
            argv.append("--upgrade")
        with contextlib.redirect_stdout(io.StringIO()):
            return INSTALLER.main(argv)

    @staticmethod
    def manifest(version="1.0.0", files=("Widget.qml",), plugin_id="demo"):
        return {
            "id": plugin_id,
            "version": version,
            "package": {"files": list(files)},
        }

    def test_fresh_install_writes_package_files(self):
        self.assertEqual(self.run_install(self.manifest()), 0)
        self.assertEqual(
            (self.root / "demo" / "Widget.qml").read_text(), "1.0.0:Widget.qml")

    def test_fresh_install_refuses_existing_directory(self):
        self.run_install(self.manifest())
        with self.assertRaises(FileExistsError):
            self.run_install(self.manifest(version="2.0.0"))

    def test_upgrade_replaces_existing_install(self):
        self.run_install(self.manifest(files=["Widget.qml", "Legacy.qml"]))
        self.assertEqual(
            self.run_install(
                self.manifest(version="2.0.0", files=["Widget.qml", "Fresh.qml"]),
                upgrade=True),
            0)
        target = self.root / "demo"
        self.assertEqual((target / "Widget.qml").read_text(), "2.0.0:Widget.qml")
        self.assertTrue((target / "Fresh.qml").exists())
        # Files only the old version shipped are gone: the upgrade is a swap,
        # not an overlay.
        self.assertFalse((target / "Legacy.qml").exists())
        # No backup directory is left behind on success.
        self.assertEqual(
            [entry.name for entry in self.root.iterdir()], ["demo"])

    def test_upgrade_refuses_mismatched_plugin_id(self):
        target = self.root / "demo"
        target.mkdir()
        (target / "manifest.json").write_text(json.dumps({"id": "other"}))
        (target / "Widget.qml").write_text("keep")
        with self.assertRaises(ValueError):
            self.run_install(self.manifest(version="2.0.0"), upgrade=True)
        self.assertEqual((target / "Widget.qml").read_text(), "keep")

    def test_upgrade_refuses_unparseable_installed_manifest(self):
        target = self.root / "demo"
        target.mkdir()
        (target / "manifest.json").write_text("not json {")
        (target / "Widget.qml").write_text("keep")
        with self.assertRaises(ValueError):
            self.run_install(self.manifest(version="2.0.0"), upgrade=True)
        self.assertEqual((target / "Widget.qml").read_text(), "keep")

    def test_store_sidecar_written_after_install(self):
        self.run_install(self.manifest(version="1.2.3"))
        sidecar = json.loads((self.root / "demo" / ".store.json").read_text())
        self.assertEqual(sidecar["manifestUrl"], self.MANIFEST_URL)
        self.assertEqual(sidecar["installedVersion"], "1.2.3")
        self.assertIn("installedAt", sidecar)

    def test_store_sidecar_records_missing_version_as_null(self):
        manifest = self.manifest()
        del manifest["version"]
        self.run_install(manifest)
        sidecar = json.loads((self.root / "demo" / ".store.json").read_text())
        self.assertIsNone(sidecar["installedVersion"])

    def test_store_sidecar_updated_on_upgrade(self):
        self.run_install(self.manifest(version="1.0.0"))
        self.run_install(self.manifest(version="2.0.0"), upgrade=True)
        sidecar = json.loads((self.root / "demo" / ".store.json").read_text())
        self.assertEqual(sidecar["installedVersion"], "2.0.0")

    def test_package_cannot_declare_the_store_sidecar(self):
        # `.store.json` is the installer's provenance record; a package that
        # tries to ship its own must be rejected by the dot-prefix rule.
        with self.assertRaises(ValueError):
            self.run_install(self.manifest(files=[".store.json"]))
        self.assertFalse((self.root / "demo").exists())


if __name__ == "__main__":
    unittest.main()
