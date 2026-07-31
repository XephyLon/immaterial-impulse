#!/usr/bin/env python3
"""Contracts for the screenshot result popup (core shell module)."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parents[3]
SERVICE = ROOT / "services" / "ScreenshotEvents.qml"
HOST = ROOT / "modules" / "common" / "plugins" / "PluginPanelHost.qml"
PANEL = ROOT / "modules" / "ii" / "screenshotResult" / "ScreenshotResultPanel.qml"
KEYBINDS = REPO / "dots" / ".config" / "hypr" / "hyprland" / "keybinds.lua"
SHELL_QML = ROOT / "shell.qml"
PLUGIN_MANAGER = ROOT / "modules" / "common" / "plugins" / "PluginManager.qml"
SCREENSHOT_ACTION = ROOT / "modules" / "common" / "utils" / "ScreenshotAction.qml"

failures = []


def check(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'} {name}" + ("" if cond else f" {detail}"))
    if not cond:
        failures.append(name)


def read(p):
    return p.read_text(encoding="utf-8") if p.exists() else ""


def main():
    print("Screenshot result contract tests")

    svc = read(SERVICE)
    check("service exists", SERVICE.exists())
    check("service is a singleton", "pragma Singleton" in svc)
    check("service declares the signal", "signal screenshotTaken(string path)" in svc)
    check("service exposes IPC", 'target: "screenshot"' in svc and "function notify(" in svc)
    # Accepts either a QML-side check (FileView/exists/isFile) or an argv-style
    # Process probe (["test", "-f", path] gated on exit code). Either way, the
    # behavior requirement is: no emit for missing files, path never spliced.
    check("notify validates existence before emitting",
          "fileExists" in svc or "FileView" in svc or "exists(" in svc or "isFile" in svc
          or ('"test", "-f"' in svc and "exitCode === 0" in svc))
    check("notify gates on image extensions", re.search(r"png|jpe?g|webp", svc, re.I) is not None)

    host = read(HOST)
    check("panel host exists", HOST.exists())
    check("panel host loads manifest.panel components", ".panel" in host and "_basePath" in host)
    # ScreenshotEvents is anchored by the always-loaded panel now, not the host.
    check("shell.qml instantiates the panel host", "PluginPanelHost" in read(SHELL_QML))

    family = read(ROOT / "panelFamilies" / "ImmaterialImpulseFamily.qml")
    check("panel loaded by the family", "PanelLoader { component: ScreenshotResultPanel {} }" in family)
    check("family imports the module", "import qs.modules.ii.screenshotResult" in family)
    check("no bundled plugin left", not (ROOT / "modules" / "common" / "plugins" / "bundled" / "screenshot-result").exists())

    panel = read(PANEL)
    check("panel subscribes to the event", "ScreenshotEvents" in panel and "onScreenshotTaken" in panel)
    check("hover pauses the dismiss timer", "HoverHandler" in panel or "hovered" in panel)
    check("dismiss timer uses config", "timeoutMs" in panel)
    # Path-safety: every bash -c in the panel must pass the path as an argument,
    # never interpolated. Allow `${...}` only for QML-side constants, not for
    # anything derived from the screenshot path property.
    for mch in re.finditer(r'"bash",\s*"-c",\s*(`[^`]*`|"[^"]*")', panel):
        body = mch.group(1)
        check("no path splicing in bash -c", "${" not in body or "currentPath" not in body,
              f"suspicious: {body[:60]}")
    check("discard guarded to scratch dirs",
          "screenshotTemp" in panel and re.search(r'startsWith\(', panel) is not None)
    raw_durations = [m for m in re.finditer(r"duration:\s*(\d+)", panel) if m.group(1) != "0"]
    check("panel motion is token-only", not raw_durations,
          f"raw: {[m.group(0) for m in raw_durations]}")

    kb = read(KEYBINDS)
    check("Print keybind writes a file and notifies",
          "screenshot notify" in kb and "wl-copy" in kb)
    check("keybind tolerates a dead shell", "|| true" in kb)

    sa = read(SCREENSHOT_ACTION)
    check("copy snip keeps a result file", "resultPath" in sa and "tee" in sa)

    if failures:
        print(f"{len(failures)} screenshot result contract(s) failed")
        return 1
    print("All screenshot result contract tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
