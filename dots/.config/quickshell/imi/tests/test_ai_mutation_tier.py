#!/usr/bin/env python3
"""The assistant's reviewed tier: nothing changes before the user approves.

The file tool's write/append actions stay inside the fence (allowlist on the
real path, a .bak kept once, a size cap, symlinks out refused); every reviewed
tool is declared for all four dialects, classified in the policy, and reaches
the approval card through the guard at the top of handleFunctionCall rather
than a direct branch; the card renders the mutation fence.
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
POLICY = ROOT / "services/ai/ai_tool_policy.js"
AI = ROOT / "services/Ai.qml"
CARD = ROOT / "modules/imi/sidebarLeft/aiChat/MessageCodeBlock.qml"

REVIEWED = ["write_file", "append_file", "set_clipboard", "set_wallpaper", "set_accent",
            "set_palette_source", "set_color_scheme", "add_todo"]


def run(*argv, stdin="", allow=None):
    env = {"PATH": os.environ["PATH"]}
    cmd = [sys.executable, str(SCRIPT), *argv]
    for a in allow or []:
        cmd += ["--allow", str(a)]
    out = subprocess.run(cmd, env=env, input=stdin, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


class WriteFence(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.allowed = Path(self.tmp.name) / "notes"
        self.outside = Path(self.tmp.name) / "secrets"
        self.allowed.mkdir()
        self.outside.mkdir()
        (self.allowed / "a.md").write_text("first\n")
        os.symlink(self.outside / "k.txt", self.allowed / "link-out.txt")

    def test_write_keeps_one_backup_then_overwrites(self):
        r = run("write", str(self.allowed / "a.md"), stdin="second\n", allow=[self.allowed])
        self.assertTrue(r["ok"], r)
        self.assertEqual((self.allowed / "a.md").read_text(), "second\n")
        self.assertEqual(Path(r["backup"]).read_text(), "first\n")
        run("write", str(self.allowed / "a.md"), stdin="third\n", allow=[self.allowed])
        self.assertEqual((self.allowed / "a.md").read_text(), "third\n")
        self.assertEqual((self.allowed / "a.md.bak").read_text(), "first\n", "the .bak is the pre-session contents, not the last write")

    def test_write_creates_a_new_file_and_append_appends(self):
        r = run("write", str(self.allowed / "sub/new.txt"), stdin="hello\n", allow=[self.allowed])
        self.assertTrue(r["ok"], r)
        self.assertFalse(r["existed"])
        self.assertIsNone(r["backup"])
        r = run("append", str(self.allowed / "sub/new.txt"), stdin="more\n", allow=[self.allowed])
        self.assertTrue(r["appended"])
        self.assertEqual((self.allowed / "sub/new.txt").read_text(), "hello\nmore\n")

    def test_outside_and_symlink_out_are_refused(self):
        for p in (self.outside / "k.txt", self.allowed / "link-out.txt", self.allowed / ".." / "secrets" / "x"):
            r = run("write", str(p), stdin="x", allow=[self.allowed])
            self.assertFalse(r["ok"], p)
        self.assertFalse((self.outside / "k.txt").exists())
        r = run("write", str(self.allowed / "a.md"), stdin="x")
        self.assertFalse(r["ok"], "no allowlist, no write")

    def test_size_cap_and_dotfiles(self):
        r = run("write", str(self.allowed / "big.txt"), stdin="x" * (257 * 1024), allow=[self.allowed])
        self.assertFalse(r["ok"])
        self.assertIn("KiB", r["error"])
        r = run("write", str(self.allowed / ".env"), stdin="TOKEN=1", allow=[self.allowed])
        self.assertFalse(r["ok"])


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class ReviewedTierContract(unittest.TestCase):
    def test_every_reviewed_tool_is_declared_for_all_dialects_and_classified(self):
        reg = _strip(REGISTRY.read_text())
        pol = POLICY.read_text()
        reviewed_list = pol[pol.index("reviewed: ["):pol.index("]", pol.index("reviewed: ["))]
        for name in REVIEWED:
            m = re.search(r'"name":\s*"%s".*?"dialects":\s*\[([^\]]*)\]' % name, reg, re.S)
            self.assertIsNotNone(m, name)
            for d in ("gemini", "openai", "mistral", "anthropic"):
                self.assertIn(f'"{d}"', m.group(1), f"{name} lacks {d}")
            self.assertIn(f'"{name}"', reviewed_list, f"{name} is not in the reviewed tier")
        self.assertIn('"set_shell_config"', reviewed_list, "set_shell_config moved behind the card")

    def test_reviewed_tools_reach_the_card_not_a_direct_branch(self):
        ai = _strip(AI.read_text())
        body = ai[ai.index("function handleFunctionCall"):ai.index("function chatToJson")]
        self.assertIn('ToolPolicy.tierOf(name) === "reviewed"', body)
        self.assertIn("message.functionPending = true", body)
        for name in REVIEWED:
            self.assertNotIn(f'name === "{name}"', body, f"{name} must not run from the dispatch chain")
        apply = ai[ai.index("function applyMutation"):ai.index("Process {", ai.index("function applyMutation"))]
        for name in REVIEWED:
            self.assertIn(f'case "{name}"', apply, f"{name} has no approved-path handler")
        self.assertIn("if (message.functionCall?.name && message.functionCall.name !== \"run_shell_command\")", ai)

    def test_the_card_renders_the_mutation_fence(self):
        card = _strip(CARD.read_text())
        self.assertIn('isMutationRequest: segmentLang === "mutation"', card)
        self.assertIn("(root.isCommandRequest || root.isMutationRequest) && root.messageData.functionPending", card)

    def test_file_writes_send_content_on_stdin_not_argv(self):
        ai = _strip(AI.read_text())
        self.assertIn("fsWriteProc.write(String(args.content", ai)
        self.assertNotRegex(ai, r'"write",\s*String\(args\.path[^\]]*args\.content', "content must not be an argv element")


if __name__ == "__main__":
    unittest.main()
