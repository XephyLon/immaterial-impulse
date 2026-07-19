#!/usr/bin/env python3
"""Guard bundled plugins against unthrottled long-running Process loops."""

from pathlib import Path
import json
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ROOT = ROOT / "modules/common/plugins/bundled"
STREAMING_COMMANDS = re.compile(r'\b(events|monitor|subscribe|follow)\b|["\']-f["\']')


def process_blocks(text: str):
    for match in re.finditer(r"\bProcess\s*\{", text):
        depth = 1
        index = match.end()
        quote = None
        escaped = False
        while index < len(text) and depth:
            char = text[index]
            if quote:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
            elif char in "\"'`":
                quote = char
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            index += 1
        yield text[match.start():index]


failures = []

# Docker's package service must only be instantiated by an explicit bar entry.
# Loading it automatically as a desktop widget triggered an in-process allocation
# runaway (multiple gigabytes within minutes) on the live Wayland shell.
docker_manifest = json.loads(
    (PLUGIN_ROOT / "docker/manifest.json").read_text(encoding="utf-8"))
if "desktopWidget" in docker_manifest:
    failures.append(
        "docker/manifest.json: Docker must not auto-load as a desktop widget; use its bar entry")
if any(option.get("key") == "pollingInterval" for option in docker_manifest.get("options", [])):
    failures.append(
        "docker/manifest.json: repeated Docker polling is disabled after live memory-runaway reproduction")

docker_service = (PLUGIN_ROOT / "docker/DockerService.qml").read_text(encoding="utf-8")
if re.search(r"\bTimer\s*\{[^{}]*\brepeat\s*:\s*true", docker_service, re.DOTALL):
    failures.append(
        "docker/DockerService.qml: repeated polling timers are prohibited; refresh on demand")

# A package bar entry must have one Loader as its sizing boundary. Nesting the
# package Loader inside PluginNode made the outer bar Loader, PluginNode, and
# package root continually negotiate geometry: the widget collapsed to one
# pixel while Quickshell allocated several gigabytes in minutes.
bar_host = (ROOT / "modules/ii/bar/PluginBarWidget.qml").read_text(encoding="utf-8")
if re.search(r"\bPluginNode\s*\{", bar_host):
    failures.append(
        "modules/ii/bar/PluginBarWidget.qml: package bar entries must not be wrapped in PluginNode")
if len(re.findall(r"\bLoader\s*\{", bar_host)) != 1:
    failures.append(
        "modules/ii/bar/PluginBarWidget.qml: package bar entries require exactly one Loader")
if re.search(r"\banchors\.fill\s*:\s*parent\b", bar_host):
    failures.append(
        "modules/ii/bar/PluginBarWidget.qml: package Loader must not fill its implicit-size host")

bar_content = (ROOT / "modules/ii/bar/BarContent.qml").read_text(encoding="utf-8")
if not re.search(
        r'name\s*===\s*["\']plugin:docker_plugin["\'].*DockerPlugin\.qml',
        bar_content):
    failures.append(
        "modules/ii/bar/BarContent.qml: bundled Docker must use its direct native bar component")

for path in PLUGIN_ROOT.rglob("*.qml"):
    for block in process_blocks(path.read_text(encoding="utf-8")):
        if STREAMING_COMMANDS.search(block) and re.search(r"\brunning\s*:\s*(?!false\b)", block):
            if "process-lifecycle: restart-safe" not in block:
                failures.append(f"{path.relative_to(ROOT)}: streaming Process has an unguarded running binding")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("Plugin process lifecycle lint passed: no unthrottled streaming processes")
