#!/usr/bin/env python3
"""Discover installed Steam Wallpaper Engine projects without loading their assets."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


DEFAULT_ROOTS = (
    Path.home() / ".local/share/Steam/steamapps/workshop/content/431960",
    Path.home() / ".steam/steam/steamapps/workshop/content/431960",
)


def project_roots(configured: str) -> list[Path]:
    if configured:
        candidates = [Path(configured).expanduser()]
    else:
        candidates = list(DEFAULT_ROOTS)
    for steam_root in (() if configured else (Path.home() / ".local/share/Steam", Path.home() / ".steam/steam")):
        libraries = steam_root / "steamapps/libraryfolders.vdf"
        try:
            contents = libraries.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for library in re.findall(r'"path"\s+"([^"]+)"', contents):
            candidates.append(Path(library.replace("\\\\", "\\")) / "steamapps/workshop/content/431960")
    roots: list[Path] = []
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved.is_dir() and resolved not in roots:
            roots.append(resolved)
    return roots


def confined_preview(directory: Path, preview_name: object) -> Path:
    """Resolve a project.json "preview" to a real file inside its own project
    directory. project.json is untrusted Workshop content, so an absolute path
    or a "../" escape must not point the preview at an arbitrary file on disk."""
    if not isinstance(preview_name, str) or not preview_name:
        return Path()
    try:
        base = directory.resolve()
        candidate = (directory / preview_name).resolve()
        candidate.relative_to(base)
    except (ValueError, OSError):
        return Path()
    return candidate if candidate.is_file() else Path()


def scan(configured: str) -> list[dict[str, object]]:
    projects_by_id: dict[str, tuple[tuple[int, int, str], dict[str, object]]] = {}
    for root in project_roots(configured):
        for manifest in sorted(root.glob("*/project.json")):
            try:
                data = json.loads(manifest.read_text(encoding="utf-8-sig"))
            except (OSError, UnicodeError, json.JSONDecodeError):
                continue
            directory = manifest.parent
            preview_name = data.get("preview", "")
            preview = confined_preview(directory, preview_name)
            if preview == Path():
                preview = next(
                    (path for name in ("preview.jpg", "preview.png", "preview.gif") if (path := directory / name).is_file()),
                    Path(),
                )
            project = {
                "id": directory.name,
                "title": str(data.get("title") or directory.name),
                "type": str(data.get("type") or "unknown"),
                "tags": data.get("tags") if isinstance(data.get("tags"), list) else [],
                "path": str(directory),
                # An empty Path() is "." and truthy, so compare explicitly to
                # avoid emitting "." when no preview file was found.
                "preview": str(preview) if preview != Path() else "",
            }
            try:
                file_count = sum(1 for path in directory.rglob("*") if path.is_file())
                manifest_mtime = manifest.stat().st_mtime_ns
            except OSError:
                file_count = 0
                manifest_mtime = 0
            # The same Workshop item may exist in multiple Steam libraries.
            # Prefer its newest revision, then its more complete installation;
            # the path gives the final selection a stable tie-breaker.
            score = (manifest_mtime, file_count, str(directory))
            current = projects_by_id.get(directory.name)
            if current is None or score > current[0]:
                projects_by_id[directory.name] = (score, project)
    projects = [entry[1] for entry in projects_by_id.values()]
    projects.sort(key=lambda item: str(item["title"]).casefold())
    return projects


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="")
    args = parser.parse_args()
    print(json.dumps(scan(args.root), ensure_ascii=False))


if __name__ == "__main__":
    main()
