#!/usr/bin/env python3
"""Validate a plugin-store registry entry against the schema and its manifest.

Shared between the shell test suite and the plugin registry's CI (see
docs/superpowers/specs/2026-07-27-plugin-store-design.md section 3.3): the
registry workflow vendors this single file, so it must stay stdlib-only and
self-contained. It never touches the network - CI fetches the manifest itself
and hands the parsed dict to cross_check().

Findings are strings: plain strings are fatal schema/consistency errors,
strings prefixed "warning: " are advisory only.
"""

import argparse
import json
import os
import re
import sys
from urllib.parse import urlsplit

# Keep in sync with scripts/plugins/install_plugin.py. The installer raises on
# these conditions at install time; this validator reports them at review time
# so a listed plugin can never fail the installer's checks. Duplicated rather
# than imported because the registry repo vendors this file alone.
ID_PATTERN = r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}"
MAX_FILE_COUNT = 64

VERSION_PATTERN = r"\d+\.\d+\.\d+"
MAX_DESCRIPTION_LENGTH = 200
KNOWN_PERMISSIONS = frozenset({
    "process", "network", "filesystem_read", "filesystem_write",
    "settings_read", "settings_write",
})
# Capabilities with a visual entry point: the store UI needs a screenshot to
# show what the user is about to install.
VISUAL_CAPABILITIES = frozenset({"desktop-widget", "bar-widget", "panel"})


def _https_origin(url):
    """(host, port) for an https URL with a hostname, else None.

    Mirrors install_plugin.py's https_origin(), but reports instead of raising:
    every finding must be collected, not just the first.
    """
    if not isinstance(url, str):
        return None
    parts = urlsplit(url)
    if parts.scheme != "https" or not parts.hostname:
        return None
    return (parts.hostname.lower(), parts.port or 443)


def _is_string_list(value):
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def validate_entry(entry: dict) -> list:
    findings = []

    plugin_id = entry.get("id")
    if not isinstance(plugin_id, str) or not re.fullmatch(ID_PATTERN, plugin_id):
        findings.append(f"id must be a string matching ^{ID_PATTERN}$")

    for field in ("name", "author"):
        value = entry.get(field)
        if not isinstance(value, str) or not value:
            findings.append(f"{field} must be a non-empty string")

    description = entry.get("description")
    if not isinstance(description, str):
        findings.append("description must be a string")
    elif len(description) > MAX_DESCRIPTION_LENGTH:
        findings.append(
            f"description must be at most {MAX_DESCRIPTION_LENGTH} characters "
            f"(got {len(description)})")

    version = entry.get("version")
    if not isinstance(version, str) or not re.fullmatch(VERSION_PATTERN, version):
        findings.append(
            f"version must be plain semver matching ^{VERSION_PATTERN}$ "
            "(no prerelease or build suffix)")

    api_version = entry.get("apiVersion")
    if isinstance(api_version, bool) or not isinstance(api_version, int) \
            or api_version < 1:
        findings.append("apiVersion must be an integer >= 1")

    capabilities = entry.get("capabilities")
    if not _is_string_list(capabilities) or not capabilities:
        findings.append("capabilities must be a non-empty list of strings")
        capabilities = []

    permissions = entry.get("permissions")
    if not _is_string_list(permissions):
        findings.append("permissions must be a list of strings")
    else:
        for permission in sorted(set(permissions) - KNOWN_PERMISSIONS):
            findings.append(
                f"permissions contains unknown permission: {permission} "
                f"(known: {', '.join(sorted(KNOWN_PERMISSIONS))})")

    for field in ("manifestUrl", "sourceUrl"):
        if _https_origin(entry.get(field)) is None:
            findings.append(f"{field} must be an https:// URL")

    # Optional fields: absent is fine, present means typed.
    if "dependencies" in entry and not _is_string_list(entry["dependencies"]):
        findings.append("dependencies must be a list of strings")
    if "tags" in entry and not _is_string_list(entry["tags"]):
        findings.append("tags must be a list of strings")
    if "icon" in entry and not isinstance(entry["icon"], str):
        findings.append("icon must be a string")
    if "featured" in entry and not isinstance(entry["featured"], bool):
        findings.append("featured must be a boolean")
    if "minShellVersion" in entry:
        min_shell = entry["minShellVersion"]
        if not isinstance(min_shell, str) \
                or not re.fullmatch(VERSION_PATTERN, min_shell):
            findings.append(
                f"minShellVersion must be plain semver matching ^{VERSION_PATTERN}$")

    screenshot = entry.get("screenshot")
    if screenshot is not None and _https_origin(screenshot) is None:
        findings.append("screenshot must be an https:// URL")
    if screenshot is None and VISUAL_CAPABILITIES.intersection(capabilities):
        findings.append(
            "screenshot is required for plugins with a visual capability "
            f"({', '.join(sorted(VISUAL_CAPABILITIES.intersection(capabilities)))})")

    manifest_url = entry.get("manifestUrl")
    if isinstance(manifest_url, str) \
            and ("/main/" in manifest_url or "/master/" in manifest_url):
        findings.append(
            "warning: manifestUrl looks branch-pinned (/main/ or /master/); "
            "use a tag- or commit-pinned URL so the listed version is immutable")

    return findings


