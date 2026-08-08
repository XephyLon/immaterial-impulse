#!/usr/bin/env python3
"""Prism Launcher instance enumeration for the launcher search.

scripts/prism/list_instances.py walks a Prism data directory and emits the
JSON the PrismLauncher service turns into search results. Everything here is
pure filesystem parsing, so it is tested against fixture trees rather than the
author's real install - which also pins the cases a real install happens not
to have right now (a renamed instance, a missing icon, a Fabric pack, a
flatpak layout).
"""

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
SCRIPT = ROOT / "dots/.config/quickshell/imi/scripts/prism/list_instances.py"


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def make_instance(instances_dir, folder, *, name=None, icon_key=None,
                  last_launch=None, played=None, components=None):
    """Write a minimal but realistic Prism instance into `instances_dir`."""
    cfg = ["[General]", "ConfigVersion=1.3", "InstanceType=OneSix"]
    if name is not None:
        cfg.append(f"name={name}")
    if icon_key is not None:
        cfg.append(f"iconKey={icon_key}")
    if last_launch is not None:
        cfg.append(f"lastLaunchTime={last_launch}")
    if played is not None:
        cfg.append(f"totalTimePlayed={played}")
    write(instances_dir / folder / "instance.cfg", "\n".join(cfg) + "\n")
    if components is not None:
        write(instances_dir / folder / "mmc-pack.json",
              json.dumps({"components": components, "formatVersion": 1}))


def run(data_dir, *, launcher="prismlauncher"):
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--data-dir", str(data_dir),
         "--launcher", launcher],
        capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


class InstanceEnumerationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.data = self.tmp / "PrismLauncher"
        self.instances = self.data / "instances"
        self.instances.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, self.tmp)

    def test_reads_name_and_launch_id_separately(self):
        # The launch ID is the FOLDER name; `name` is the display name a user
        # can rename freely. Conflating them launches the wrong pack, or
        # nothing at all.
        make_instance(self.instances, "cottage-witch-1", name="Cottage Witch")
        out = run(self.data)
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["id"], "cottage-witch-1")
        self.assertEqual(out[0]["name"], "Cottage Witch")

    def test_folder_name_is_the_fallback_display_name(self):
        make_instance(self.instances, "No Name Here")
        out = run(self.data)
        self.assertEqual(out[0]["name"], "No Name Here")

    def test_directories_without_instance_cfg_are_skipped(self):
        # instgroups.json and stray directories live alongside instances.
        make_instance(self.instances, "real", name="Real")
        (self.instances / "not-an-instance").mkdir()
        write(self.instances / "instgroups.json", '{"groups":{}}')
        out = run(self.data)
        self.assertEqual([i["id"] for i in out], ["real"])

    def test_sorted_by_most_recently_launched(self):
        make_instance(self.instances, "old", name="Old", last_launch=1000)
        make_instance(self.instances, "new", name="New", last_launch=9000)
        make_instance(self.instances, "never", name="Never")
        out = run(self.data)
        # Never-launched sorts last rather than first: a missing timestamp is
        # not a recent one.
        self.assertEqual([i["name"] for i in out], ["New", "Old", "Never"])

    def test_icon_resolves_to_a_real_file_of_any_extension(self):
        make_instance(self.instances, "a", name="A", icon_key="curseforge_x")
        make_instance(self.instances, "b", name="B", icon_key="modrinth_y")
        write(self.data / "icons/curseforge_x.png", "")
        write(self.data / "icons/modrinth_y.webp", "")
        out = {i["name"]: i for i in run(self.data)}
        self.assertTrue(out["A"]["icon"].endswith("/icons/curseforge_x.png"))
        self.assertTrue(out["B"]["icon"].endswith("/icons/modrinth_y.webp"))

    def test_missing_icon_file_yields_empty_icon_not_a_broken_path(self):
        # iconKey often names a Prism built-in ("flame", "default") with no
        # file on disk. Handing the UI a path that does not exist renders a
        # broken-image box; empty lets it fall back to a Material symbol.
        make_instance(self.instances, "a", name="A", icon_key="flame")
        out = run(self.data)
        self.assertEqual(out[0]["icon"], "")

    def test_version_and_loader_come_from_mmc_pack(self):
        make_instance(self.instances, "a", name="A", components=[
            {"uid": "org.lwjgl3", "version": "3.3.1"},
            {"uid": "net.minecraft", "version": "1.19.2"},
            {"uid": "net.minecraftforge", "version": "43.2.0"},
        ])
        out = run(self.data)
        self.assertEqual(out[0]["minecraftVersion"], "1.19.2")
        self.assertEqual(out[0]["loader"], "Forge")

    def test_every_known_loader_is_named(self):
        loaders = {
            "net.fabricmc.fabric-loader": "Fabric",
            "org.quiltmc.quilt-loader": "Quilt",
            "net.neoforged": "NeoForge",
            "com.mumfrey.liteloader": "LiteLoader",
        }
        for uid, expected in loaders.items():
            with self.subTest(uid=uid):
                folder = uid.replace(".", "-")
                make_instance(self.instances, folder, name=folder, components=[
                    {"uid": "net.minecraft", "version": "1.20.1"},
                    {"uid": uid, "version": "1.0"},
                ])
                out = {i["name"]: i for i in run(self.data)}
                self.assertEqual(out[folder]["loader"], expected)

    def test_vanilla_instance_has_no_loader(self):
        make_instance(self.instances, "a", name="A", components=[
            {"uid": "net.minecraft", "version": "1.20.1"},
        ])
        self.assertEqual(run(self.data)[0]["loader"], "")

    def test_unreadable_mmc_pack_does_not_drop_the_instance(self):
        # A half-written or hand-edited pack file must cost that instance its
        # version line, not its presence in the launcher.
        make_instance(self.instances, "a", name="A")
        write(self.instances / "a/mmc-pack.json", "{ not json")
        out = run(self.data)
        self.assertEqual(out[0]["name"], "A")
        self.assertEqual(out[0]["minecraftVersion"], "")

    def test_launch_command_carries_the_instance_id(self):
        make_instance(self.instances, "cottage-witch-1", name="Cottage Witch")
        out = run(self.data)
        self.assertEqual(out[0]["launch"],
                         ["prismlauncher", "--launch", "cottage-witch-1"])

    def test_flatpak_launcher_is_passed_through_verbatim(self):
        # The service decides native vs flatpak; the script must not rewrite
        # whatever it is handed, or a flatpak install launches nothing.
        make_instance(self.instances, "a", name="A")
        out = run(self.data, launcher="flatpak run org.prismlauncher.PrismLauncher")
        self.assertEqual(out[0]["launch"], [
            "flatpak", "run", "org.prismlauncher.PrismLauncher",
            "--launch", "a"])

    def test_missing_data_dir_is_empty_output_not_an_error(self):
        # Feature detection lives in the service, but the script is what runs
        # on a machine where Prism was uninstalled between the two.
        out = run(self.tmp / "does-not-exist")
        self.assertEqual(out, [])

    def test_instance_cfg_without_a_section_header_still_parses(self):
        # Older MultiMC-era configs have no [General] header.
        write(self.instances / "legacy/instance.cfg",
              "name=Legacy Pack\nlastLaunchTime=5\n")
        out = run(self.data)
        self.assertEqual(out[0]["name"], "Legacy Pack")

    def test_values_containing_equals_are_not_truncated(self):
        make_instance(self.instances, "a", name="A=B=C")
        self.assertEqual(run(self.data)[0]["name"], "A=B=C")


if __name__ == "__main__":
    unittest.main()
