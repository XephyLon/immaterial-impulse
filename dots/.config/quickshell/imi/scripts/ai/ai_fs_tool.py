#!/usr/bin/env python3
"""The assistant's file tools: `read_file` and `list_directory`, fenced.

The model names a path; this decides whether the shell may look at it. The
rules live here rather than in QML so they are testable without a shell:

- Only paths inside an allowed folder (`--allow DIR`, repeatable, or the
  IMI_AI_FOLDERS environment variable, colon-separated). Empty allowlist
  means nothing is readable, and the error says where to change that.
- Containment is decided on the REAL path (symlinks resolved), so a link
  inside an allowed folder cannot point outside it.
- Dotfiles and dot-directories are invisible at every depth, even inside an
  allowed folder: they are where credentials live.
- `read` refuses binaries (a NUL in the first 8 KiB) and caps the bytes it
  returns; `list` caps its depth and entry count.

Output is one JSON object on stdout, exit 0 either way - the shell reads the
`ok` field, and a stack trace is never the model's answer.
"""
import json
import os
import sys

MAX_READ_BYTES = 64 * 1024
MAX_DEPTH = 3
MAX_ENTRIES = 500


def allowed_roots(args):
    roots = []
    for raw in list(args.allow) + os.environ.get("IMI_AI_FOLDERS", "").split(":"):
        raw = raw.strip()
        if not raw:
            continue
        real = os.path.realpath(os.path.expanduser(raw))
        if os.path.isdir(real):
            roots.append(real)
    return roots


def hidden_component(path, root):
    rel = os.path.relpath(path, root)
    return any(part.startswith(".") for part in rel.split(os.sep) if part not in ("", "."))


def resolve(raw_path, roots):
    """Return (real_path, root) or raise ValueError with the model-facing reason."""
    if not roots:
        raise ValueError("No folders are allowed. Add folders under Settings > Services > AI > "
                         "Folders the assistant may read.")
    if not raw_path:
        raise ValueError("A path is required.")
    real = os.path.realpath(os.path.expanduser(raw_path))
    for root in roots:
        if real == root or real.startswith(root + os.sep):
            if hidden_component(real, root):
                raise ValueError("Hidden files and folders are not readable.")
            return real, root
    raise ValueError("That path is outside the folders the assistant may read: "
                     + ", ".join(roots))


def do_read(args, roots):
    real, _root = resolve(args.path, roots)
    if os.path.isdir(real):
        raise ValueError("That is a folder; use list_directory.")
    if not os.path.isfile(real):
        raise ValueError("No such file.")
    size = os.path.getsize(real)
    with open(real, "rb") as f:
        head = f.read(8192)
        if b"\x00" in head:
            raise ValueError("That looks like a binary file; only text is readable.")
        rest = f.read(max(0, args.max_bytes - len(head)))
    data = (head + rest)[: args.max_bytes]
    return {
        "ok": True,
        "path": real,
        "size": size,
        "truncated": size > args.max_bytes,
        "content": data.decode("utf-8", errors="replace"),
    }


def do_list(args, roots):
    real, root = resolve(args.path, roots)
    if not os.path.isdir(real):
        raise ValueError("That is not a folder.")
    depth = max(1, min(MAX_DEPTH, args.depth))
    entries = []
    truncated = False

    def walk(directory, level):
        nonlocal truncated
        try:
            names = sorted(os.listdir(directory))
        except OSError:
            return
        for name in names:
            if name.startswith("."):
                continue
            full = os.path.join(directory, name)
            if len(entries) >= MAX_ENTRIES:
                truncated = True
                return
            is_dir = os.path.isdir(full)
            # A symlink that leaves the root is listed by name but never
            # followed - the read call would refuse it anyway.
            inside = os.path.realpath(full).startswith(root)
            entry = {"path": os.path.relpath(full, real), "type": "dir" if is_dir else "file"}
            if not is_dir:
                try:
                    entry["size"] = os.path.getsize(full)
                except OSError:
                    entry["size"] = None
            entries.append(entry)
            if is_dir and inside and level < depth:
                walk(full, level + 1)

    walk(real, 1)
    return {"ok": True, "path": real, "entries": entries, "truncated": truncated}


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=["read", "list"])
    parser.add_argument("path")
    parser.add_argument("--allow", action="append", default=[], help="an allowed folder (repeatable)")
    parser.add_argument("--depth", type=int, default=1)
    parser.add_argument("--max-bytes", type=int, default=MAX_READ_BYTES)
    args = parser.parse_args(argv)
    roots = allowed_roots(args)
    try:
        result = do_read(args, roots) if args.action == "read" else do_list(args, roots)
    except ValueError as e:
        result = {"ok": False, "error": str(e)}
    except OSError as e:
        result = {"ok": False, "error": f"Could not access that path: {e.strerror or e}"}
    sys.stdout.write(json.dumps(result) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
