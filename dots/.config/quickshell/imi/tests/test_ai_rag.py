#!/usr/bin/env python3
"""scripts/ai/ai_rag.py: the privacy contract, the index, the search.

Driven against a temp tree with the offline lexical embedder, plus a fake
Ollama /api/embed for the daemon path. Nothing outside the named folders;
dotfiles, .noindex subtrees, .gitignore'd names, binaries and oversize files
skipped; a search ranks the passage that shares the words; incremental
re-index touches only changed files; forget deletes a folder's rows at once.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/ai/ai_rag.py"


def run(*argv, env=None):
    e = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"]}
    if env:
        e.update(env)
    out = subprocess.run([sys.executable, str(SCRIPT), *argv], env=e, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    lines = [json.loads(l) for l in out.stdout.splitlines() if l.strip()]
    return lines[-1], lines


class RagIndexAndSearch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.docs = Path(self.tmp.name) / "docs"
        self.other = Path(self.tmp.name) / "other"
        (self.docs / "sub").mkdir(parents=True)
        (self.docs / "private").mkdir()
        (self.docs / "build").mkdir()
        self.other.mkdir()
        (self.docs / "wayland.md").write_text("# Wayland\n\nA compositor draws every window into one framebuffer.\n"
                                              "The layer shell protocol places bars and panels.\n")
        (self.docs / "sub/recipes.txt").write_text("Pancakes: flour, milk, eggs. Whisk and fry.\n")
        (self.docs / ".env").write_text("TOKEN=secret\n")
        (self.docs / "private/.noindex").write_text("")
        (self.docs / "private/diary.md").write_text("very private thoughts about compositors\n")
        (self.docs / ".gitignore").write_text("build/\n*.log\n")
        (self.docs / "build/out.md").write_text("generated compositor notes\n")
        (self.docs / "trace.log").write_text("compositor compositor compositor\n")
        (self.docs / "blob.txt").write_bytes(b"\x00\x01binary compositor")
        (self.docs / "huge.txt").write_text("compositor " * 300000)   # > 2 MB
        (self.other / "outside.md").write_text("compositor outside the allowlist\n")
        self.db = str(Path(self.tmp.name) / "index.sqlite")

    def test_index_respects_the_fence_and_search_finds_the_right_passage(self):
        final, lines = run("index", "--folder", str(self.docs), "--db", self.db)
        self.assertTrue(final["ok"], final)
        self.assertEqual(final["files"], 2, final)
        self.assertTrue(any("progress" in l for l in lines))
        q, _ = run("query", "how does a wayland compositor draw windows", "--db", self.db)
        self.assertTrue(q["ok"])
        self.assertTrue(q["results"], "a match was expected")
        top = q["results"][0]
        self.assertTrue(top["path"].endswith("wayland.md"))
        self.assertIn("framebuffer", top["text"])
        self.assertGreaterEqual(top["start"], 1)
        paths = "\n".join(r["path"] for r in q["results"])
        for never in (".env", "diary.md", "build/out.md", "trace.log", "blob.txt", "huge.txt", "outside.md"):
            self.assertNotIn(never, paths, never)

    def test_incremental_reindex_touches_only_changed_files(self):
        run("index", "--folder", str(self.docs), "--db", self.db)
        final, lines = run("index", "--folder", str(self.docs), "--db", self.db)
        self.assertEqual(lines[0], {"progress": 0, "total": 0}, "nothing changed, nothing re-embedded")
        (self.docs / "sub/recipes.txt").write_text("Pancakes: flour, milk, eggs. Whisk, rest, fry.\n")
        os.utime(self.docs / "sub/recipes.txt", (1, 2))
        final, lines = run("index", "--folder", str(self.docs), "--db", self.db)
        self.assertEqual(lines[0]["total"], 1)
        (self.docs / "sub/recipes.txt").unlink()
        final, _ = run("index", "--folder", str(self.docs), "--db", self.db)
        self.assertEqual(final["files"], 1, "a deleted file drops out of the index")

    def test_forget_deletes_a_folders_rows_at_once(self):
        run("index", "--folder", str(self.docs), "--db", self.db)
        f, _ = run("forget", str(self.docs / "sub"), "--db", self.db)
        self.assertEqual(f["forgotten"], 1)
        st, _ = run("status", "--db", self.db)
        self.assertEqual(st["files"], 1)
        q, _ = run("query", "pancakes flour milk", "--db", self.db)
        self.assertFalse(any("recipes" in r["path"] for r in q["results"]))

    def test_a_forbidden_home_subtree_is_never_indexed_even_when_named(self):
        home = Path(self.tmp.name) / "home"
        (home / ".ssh").mkdir(parents=True)
        (home / ".ssh/notes.md").write_text("key material\n")
        (home / ".config/immaterial-impulse").mkdir(parents=True)
        (home / ".config/immaterial-impulse/config.json").write_text("{}")
        final, _ = run("index", "--folder", str(home / ".ssh"), "--folder", str(home / ".config/immaterial-impulse"),
                       "--db", self.db, env={"HOME": str(home)})
        self.assertEqual(final["files"], 0)

    def test_the_ollama_embedder_uses_the_daemon_and_namespaces_vectors(self):
        calls = []

        class Fake(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_POST(self):
                n = int(self.headers.get("Content-Length", "0"))
                req = json.loads(self.rfile.read(n))
                calls.append(req)
                # A toy embedding: counts of a few words, so "compositor"
                # texts land near a "compositor" query.
                vecs = []
                for t in req["input"]:
                    tl = t.lower()
                    vecs.append([tl.count("compositor"), tl.count("pancake"), 1.0])
                body = json.dumps({"embeddings": vecs}).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.shutdown)
        env = {"IMI_OLLAMA_URL": f"http://127.0.0.1:{srv.server_address[1]}"}
        final, _ = run("index", "--folder", str(self.docs), "--db", self.db, "--embedder", "ollama:toy", env=env)
        self.assertTrue(final["ok"], final)
        self.assertTrue(calls and calls[0]["model"] == "toy")
        q, _ = run("query", "compositor", "--db", self.db, "--embedder", "ollama:toy", "--k", "1", env=env)
        self.assertTrue(q["results"] and q["results"][0]["path"].endswith("wayland.md"))
        # The lexical namespace is empty: a query there finds nothing.
        q2, _ = run("query", "compositor", "--db", self.db, "--embedder", "lexical")
        self.assertEqual(q2["searched"], 0)

    def test_errors_are_json_not_tracebacks(self):
        final, _ = run("index", "--folder", str(self.docs), "--db", self.db, "--embedder", "nope:x")
        self.assertFalse(final["ok"])
        self.assertIn("embedder", final["error"])


if __name__ == "__main__":
    unittest.main()
