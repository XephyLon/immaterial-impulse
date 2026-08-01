#!/usr/bin/env python3
"""Install generated Matugen colors without replacing unrelated app settings."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path


CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
GENERATED = STATE / "quickshell/user/generated/apps"


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.immaterial-impulse-{os.getpid()}")
    temporary.write_text(content)
    temporary.replace(path)


def replace_ini_section(content: str, section: str, replacement: str) -> str:
    pattern = re.compile(
        rf"(?ms)^\[{re.escape(section)}\][ \t]*\n.*?(?=^\[[^\n]+\][ \t]*$|\Z)"
    )
    replacement = replacement.rstrip() + "\n"
    if pattern.search(content):
        return pattern.sub(replacement, content, count=1)
    return content.rstrip() + "\n\n" + replacement


def apply_cava() -> None:
    generated = GENERATED / "cava.ini"
    if not generated.is_file():
        return
    config = CONFIG / "cava/config"
    current = config.read_text() if config.is_file() else ""
    atomic_write(config, replace_ini_section(current, "color", generated.read_text()))
    subprocess.run(["pkill", "-USR2", "-x", "cava"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def apply_btop() -> None:
    generated = GENERATED / "btop.theme"
    if not generated.is_file():
        return
    theme = CONFIG / "btop/themes/matugen.theme"
    theme.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(generated, theme)

    config = CONFIG / "btop/btop.conf"
    current = config.read_text() if config.is_file() else ""
    setting = 'color_theme = "matugen"'
    pattern = re.compile(r'(?m)^color_theme\s*=.*$')
    updated = pattern.sub(setting, current, count=1) if pattern.search(current) else setting + "\n" + current
    atomic_write(config, updated)


def apply_tmux() -> None:
    generated = GENERATED / "tmux.conf"
    if not generated.is_file():
        return
    theme = CONFIG / "tmux/matugen.conf"
    theme.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(generated, theme)

    config = CONFIG / "tmux/tmux.conf"
    current = config.read_text() if config.is_file() else ""
    source_line = f"source-file -q '{theme}'"
    if source_line not in current.splitlines():
        atomic_write(config, current.rstrip() + "\n\n# Matugen colors\n" + source_line + "\n")
    subprocess.run(["tmux", "source-file", str(theme)], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> None:
    apply_cava()
    apply_btop()
    apply_tmux()


if __name__ == "__main__":
    main()
