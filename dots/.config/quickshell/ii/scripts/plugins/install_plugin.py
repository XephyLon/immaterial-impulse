#!/usr/bin/env python3
"""Install a Quickshell plugin package described by a remote manifest."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

# Installing a package means running its QML inside the shell process, so the
# transport is the only thing standing between a manifest and arbitrary code
# execution. Require TLS, keep every file on the manifest's own origin, and
# refuse to buffer an unbounded response into memory.
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024
MAX_FILE_COUNT = 64


def https_origin(url: str, description: str) -> tuple:
    parts = urlsplit(url)
    if parts.scheme != "https" or not parts.hostname:
        raise ValueError(f"{description} must be an https:// URL: {url}")
    return (parts.hostname.lower(), parts.port or 443)


def require_same_origin(url: str, origin: tuple, description: str) -> str:
    if https_origin(url, description) != origin:
        raise ValueError(f"{description} must stay on {origin[0]}: {url}")
    return url


def download(url: str, limit: int = MAX_FILE_BYTES) -> bytes:
    request = Request(url, headers={"User-Agent": "immaterial-impulse-plugin-installer/1"})
    with urlopen(request, timeout=30) as response:
        declared = response.headers.get("Content-Length")
        if declared and declared.isdigit() and int(declared) > limit:
            raise ValueError(f"response exceeds {limit} bytes: {url}")
        # Read one byte past the limit so a missing or lying Content-Length
        # cannot stream an arbitrarily large body into memory.
        payload = response.read(limit + 1)
    if len(payload) > limit:
        raise ValueError(f"response exceeds {limit} bytes: {url}")
    return payload


def safe_relative_path(value: str) -> Path:
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise ValueError(f"unsafe package path: {value}")
    if any(part.startswith(".") or ":" in part for part in path.parts):
        raise ValueError(f"unsafe package path: {value}")
    return Path(*path.parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest_url")
    parser.add_argument("install_root", type=Path)
    args = parser.parse_args()

    origin = https_origin(args.manifest_url, "manifest URL")
    manifest_bytes = download(args.manifest_url)
    manifest = json.loads(manifest_bytes)
    plugin_id = manifest.get("id", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", plugin_id):
        raise ValueError("manifest has an invalid plugin id")

    package = manifest.get("package")
    if not isinstance(package, dict) or not isinstance(package.get("files"), list):
        raise ValueError("remote manifest must declare package.files")
    base_url = package.get("baseUrl") or args.manifest_url
    require_same_origin(base_url, origin, "package baseUrl")
    if len(package["files"]) > MAX_FILE_COUNT:
        raise ValueError(f"package declares more than {MAX_FILE_COUNT} files")

    args.install_root.mkdir(parents=True, exist_ok=True)
    destination = args.install_root / plugin_id
    if destination.exists():
        raise FileExistsError(f"plugin already installed: {plugin_id}")

    staging = Path(tempfile.mkdtemp(prefix=f".{plugin_id}-", dir=args.install_root))
    try:
        (staging / "manifest.json").write_bytes(manifest_bytes)
        downloaded_bytes = 0
        for entry in package["files"]:
            if isinstance(entry, str):
                relative = safe_relative_path(entry)
                url = urljoin(base_url, entry)
                expected_hash = ""
            elif isinstance(entry, dict):
                relative = safe_relative_path(entry.get("path", ""))
                url = entry.get("url") or urljoin(base_url, relative.as_posix())
                expected_hash = entry.get("sha256", "")
            else:
                raise ValueError("package.files entries must be strings or objects")

            require_same_origin(url, origin, "package file URL")
            payload = download(url, min(MAX_FILE_BYTES, MAX_TOTAL_BYTES - downloaded_bytes))
            downloaded_bytes += len(payload)
            if expected_hash and hashlib.sha256(payload).hexdigest() != expected_hash.lower():
                raise ValueError(f"checksum mismatch for {relative}")
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)

        os.replace(staging, destination)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    print(plugin_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
