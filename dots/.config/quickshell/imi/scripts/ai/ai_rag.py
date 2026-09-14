#!/usr/bin/env python3
"""Local retrieval for the assistant: index folders the user named, search them.

    ai_rag.py index  --folder DIR [--folder DIR...] [--embedder lexical|ollama:MODEL]
    ai_rag.py query  "text" [--k 6] [--embedder ...]
    ai_rag.py forget DIR
    ai_rag.py status

One SQLite file (``--db``, default ``$XDG_STATE_HOME/quickshell/user/rag/index.sqlite``)
holds files, chunks and one vector per chunk per embedding model. Everything
here is local; the only network an embedder may touch is the local Ollama
daemon (``ollama:<model>`` -> ``/api/embed``), and the default ``lexical``
embedder is a hashed bag of words that needs nothing at all.

The privacy contract (docs/proposals/ai-local-rag.md) lives in this file so
it is testable without a shell: nothing outside the given folders; dotfiles
and dot-directories never; the shell's own config, keys and caches never even
when inside a folder; ``.noindex`` marks a subtree out; binaries and files
over the size cap skipped; removing a folder deletes its rows at once.

Output is JSON on stdout. ``index`` streams ``{"progress": n, "total": m}``
lines and ends with ``{"ok": true, ...}``; every other command prints one
object. Exit code 0 either way - a stack trace is never the model's answer.
"""
import fnmatch
import hashlib
import json
import math
import os
import re
import sqlite3
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request

MAX_FILE_BYTES = 2 * 1024 * 1024
MAX_FILES_PER_FOLDER = 5000
CHUNK_LINES = 40
CHUNK_OVERLAP = 8
CHUNK_MAX_CHARS = 2400
LEXICAL_DIM = 512
TEXT_SUFFIXES = {".md", ".markdown", ".txt", ".rst", ".org", ".adoc", ".tex", ".csv", ".tsv", ".json", ".yaml",
                 ".yml", ".toml", ".ini", ".cfg", ".conf", ".xml", ".html", ".htm", ".py", ".js", ".ts", ".qml",
                 ".sh", ".bash", ".zsh", ".fish", ".lua", ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".java",
                 ".kt", ".swift", ".rb", ".php", ".css", ".scss", ".sql", ".nix", ".pdf"}
# Never indexed, even inside an allowed folder: where credentials and the
# shell's own state live.
FORBIDDEN_DIRS = (".ssh", ".gnupg", ".config/immaterial-impulse", ".config/quickshell", ".local/share/keyrings",
                  ".aws", ".kube", ".docker", ".mozilla", ".password-store")


# ----------------------------------------------------------------------------
# storage
def default_db():
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "quickshell", "user", "rag", "index.sqlite")


