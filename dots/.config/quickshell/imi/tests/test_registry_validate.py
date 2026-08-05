#!/usr/bin/env python3
"""Contract tests for the plugin-store registry entry validator.

registry_validate.py is shared verbatim with the registry repo's CI
(docs/superpowers/specs/2026-07-27-plugin-store-design.md section 3.3), so these
tests pin the full finding surface: schema errors, branch-URL warnings,
filename convention, and the entry-vs-manifest cross-check that mirrors the
installer's same-origin and integrity rules.
"""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import tempfile

from contract_runner import run

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "registry_validate", ROOT / "scripts/plugins/registry_validate.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)

ORIGIN = "https://raw.githubusercontent.com/somebody/imi-pomodoro/v1.2.0"


def make_entry(**overrides):
    entry = {
        "id": "pomodoroTimer",
        "name": "Pomodoro Timer",
        "description": "A desktop pomodoro timer widget with bar pill integration",
        "author": "somebody",
        "version": "1.2.0",
        "apiVersion": 1,
        "capabilities": ["desktop-widget"],
        "permissions": ["settings_read", "settings_write"],
        "manifestUrl": f"{ORIGIN}/manifest.json",
        "sourceUrl": "https://github.com/somebody/imi-pomodoro",
        "screenshot": f"{ORIGIN}/screenshot.png",
    }
    entry.update(overrides)
    return {key: value for key, value in entry.items() if value is not DROP}


DROP = object()


def make_manifest(**overrides):
    manifest = {
        "id": "pomodoroTimer",
        "name": "Pomodoro Timer",
        "version": "1.2.0",
        "apiVersion": 1,
        "capabilities": ["desktop-widget"],
        # Same set as the entry, different order: order must not matter.
        "permissions": ["settings_write", "settings_read"],
        "package": {
            "baseUrl": f"{ORIGIN}/",
            "files": [
                {"path": "Widget.qml", "sha256": "a" * 64},
                {"path": "lib/Util.js", "sha256": "b" * 64},
            ],
        },
    }
    manifest.update(overrides)
    return {key: value for key, value in manifest.items() if value is not DROP}


def errors(findings):
    return [finding for finding in findings if not finding.startswith("warning: ")]


def warnings(findings):
    return [finding for finding in findings if finding.startswith("warning: ")]


def assert_error_mentions(findings, needle):
    matching = [finding for finding in errors(findings) if needle in finding]
    assert matching, f"expected an error mentioning {needle!r}, got {findings!r}"


# --- validate_entry: happy path ---------------------------------------------

def test_valid_entry_has_zero_findings():
    findings = VALIDATOR.validate_entry(make_entry())
    assert findings == [], findings


def test_unknown_fields_are_ignored():
    findings = VALIDATOR.validate_entry(make_entry(futureField={"x": 1}))
    assert findings == [], findings


# --- validate_entry: required fields ----------------------------------------

def test_each_missing_required_field_is_an_error():
    for field in ("id", "name", "description", "author", "version",
                  "apiVersion", "capabilities", "permissions",
                  "manifestUrl", "sourceUrl"):
        findings = VALIDATOR.validate_entry(make_entry(**{field: DROP}))
        assert_error_mentions(findings, field)


def test_id_rejects_bad_characters():
    for bad in ("-leadingDash", "has space", "sla/sh", "", "a" * 65):
        assert_error_mentions(VALIDATOR.validate_entry(make_entry(id=bad)), "id")


def test_id_accepts_dots_dashes_underscores():
    assert VALIDATOR.validate_entry(make_entry(id="a.b_c-d9")) == []


def test_name_must_be_nonempty_string():
    assert_error_mentions(VALIDATOR.validate_entry(make_entry(name="")), "name")
    assert_error_mentions(VALIDATOR.validate_entry(make_entry(name=3)), "name")


def test_description_length_cap():
    assert VALIDATOR.validate_entry(make_entry(description="x" * 200)) == []
    assert_error_mentions(
        VALIDATOR.validate_entry(make_entry(description="x" * 201)), "description")


