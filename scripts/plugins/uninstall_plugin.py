#!/usr/bin/env python3
"""Remove an installed Quickshell plugin package.

Deletion runs unattended from the shell, so the target is validated the same way
install_plugin.py validates what it writes: the id must match the accepted
shape, and the resolved directory must sit directly inside the install root so a
crafted id or a planted symlink cannot walk the removal out of that tree.
"""

import argparse
import os
import re
import shutil
from pathlib import Path

PLUGIN_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}")


def resolve_target(install_root: Path, plugin_id: str) -> Path:
    """Return the path to remove, or raise if the request is unsafe.

    A symlink at the plugin path is returned as-is: the caller unlinks the link
    itself and never follows it, so a link planted in the install root cannot
    redirect the removal at whatever it points to. A real entry must resolve to
    a directory sitting directly under the install root.
    """
    if not PLUGIN_ID.fullmatch(plugin_id):
        raise ValueError("invalid plugin id")

    target = install_root / plugin_id
    if target.is_symlink():
        return target

    if not target.exists():
        raise FileNotFoundError(f"plugin not installed: {plugin_id}")

    resolved = target.resolve()
    if resolved.parent != install_root.resolve():
        raise ValueError("refusing to remove a path outside the install root")
    if not resolved.is_dir():
        raise ValueError("plugin entry is not a directory")
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("install_root", type=Path)
    parser.add_argument("plugin_id")
    args = parser.parse_args()

    target = resolve_target(args.install_root, args.plugin_id)
    if target.is_symlink():
        target.unlink()
    else:
        shutil.rmtree(target)

    print(args.plugin_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