def validate_filename(filename: str, entry: dict) -> list:
    author = entry.get("author")
    plugin_id = entry.get("id")
    if not isinstance(author, str) or not isinstance(plugin_id, str):
        # validate_entry already reports the broken fields; without them there
        # is no expected filename to compare against.
        return ["filename cannot be checked: entry author/id missing or invalid"]
    expected = f"{author}-{plugin_id}.json"
    actual = os.path.basename(filename)
    if actual != expected:
        return [f"filename must be {expected} (got {actual})"]
    return []


def cross_check(entry: dict, manifest: dict) -> list:
    findings = []

    for field in ("id", "name", "version", "apiVersion"):
        if entry.get(field) != manifest.get(field):
            findings.append(
                f"{field} differs between entry ({entry.get(field)!r}) "
                f"and manifest ({manifest.get(field)!r})")

    for field, default in (("capabilities", None), ("permissions", [])):
        entry_value = entry.get(field)
        manifest_value = manifest.get(field, default)
        entry_set = set(entry_value) if _is_string_list(entry_value) else None
        manifest_set = set(manifest_value) \
            if _is_string_list(manifest_value) else None
        if entry_set is None or manifest_set is None or entry_set != manifest_set:
            findings.append(
                f"{field} differ between entry ({entry_value!r}) "
                f"and manifest ({manifest_value!r})")

    package = manifest.get("package")
    files = package.get("files") if isinstance(package, dict) else None
    if not isinstance(files, list) or not files:
        findings.append("manifest must declare a non-empty package.files list")
        files = []
    elif len(files) > MAX_FILE_COUNT:
        findings.append(
            f"package.files declares {len(files)} files "
            f"(installer cap is {MAX_FILE_COUNT})")

    origin = _https_origin(entry.get("manifestUrl"))
    if origin is None:
        findings.append(
            "cannot check origins: entry manifestUrl is not a valid https:// URL")

    def check_origin(url, description):
        if origin is None:
            return
        if _https_origin(url) != origin:
            findings.append(
                f"{description} must stay on {origin[0]}: {url}")

    screenshot = entry.get("screenshot")
    if screenshot is not None:
        check_origin(screenshot, "entry screenshot")

    base_url = package.get("baseUrl") if isinstance(package, dict) else None
    if base_url is not None:
        check_origin(base_url, "package baseUrl")

    for index, file_entry in enumerate(files):
        if not isinstance(file_entry, dict):
            # The installer accepts bare-string entries (path joined against
            # baseUrl, no integrity check); registry submissions must carry a
            # sha256 per file, so only the object form is acceptable.
            findings.append(
                f"package.files[{index}] must be an object with a sha256 "
                "(string-form file entries carry no checksum)")
            continue
        sha256 = file_entry.get("sha256")
        if not isinstance(sha256, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", sha256):
            findings.append(
                f"package.files[{index}] must declare a sha256 hex digest")
        url = file_entry.get("url")
        # Relative paths inherit baseUrl's (already checked) origin; only
        # absolute URLs can point somewhere else.
        if isinstance(url, str) and urlsplit(url).scheme:
            check_origin(url, f"package.files[{index}] url")

    return findings


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate a plugin registry entry (and optionally "
                    "cross-check it against the plugin's manifest.json).")
    parser.add_argument("entry", help="path to the <author>-<id>.json entry")
    parser.add_argument(
        "--manifest",
        help="path to the plugin's own manifest.json (pre-fetched by the "
             "caller; this tool never touches the network)")
    args = parser.parse_args(argv)

    try:
        with open(args.entry, encoding="utf-8") as handle:
            entry = json.load(handle)
    except (OSError, ValueError) as error:
        print(f"entry is not readable JSON: {error}")
        return 1
    if not isinstance(entry, dict):
        print("entry must be a JSON object")
        return 1

    findings = validate_entry(entry)
    findings += validate_filename(args.entry, entry)

    if args.manifest:
        try:
            with open(args.manifest, encoding="utf-8") as handle:
                manifest = json.load(handle)
        except (OSError, ValueError) as error:
            print(f"manifest is not readable JSON: {error}")
            return 1
        if not isinstance(manifest, dict):
            print("manifest must be a JSON object")
            return 1
        findings += cross_check(entry, manifest)

    for finding in findings:
        print(finding)
    return 1 if any(
        not finding.startswith("warning: ") for finding in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