def test_author_must_be_nonempty_string():
    assert_error_mentions(VALIDATOR.validate_entry(make_entry(author="")), "author")


def test_version_rejects_prerelease_and_partial():
    for bad in ("1.2.3-beta.1", "1.2", "v1.2.3", "1.2.3+build"):
        assert_error_mentions(
            VALIDATOR.validate_entry(make_entry(version=bad)), "version")


def test_api_version_must_be_int_at_least_one():
    for bad in (0, -1, "1", 1.5, True):
        assert_error_mentions(
            VALIDATOR.validate_entry(make_entry(apiVersion=bad)), "apiVersion")


def test_capabilities_must_be_nonempty_string_list():
    for bad in ([], "desktop-widget", [1]):
        assert_error_mentions(
            VALIDATOR.validate_entry(
                make_entry(capabilities=bad, screenshot=DROP)), "capabilities")


def test_permissions_reject_unknown_permission():
    assert_error_mentions(
        VALIDATOR.validate_entry(make_entry(permissions=["sudo"])), "sudo")


def test_permissions_accept_empty_list_and_full_known_set():
    assert VALIDATOR.validate_entry(make_entry(permissions=[])) == []
    assert VALIDATOR.validate_entry(make_entry(permissions=[
        "process", "network", "filesystem_read", "filesystem_write",
        "settings_read", "settings_write"])) == []


def test_manifest_url_must_be_https():
    assert_error_mentions(
        VALIDATOR.validate_entry(
            make_entry(manifestUrl="http://example.org/manifest.json")),
        "manifestUrl")


def test_source_url_must_be_https():
    assert_error_mentions(
        VALIDATOR.validate_entry(make_entry(sourceUrl="git@github.com:x/y")),
        "sourceUrl")


# --- validate_entry: optional fields ----------------------------------------

def test_optional_fields_typed():
    assert VALIDATOR.validate_entry(make_entry(
        dependencies=["libnotify"], icon="timer", tags=["productivity"],
        featured=True, minShellVersion="0.9.0")) == []
    assert_error_mentions(
        VALIDATOR.validate_entry(make_entry(dependencies="libnotify")),
        "dependencies")
    assert_error_mentions(
        VALIDATOR.validate_entry(make_entry(tags=[1])), "tags")
    assert_error_mentions(
        VALIDATOR.validate_entry(make_entry(featured="yes")), "featured")
    assert_error_mentions(
        VALIDATOR.validate_entry(make_entry(minShellVersion="0.9.0-rc1")),
        "minShellVersion")
    assert_error_mentions(
        VALIDATOR.validate_entry(
            make_entry(screenshot="http://example.org/s.png")), "screenshot")


def test_screenshot_required_for_visual_capabilities():
    for capability in (
            "desktop-widget", "bar-widget", "overlay-widget", "panel"):
        findings = VALIDATOR.validate_entry(
            make_entry(capabilities=[capability], screenshot=DROP))
        assert_error_mentions(findings, "screenshot")
    # Non-visual plugins need no screenshot.
    assert VALIDATOR.validate_entry(
        make_entry(capabilities=["service"], screenshot=DROP)) == []


def test_visual_capabilities_match_the_qml_surface_vocabulary():
    # scripts/plugins/registry_validate.py is vendored alone into the registry
    # repo, so nothing imports the QML vocabulary at runtime - drift between
    # the two lists is exactly how overlay-widget escaped the screenshot
    # requirement. Pin the Python set to the surfaces PluginManager declares.
    manager = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..",
        "modules", "common", "plugins", "PluginManager.qml")
    with open(manager, encoding="utf-8") as handle:
        source = handle.read()
    block = re.search(
        r"surfaceCapabilities:\s*\[(.*?)\]", source, re.DOTALL).group(1)
    qml_surfaces = set(re.findall(r'value:\s*"([^"]+)"', block))
    assert qml_surfaces, "failed to parse PluginManager.surfaceCapabilities"
    assert VALIDATOR.VISUAL_CAPABILITIES == qml_surfaces, (
        f"VISUAL_CAPABILITIES {sorted(VALIDATOR.VISUAL_CAPABILITIES)} has "
        f"drifted from PluginManager.surfaceCapabilities {sorted(qml_surfaces)}")


