#!/usr/bin/env python3
"""The assistant's read-tier tools, and the fence around the file ones.

`read_file`/`list_directory` go through scripts/ai/ai_fs_tool.py, which
decides on the REAL path whether the model may look: inside an allowed folder,
never a dotfile, never a binary, never more than the byte cap. The QML side
must declare every new tool for all four dialects and dispatch each one.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/ai/ai_fs_tool.py"
REGISTRY = ROOT / "services/AiToolRegistry.qml"
AI = ROOT / "services/Ai.qml"
CONFIG = ROOT / "modules/common/Config.qml"
SERVICES_PAGE = ROOT / "modules/imi/settings/pages/ServicesConfig.qml"

READ_TIER = ["read_file", "list_directory", "get_clipboard", "get_wallpaper", "list_todos", "list_events"]


def run(*argv, env_folders=None):
    env = {"PATH": os.environ["PATH"]}
    if env_folders is not None:
        env["IMI_AI_FOLDERS"] = env_folders
    out = subprocess.run([sys.executable, str(SCRIPT), *argv], env=env, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


class FileToolFence(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.allowed = Path(self.tmp.name) / "notes"
        self.outside = Path(self.tmp.name) / "secrets"
        (self.allowed / "sub").mkdir(parents=True)
        self.outside.mkdir()
        (self.allowed / "a.md").write_text("hello\n")
        (self.allowed / "sub/b.txt").write_text("deep\n")
        (self.allowed / ".env").write_text("TOKEN=x\n")
        (self.allowed / ".git").mkdir()
        (self.allowed / ".git/config").write_text("[core]\n")
        (self.allowed / "blob.bin").write_bytes(b"\x89PNG\x00\x00binary")
        (self.outside / "key.txt").write_text("private\n")
        os.symlink(self.outside / "key.txt", self.allowed / "link-out.txt")
        os.symlink(self.outside, self.allowed / "dir-out")

    def test_reads_inside_the_allowlist(self):
        r = run("read", str(self.allowed / "a.md"), "--allow", str(self.allowed))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["content"], "hello\n")
        self.assertFalse(r["truncated"])

    def test_the_allowlist_can_come_from_the_environment(self):
        r = run("read", str(self.allowed / "sub/b.txt"), env_folders=str(self.allowed))
        self.assertTrue(r["ok"], r)

    def test_an_empty_allowlist_reads_nothing_and_says_where_to_fix_it(self):
        r = run("read", str(self.allowed / "a.md"))
        self.assertFalse(r["ok"])
        self.assertIn("Settings", r["error"])

    def test_outside_and_traversal_are_refused(self):
        for p in (self.outside / "key.txt", self.allowed / ".." / "secrets" / "key.txt"):
            r = run("read", str(p), "--allow", str(self.allowed))
            self.assertFalse(r["ok"], p)
            self.assertIn("outside", r["error"])

    def test_a_symlink_out_of_the_allowlist_is_refused(self):
        r = run("read", str(self.allowed / "link-out.txt"), "--allow", str(self.allowed))
        self.assertFalse(r["ok"])
        r = run("list", str(self.allowed / "dir-out"), "--allow", str(self.allowed))
        self.assertFalse(r["ok"])

    def test_dotfiles_are_invisible_even_inside(self):
        for p in (".env", ".git/config"):
            r = run("read", str(self.allowed / p), "--allow", str(self.allowed))
            self.assertFalse(r["ok"], p)
            self.assertIn("Hidden", r["error"])
        listing = run("list", str(self.allowed), "--allow", str(self.allowed), "--depth", "3")
        names = [e["path"] for e in listing["entries"]]
        self.assertNotIn(".env", names)
        self.assertFalse(any(n.startswith(".git") for n in names))

    def test_binary_is_refused_and_size_is_capped(self):
        r = run("read", str(self.allowed / "blob.bin"), "--allow", str(self.allowed))
        self.assertFalse(r["ok"])
        self.assertIn("binary", r["error"])
        big = self.allowed / "big.txt"
        big.write_text("x" * 5000)
        r = run("read", str(big), "--allow", str(self.allowed), "--max-bytes", "100")
        self.assertTrue(r["ok"])
        self.assertTrue(r["truncated"])
        self.assertEqual(len(r["content"]), 100)
        self.assertEqual(r["size"], 5000)

    def test_list_walks_to_the_depth_asked_and_no_further(self):
        shallow = run("list", str(self.allowed), "--allow", str(self.allowed))
        self.assertEqual([e["path"] for e in shallow["entries"] if e["type"] == "dir"], ["dir-out", "sub"])
        self.assertNotIn("sub/b.txt", [e["path"] for e in shallow["entries"]])
        deep = run("list", str(self.allowed), "--allow", str(self.allowed), "--depth", "2")
        self.assertIn("sub/b.txt", [e["path"] for e in deep["entries"]])
        # The out-of-root symlinked dir is named but never descended.
        self.assertFalse(any(e["path"].startswith("dir-out/") for e in deep["entries"]))

    def test_a_folder_given_to_read_points_at_list(self):
        r = run("read", str(self.allowed), "--allow", str(self.allowed))
        self.assertFalse(r["ok"])
        self.assertIn("list_directory", r["error"])


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class ReadTierContract(unittest.TestCase):
    def test_every_read_tier_tool_is_declared_for_all_four_dialects(self):
        src = _strip(REGISTRY.read_text())
        for name in READ_TIER:
            m = re.search(r'"name":\s*"%s".*?"dialects":\s*\[([^\]]*)\]' % name, src, re.S)
            self.assertIsNotNone(m, name)
            for dialect in ("gemini", "openai", "mistral", "anthropic"):
                self.assertIn(f'"{dialect}"', m.group(1), f"{name} lacks {dialect}")

    def test_every_read_tier_tool_is_dispatched(self):
        src = _strip(AI.read_text())
        body = src[src.index("function handleFunctionCall"):]
        for name in READ_TIER:
            self.assertIn(f'name === "{name}"', body, name)

    def test_the_file_tools_go_through_the_fenced_script_with_the_configured_folders(self):
        src = _strip(AI.read_text())
        self.assertIn("ai/ai_fs_tool.py", src)
        self.assertIn("Config.options.ai.tools.folders", src)
        self.assertNotRegex(src, r'\["cat",', "no unfenced file read")

    def test_the_clipboard_tool_is_gated(self):
        src = _strip(AI.read_text())
        self.assertIn("Config.options.ai.tools.allowClipboard", src)

    def test_config_declares_the_tools_block_with_safe_defaults(self):
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject tools: JsonObject"):]
        self.assertRegex(block, r"property list<string> folders:\s*\[\]")
        self.assertRegex(block, r"property bool allowClipboard:\s*true")

    def test_settings_exposes_the_folder_allowlist(self):
        page = SERVICES_PAGE.read_text()
        self.assertIn("ai.tools.folders", page)
        self.assertIn("ai.tools.allowClipboard", page)


if __name__ == "__main__":
    unittest.main()
