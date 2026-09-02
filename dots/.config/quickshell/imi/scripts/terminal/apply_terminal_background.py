#!/usr/bin/env python3
"""Apply the shell's terminal background settings to its generated Kitty theme."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
from pathlib import Path


START_MARKER = "# BEGIN immaterial-impulse terminal background"
END_MARKER = "# END immaterial-impulse terminal background"
VALID_LAYOUTS = {"tiled", "mirror-tiled", "scaled", "clamped"}


def without_managed_block(text: str) -> str:
    """Return theme text with the previously generated block removed."""
    lines = text.splitlines()
    output = []
    inside = False
    for line in lines:
        if line == START_MARKER:
            inside = True
            continue
        if line == END_MARKER:
            inside = False
            continue
        if not inside:
            output.append(line)
    return "\n".join(output).rstrip() + "\n"


def render(theme_text: str, settings: dict) -> str:
    """Replace the managed block from the terminal settings.

    `settings` is `appearance.terminal`: `opacity` (the window's
    background_opacity, 1 = opaque) and `background` (the pattern). A bare
    pattern dict is accepted too, as the older callers and tests pass one.
    """
    clean = without_managed_block(theme_text)
    # The pattern dict has an `opacity` of its own (the pattern's visibility),
    # so only the `background` key tells the two shapes apart.
    if "background" in settings:
        pattern = settings.get("background", {}) or {}
        window_opacity = max(0.0, min(1.0, float(settings.get("opacity", 1.0))))
    else:
        pattern = settings
        window_opacity = 1.0

    opacity_lines = []
    if window_opacity < 1.0:
        opacity_lines = [
            f"background_opacity {window_opacity:.2f}",
            "dynamic_background_opacity yes",
        ]

    if not pattern.get("enabled", False):
        if not opacity_lines:
            return clean
        return clean + "\n" + "\n".join([START_MARKER, *opacity_lines, END_MARKER]) + "\n"

    settings = pattern
    raw_path = str(settings.get("imagePath", "")).strip()
    if not raw_path or "\n" in raw_path or "\r" in raw_path:
        raise ValueError("Choose a valid terminal pattern image")
    image_path = Path(os.path.expandvars(raw_path)).expanduser()
    if not image_path.is_absolute() or not image_path.is_file():
        raise ValueError("Terminal pattern image does not exist")

    layout = str(settings.get("layout", "tiled"))
    if layout not in VALID_LAYOUTS:
        raise ValueError("Unsupported terminal pattern layout")
    opacity = max(0.0, min(1.0, float(settings.get("opacity", 0.18))))
    tint = 1.0 - opacity

    block = [
        START_MARKER,
        *opacity_lines,
        f"background_image {image_path}",
        f"background_image_layout {layout}",
        f"background_tint {tint:.2f}",
        "background_tint_gaps 1.0",
        END_MARKER,
    ]
    return clean + "\n" + "\n".join(block) + "\n"


def load_settings(config_path: Path) -> dict:
    data = json.loads(config_path.read_text(encoding="utf-8"))
    return data.get("appearance", {}).get("terminal", {})


def write_atomic(path: Path, text: str) -> None:
    """Replace the generated theme without exposing Kitty to a partial write."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(text)
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def reload_kitty() -> None:
    result = subprocess.run(
        ["pidof", "kitty"], check=False, capture_output=True, text=True
    )
    for value in result.stdout.split():
        try:
            os.kill(int(value), signal.SIGUSR1)
        except (ValueError, ProcessLookupError, PermissionError):
            continue


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--theme", type=Path)
    parser.add_argument("--reload", action="store_true")
    args = parser.parse_args()

    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    theme_path = args.theme or state_home / "quickshell/user/generated/terminal/kitty-theme.conf"
    theme_path.parent.mkdir(parents=True, exist_ok=True)
    existing = theme_path.read_text(encoding="utf-8") if theme_path.exists() else ""

    try:
        updated = render(existing, load_settings(args.config))
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as error:
        # Remove an old managed block even when a newly entered path is invalid,
        # so the visible terminal never keeps showing a stale image.
        write_atomic(theme_path, without_managed_block(existing))
        print(str(error), file=sys.stderr)
        return 1

    write_atomic(theme_path, updated)
    if args.reload:
        reload_kitty()
    print("Terminal background updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