# --- validate_entry: warnings -----------------------------------------------

def test_branch_manifest_url_is_warning_only():
    for branch in ("main", "master"):
        url = f"https://raw.githubusercontent.com/s/p/{branch}/manifest.json"
        findings = VALIDATOR.validate_entry(make_entry(
            manifestUrl=url,
            screenshot=f"https://raw.githubusercontent.com/s/p/{branch}/s.png"))
        assert errors(findings) == [], findings
        assert len(warnings(findings)) == 1, findings
        assert findings[0].startswith("warning: "), findings


# --- validate_filename -------------------------------------------------------

def test_filename_match_and_mismatch():
    entry = make_entry()
    assert VALIDATOR.validate_filename("somebody-pomodoroTimer.json", entry) == []
    assert VALIDATOR.validate_filename(
        "plugins/somebody-pomodoroTimer.json", entry) == []
    for bad in ("pomodoroTimer.json", "somebody-pomodoroTimer.JSON",
                "other-pomodoroTimer.json"):
        findings = VALIDATOR.validate_filename(bad, entry)
        assert_error_mentions(findings, "somebody-pomodoroTimer.json")


# --- cross_check -------------------------------------------------------------

def test_cross_check_happy_path():
    assert VALIDATOR.cross_check(make_entry(), make_manifest()) == []


def test_cross_check_flags_field_drift():
    for field, value in (("id", "other"), ("name", "Other"),
                         ("version", "9.9.9"), ("apiVersion", 2)):
        findings = VALIDATOR.cross_check(
            make_entry(), make_manifest(**{field: value}))
        assert_error_mentions(findings, field)


def test_cross_check_flags_capability_and_permission_set_drift():
    findings = VALIDATOR.cross_check(
        make_entry(), make_manifest(capabilities=["desktop-widget", "panel"]))
    assert_error_mentions(findings, "capabilities")
    findings = VALIDATOR.cross_check(
        make_entry(), make_manifest(permissions=["settings_read"]))
    assert_error_mentions(findings, "permissions")


def test_cross_check_manifest_without_permissions_means_empty_set():
    entry = make_entry(permissions=[])
    manifest = make_manifest(permissions=DROP)
    assert VALIDATOR.cross_check(entry, manifest) == []
    # ...and an entry that claims permissions the manifest never declared drifts.
    assert_error_mentions(
        VALIDATOR.cross_check(make_entry(), manifest), "permissions")


def test_cross_check_requires_package_files():
    assert_error_mentions(
        VALIDATOR.cross_check(make_entry(), make_manifest(package=DROP)),
        "package.files")
    assert_error_mentions(
        VALIDATOR.cross_check(
            make_entry(), make_manifest(package={"files": []})),
        "package.files")


def test_cross_check_enforces_file_count_cap():
    manifest = make_manifest()
    manifest["package"]["files"] = [
        {"path": f"f{i}.qml", "sha256": "c" * 64} for i in range(65)]
    assert_error_mentions(
        VALIDATOR.cross_check(make_entry(), manifest), "64")


def test_cross_check_requires_sha256_on_every_file():
    manifest = make_manifest()
    manifest["package"]["files"][1] = {"path": "lib/Util.js"}
    assert_error_mentions(
        VALIDATOR.cross_check(make_entry(), manifest), "sha256")


def test_cross_check_rejects_string_form_file_entries():
    # The installer tolerates bare-string file entries (no hash); registry
    # submissions must not.
    manifest = make_manifest()
    manifest["package"]["files"][0] = "Widget.qml"
    assert_error_mentions(
        VALIDATOR.cross_check(make_entry(), manifest), "sha256")