def open_db(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS files (
            path TEXT PRIMARY KEY, folder TEXT NOT NULL, mtime REAL NOT NULL, size INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY, path TEXT NOT NULL, start INTEGER NOT NULL, end INTEGER NOT NULL,
            text TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS chunks_path ON chunks(path);
        CREATE TABLE IF NOT EXISTS vectors (
            chunk_id INTEGER NOT NULL, model TEXT NOT NULL, dim INTEGER NOT NULL, blob BLOB NOT NULL,
            PRIMARY KEY (chunk_id, model));
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    """)
    return db


def pack(vec):
    return struct.pack(f"{len(vec)}f", *vec)


def unpack(blob, dim):
    return struct.unpack(f"{dim}f", blob)


# ----------------------------------------------------------------------------
# embedders
TOKEN = re.compile(r"[A-Za-z0-9_]{2,}")


def lexical_embed(texts):
    """A hashed bag of words: deterministic, offline, adequate for keyword
    retrieval, and what the tests run on."""
    out = []
    for text in texts:
        vec = [0.0] * LEXICAL_DIM
        for tok in TOKEN.findall(text.lower()):
            h = int(hashlib.blake2b(tok.encode(), digest_size=8).hexdigest(), 16)
            vec[h % LEXICAL_DIM] += 1.0
            # A second slot per token halves collision damage.
            vec[(h >> 20) % LEXICAL_DIM] += 0.5
        norm = math.sqrt(sum(v * v for v in vec)) or 1.0
        out.append([v / norm for v in vec])
    return out


def ollama_base():
    override = os.environ.get("IMI_OLLAMA_URL")
    if override:
        return override.rstrip("/")
    host = os.environ.get("OLLAMA_HOST") or "http://127.0.0.1:11434"
    if "://" not in host:
        host = "http://" + host
    return host.replace("0.0.0.0", "127.0.0.1").rstrip("/")


def ollama_embed(model, texts):
    out = []
    for i in range(0, len(texts), 16):
        batch = texts[i:i + 16]
        req = urllib.request.Request(ollama_base() + "/api/embed", method="POST",
                                     data=json.dumps({"model": model, "input": batch}).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = json.loads(resp.read())
        vecs = payload.get("embeddings") or []
        if len(vecs) != len(batch):
            raise RuntimeError(f"embedder returned {len(vecs)} vectors for {len(batch)} texts")
        for v in vecs:
            norm = math.sqrt(sum(x * x for x in v)) or 1.0
            out.append([x / norm for x in v])
    return out


def validate_embedder(spec):
    if spec == "lexical" or (spec.startswith("ollama:") and len(spec) > len("ollama:")):
        return spec
    raise ValueError(f"unknown embedder {spec!r}: use lexical or ollama:<model>")


def embed(spec, texts):
    validate_embedder(spec)
    if not texts:
        return []
    if spec == "lexical":
        return lexical_embed(texts)
    if spec.startswith("ollama:"):
        return ollama_embed(spec[len("ollama:"):], texts)
    raise ValueError(f"unknown embedder {spec!r}")


# ----------------------------------------------------------------------------
# walking
def forbidden(real):
    home = os.path.realpath(os.path.expanduser("~"))
    for d in FORBIDDEN_DIRS:
        f = os.path.join(home, d)
        if real == f or real.startswith(f + os.sep):
            return True
    return False


def load_ignores(directory):
    """Very small .gitignore reader: bare names and globs, no negation."""
    pats = []
    for name in (".gitignore", ".ignore"):
        try:
            with open(os.path.join(directory, name), encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or line.startswith("!"):
                        continue
                    pats.append(line.rstrip("/"))
        except OSError:
            pass
    return pats


def ignored(name, pats):
    return any(fnmatch.fnmatch(name, p) or fnmatch.fnmatch(name, p.lstrip("/")) for p in pats)


def walk(folder):
    """Yield (path, mtime, size) for indexable files under folder."""
    root = os.path.realpath(os.path.expanduser(folder))
    if not os.path.isdir(root) or forbidden(root):
        return
    count = 0
    stack = [(root, [])]
    while stack:
        directory, inherited = stack.pop()
        if os.path.exists(os.path.join(directory, ".noindex")):
            continue
        pats = inherited + load_ignores(directory)
        try:
            names = sorted(os.listdir(directory))
        except OSError:
            continue
        for name in names:
            if name.startswith("."):
                continue
            full = os.path.join(directory, name)
            real = os.path.realpath(full)
            if not real.startswith(root + os.sep) or forbidden(real) or ignored(name, pats):
                continue
            if os.path.isdir(full):
                stack.append((full, pats))
                continue
            if os.path.splitext(name)[1].lower() not in TEXT_SUFFIXES:
                continue
            try:
                st = os.stat(full)
            except OSError:
                continue
            if st.st_size > MAX_FILE_BYTES:
                continue
            count += 1
            if count > MAX_FILES_PER_FOLDER:
                return
            yield full, st.st_mtime, st.st_size


def read_text(path):
    if path.lower().endswith(".pdf"):
        try:
            out = subprocess.run(["pdftotext", "-layout", path, "-"], capture_output=True, timeout=60)
            return out.stdout.decode("utf-8", errors="replace") if out.returncode == 0 else ""
        except (OSError, subprocess.TimeoutExpired):
            return ""
    with open(path, "rb") as f:
        data = f.read(MAX_FILE_BYTES)
    if b"\x00" in data[:8192]:
        return ""
    return data.decode("utf-8", errors="replace")


def chunk(text):
    """(start_line, end_line, text) windows of CHUNK_LINES with overlap, split
    further when a window is longer than CHUNK_MAX_CHARS."""
    lines = text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        j = min(len(lines), i + CHUNK_LINES)
        piece = "\n".join(lines[i:j]).strip()
        if piece:
            if len(piece) > CHUNK_MAX_CHARS:
                for k in range(0, len(piece), CHUNK_MAX_CHARS):
                    out.append((i + 1, j, piece[k:k + CHUNK_MAX_CHARS]))
            else:
                out.append((i + 1, j, piece))
        if j >= len(lines):
            break
        i = j - CHUNK_OVERLAP
    return out


# ----------------------------------------------------------------------------
# commands
def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def cmd_index(db, folders, embedder):
    folders = [os.path.realpath(os.path.expanduser(f)) for f in folders]
    seen = set()
    todo = []
    known = {row[0]: (row[1], row[2]) for row in db.execute("SELECT path, mtime, size FROM files")}
    for folder in folders:
        for path, mtime, size in walk(folder):
            seen.add(path)
            old = known.get(path)
            if old and abs(old[0] - mtime) < 1e-6 and old[1] == size:
                # Unchanged, but maybe never embedded with THIS model.
                missing = db.execute(
                    "SELECT COUNT(*) FROM chunks c LEFT JOIN vectors v ON v.chunk_id = c.id AND v.model = ? "
                    "WHERE c.path = ? AND v.chunk_id IS NULL", (embedder, path)).fetchone()[0]
                if missing == 0:
                    continue
            todo.append((path, folder, mtime, size))
    # Files gone from disk, or no longer under any given folder, drop out.
    for path in list(known):
        if path not in seen and any(path.startswith(f + os.sep) for f in folders):
            forget_path(db, path)
    total = len(todo)
    emit({"progress": 0, "total": total})
    done = 0
    failed = 0
    for path, folder, mtime, size in todo:
        try:
            text = read_text(path)
            pieces = chunk(text) if text else []
            db.execute("DELETE FROM vectors WHERE chunk_id IN (SELECT id FROM chunks WHERE path = ?)", (path,))
            db.execute("DELETE FROM chunks WHERE path = ?", (path,))
            # A binary, empty or unreadable file is recorded (so an unchanged
            # one is not re-read next time) but has no chunks, and status()
            # counts documents by their chunks, not by this table.
            ids = []
            for start, end, piece in pieces:
                cur = db.execute("INSERT INTO chunks(path, start, end, text) VALUES (?, ?, ?, ?)",
                                 (path, start, end, piece))
                ids.append(cur.lastrowid)
            vecs = embed(embedder, [p[2] for p in pieces])
            for cid, vec in zip(ids, vecs):
                db.execute("INSERT OR REPLACE INTO vectors(chunk_id, model, dim, blob) VALUES (?, ?, ?, ?)",
                           (cid, embedder, len(vec), pack(vec)))
            db.execute("INSERT OR REPLACE INTO files(path, folder, mtime, size) VALUES (?, ?, ?, ?)",
                       (path, folder, mtime, size))
            db.commit()
        except (OSError, RuntimeError, urllib.error.URLError, ValueError) as e:
            failed += 1
            db.rollback()
            emit({"warning": f"{path}: {e}"})
        done += 1
        emit({"progress": done, "total": total})
    db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('last_indexed', ?)", (str(time.time()),))
    db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('embedder', ?)", (embedder,))
    db.commit()
    return status(db) | {"ok": True, "indexed": done - failed, "failed": failed}


def forget_path(db, path):
    db.execute("DELETE FROM vectors WHERE chunk_id IN (SELECT id FROM chunks WHERE path = ?)", (path,))
    db.execute("DELETE FROM chunks WHERE path = ?", (path,))
    db.execute("DELETE FROM files WHERE path = ?", (path,))


def cmd_forget(db, folder):
    folder = os.path.realpath(os.path.expanduser(folder))
    paths = [r[0] for r in db.execute("SELECT path FROM files WHERE path = ? OR path LIKE ?",
                                      (folder, folder + os.sep + "%"))]
    for p in paths:
        forget_path(db, p)
    db.commit()
    return {"ok": True, "forgotten": len(paths)}


def cmd_query(db, text, k, embedder):
    q = embed(embedder, [text])[0]
    rows = db.execute("SELECT c.id, c.path, c.start, c.end, c.text, v.dim, v.blob FROM vectors v "
                      "JOIN chunks c ON c.id = v.chunk_id WHERE v.model = ?", (embedder,)).fetchall()
    scored = []
    for cid, path, start, end, body, dim, blob in rows:
        vec = unpack(blob, dim)
        if len(vec) != len(q):
            continue
        score = sum(a * b for a, b in zip(q, vec))
        if score > 0:
            scored.append((score, path, start, end, body))
    scored.sort(key=lambda r: -r[0])
    results = [{"path": p, "start": s, "end": e, "score": round(sc, 4), "text": b}
               for sc, p, s, e, b in scored[:k]]
    return {"ok": True, "results": results, "searched": len(rows), "embedder": embedder}


def status(db):
    files = db.execute("SELECT COUNT(DISTINCT path) FROM chunks").fetchone()[0]
    chunks = db.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    meta = dict(db.execute("SELECT key, value FROM meta").fetchall())
    return {"files": files, "chunks": chunks, "last_indexed": float(meta.get("last_indexed", 0) or 0),
            "embedder": meta.get("embedder", "")}


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=["index", "query", "forget", "status"])
    parser.add_argument("arg", nargs="?", default="")
    parser.add_argument("--folder", action="append", default=[])
    parser.add_argument("--embedder", default="lexical")
    parser.add_argument("--k", type=int, default=6)
    parser.add_argument("--db", default=os.environ.get("IMI_RAG_DB") or default_db())
    args = parser.parse_args(argv)
    try:
        db = open_db(args.db)
        if args.action in ("index", "query"):
            validate_embedder(args.embedder)
        if args.action == "index":
            result = cmd_index(db, args.folder, args.embedder)
        elif args.action == "query":
            result = cmd_query(db, args.arg, max(1, min(20, args.k)), args.embedder)
        elif args.action == "forget":
            result = cmd_forget(db, args.arg)
        else:
            result = status(db) | {"ok": True}
    except (sqlite3.Error, OSError, ValueError, RuntimeError, urllib.error.URLError) as e:
        result = {"ok": False, "error": str(e)}
    emit(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
