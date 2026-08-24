#!/usr/bin/env python3
"""Install generated Matugen colors without replacing unrelated app settings."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
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
    # The shipped config sources the theme by its ~ path; a hand-written one
    # may use the absolute path this used to append. Both count - matching the
    # exact absolute line only would stack a duplicate source line per palette
    # switch on any config that already sources the file another way.
    sourced = re.search(r"(?m)^\s*source-file\s+-q\s+'?[^'\n]*tmux/matugen\.conf'?\s*$", current)
    if not sourced:
        atomic_write(config, current.rstrip() + f"\n\n# Matugen colors\nsource-file -q '{theme}'\n")
    subprocess.run(["tmux", "source-file", str(theme)], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def reload_kitty() -> None:
    # matugen writes ~/.config/kitty/colors-matugen.conf directly (see
    # matugen/config.toml), and kitty.conf `include`s it, so newly launched
    # kitty windows always get the new palette. Running windows only live-reload
    # if kitty remote control is enabled; this repo ships it off, so this call is
    # a harmless no-op there and running instances are instead recolored by
    # applycolor.sh's `kill -SIGUSR1 $(pidof kitty)` later in the same switch.
    if not shutil.which("kitty"):
        return
    colors = CONFIG / "kitty/colors-matugen.conf"
    if not colors.is_file():
        return
    if subprocess.run(["pidof", "kitty"], stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL, check=False).returncode != 0:
        return
    subprocess.run(["kitty", "@", "set-colors", "--all", "--configured", str(colors)],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> None:
    # Each app fails alone. A single unwritable config - measured: a dangling
    # ~/.config/btop symlink left behind by a previous dotfiles suite - used to
    # abort the whole run here, so every app after it in this list silently
    # never got its theme, and switchwall.sh does not stop on a failing step.
    for apply in (apply_cava, apply_btop, apply_tmux, reload_kitty):
        try:
            apply()
        except OSError as error:
            print(f"[apply_matugen_app_themes] {apply.__name__} skipped: {error}",
                  file=sys.stderr)


if __name__ == "__main__":
    main()