def test_cross_check_rejects_cross_origin_file_url():
    manifest = make_manifest()
    manifest["package"]["files"][0] = {
        "path": "Widget.qml",
        "url": "https://cdn.example.net/Widget.qml",
        "sha256": "a" * 64,
    }
    assert_error_mentions(
        VALIDATOR.cross_check(make_entry(), manifest), "cdn.example.net")


def test_cross_check_allows_relative_file_paths():
    # Relative paths inherit baseUrl's origin, so only absolute urls are
    # origin-checked; a same-origin absolute url is also fine.
    manifest = make_manifest()
    manifest["package"]["files"][0] = {
        "path": "Widget.qml",
        "url": f"{ORIGIN}/Widget.qml",
        "sha256": "a" * 64,
    }
    assert VALIDATOR.cross_check(make_entry(), manifest) == []


def test_cross_check_rejects_cross_origin_base_url():
    manifest = make_manifest()
    manifest["package"]["baseUrl"] = "https://cdn.example.net/pkg/"
    assert_error_mentions(
        VALIDATOR.cross_check(make_entry(), manifest), "baseUrl")


def test_cross_check_rejects_cross_origin_screenshot():
    entry = make_entry(screenshot="https://imgur.example.com/shot.png")
    assert_error_mentions(
        VALIDATOR.cross_check(entry, make_manifest()), "screenshot")


# --- CLI ---------------------------------------------------------------------

def run_main(argv):
    stdout = io.StringIO()
    with contextlib.redirect_stdout(stdout):
        code = VALIDATOR.main(argv)
    return code, stdout.getvalue()


def write_json(directory, name, payload):
    path = os.path.join(directory, name)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
    return path


def test_main_clean_entry_exits_zero():
    with tempfile.TemporaryDirectory() as directory:
        path = write_json(directory, "somebody-pomodoroTimer.json", make_entry())
        code, output = run_main([path])
    assert code == 0, output
    assert output.strip() == "", output


def test_main_warnings_alone_exit_zero():
    entry = make_entry(
        manifestUrl="https://raw.githubusercontent.com/s/p/main/manifest.json",
        screenshot="https://raw.githubusercontent.com/s/p/main/s.png")
    with tempfile.TemporaryDirectory() as directory:
        path = write_json(directory, "somebody-pomodoroTimer.json", entry)
        code, output = run_main([path])
    assert code == 0, output
    assert "warning: " in output, output


def test_main_schema_error_exits_one():
    with tempfile.TemporaryDirectory() as directory:
        path = write_json(
            directory, "somebody-pomodoroTimer.json", make_entry(version="1.2"))
        code, output = run_main([path])
    assert code == 1, output
    assert "version" in output, output


def test_main_filename_mismatch_exits_one():
    with tempfile.TemporaryDirectory() as directory:
        path = write_json(directory, "wrong-name.json", make_entry())
        code, output = run_main([path])
    assert code == 1, output


def test_main_with_manifest_runs_cross_check():
    with tempfile.TemporaryDirectory() as directory:
        entry_path = write_json(
            directory, "somebody-pomodoroTimer.json", make_entry())
        manifest_path = write_json(
            directory, "manifest.json", make_manifest(version="9.9.9"))
        code, output = run_main([entry_path, "--manifest", manifest_path])
    assert code == 1, output
    assert "version" in output, output

    with tempfile.TemporaryDirectory() as directory:
        entry_path = write_json(
            directory, "somebody-pomodoroTimer.json", make_entry())
        manifest_path = write_json(directory, "manifest.json", make_manifest())
        code, output = run_main([entry_path, "--manifest", manifest_path])
    assert code == 0, output


def test_main_unreadable_entry_exits_one():
    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "somebody-pomodoroTimer.json")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("not json {")
        code, output = run_main([path])
    assert code == 1, output


def test_validator_never_touches_the_network():
    # Shared with registry CI, which runs it against untrusted PRs: the module
    # must not even import url-opening machinery.
    source = (ROOT / "scripts/plugins/registry_validate.py").read_text()
    assert "urlopen" not in source
    assert "urllib.request" not in source


if __name__ == "__main__":
    raise SystemExit(run(globals()))
