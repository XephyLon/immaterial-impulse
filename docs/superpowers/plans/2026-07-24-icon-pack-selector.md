# Icon Pack Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a system-wide icon-pack selector — a preview grid in the shell's Interface settings that writes GTK/kdeglobals/gsettings and auto-restarts the shell to adopt the chosen icon theme.

**Architecture:** A python scanner enumerates installed icon themes to JSON; an `IconThemes.qml` singleton runs it (mirroring `WallpaperEngine.qml`) and exposes the list. A grid UI in `InterfaceConfig.qml` previews each theme with real sample icons loaded by file path. Picking one runs `apply-icon-theme.sh` (validates the id, writes GTK 3/4 `settings.ini`, `kdeglobals`, and gsettings via argv), then the shell relaunches. Design doc: `docs/superpowers/specs/2026-07-24-icon-pack-selector-design.md`.

**Tech Stack:** QML (Quickshell), Python 3 (scanner + tests), Bash (apply script), configparser for ini edits, gsettings for the live signal.

**Key repo conventions (verified):**
- Config options live in `modules/common/Config.qml` as nested `JsonObject`; the `appearance` block starts at line 126.
- Scanner-service pattern: `services/WallpaperEngine.qml` runs a python scanner via `Process` + `StdioCollector.onStreamFinished` → `JSON.parse`.
- Script paths registered in `modules/common/Directories.qml` (e.g. `wallpaperSwitchScriptPath`, line 44).
- matugen writes only `gtk-3.0/gtk.css`/`gtk-4.0/gtk.css`; it does NOT own `settings.ini` or `kdeglobals` — safe to write those directly.
- `switchwall.sh:41-45` is the existing gsettings idiom to mirror (`gsettings set org.gnome.desktop.interface gtk-theme …`).
- Python tests are registered as sequential blocks in `tests/run_tests.sh` and run via `qmltestrunner`-adjacent `python3 "$SCRIPT_DIR/<name>.py"`.
- Security rule (from commit 75ef1aec): never splice external/derived strings into `bash -c`; validate + pass as argv.

---

## Task 1: Add the `appearance.iconTheme` config option

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/common/Config.qml:126-127`

- [ ] **Step 1: Add the option**

In `modules/common/Config.qml`, inside `property JsonObject appearance: JsonObject {` (line 126), add as the first child (after line 126, before `extraBackgroundTint`):

```qml
                property JsonObject appearance: JsonObject {
                    // "" = follow the system icon theme; otherwise the directory
                    // name of an installed icon theme (see IconThemes.qml).
                    property string iconTheme: ""
                    property bool extraBackgroundTint: true
```

- [ ] **Step 2: Verify it loads**

Run: `cd dots/.config/quickshell/ii && QT_QPA_PLATFORM=offscreen ./tests/run_tests.sh 2>&1 | tail -3`
Expected: `All tests passed successfully!` (no QML syntax error in Config.qml on load).

- [ ] **Step 3: Commit**

```bash
git add dots/.config/quickshell/ii/modules/common/Config.qml
git commit -m "feat(config): add appearance.iconTheme option"
```

---

## Task 2: Icon-theme scanner script (TDD)

**Files:**
- Create: `dots/.config/quickshell/ii/scripts/icons/scan-icon-themes.py`
- Test: `dots/.config/quickshell/ii/tests/test_scan_icon_themes.py`

- [ ] **Step 1: Write the failing test**

Create `tests/test_scan_icon_themes.py`:

```python
#!/usr/bin/env python3
"""Tests for the icon-theme scanner: real themes kept, cursor-only excluded."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCANNER = Path(__file__).resolve().parents[1] / "scripts/icons/scan-icon-themes.py"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ScanIconThemesTest(unittest.TestCase):
    def run_scanner(self, roots):
        result = subprocess.run(
            [sys.executable, str(SCANNER), *roots],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)

    def test_real_theme_kept_cursor_only_excluded(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            # A real app-icon theme with a sample icon on disk.
            write(root / "CoolIcons/index.theme",
                  "[Icon Theme]\nName=Cool Icons\nDirectories=48x48/apps\n\n"
                  "[48x48/apps]\nSize=48\nContext=Applications\nType=Fixed\n")
            write(root / "CoolIcons/48x48/apps/firefox.png", "x")
            # A cursor-only pack: must be excluded.
            write(root / "MyCursors/index.theme",
                  "[Icon Theme]\nName=My Cursors\nDirectories=cursors\n\n"
                  "[cursors]\nSize=24\nContext=Cursors\nType=Fixed\n")
            # hicolor: must be excluded (fallback base, not selectable).
            write(root / "hicolor/index.theme",
                  "[Icon Theme]\nName=Hicolor\nDirectories=48x48/apps\n")

            themes = self.run_scanner([str(root)])
            ids = {t["id"] for t in themes}
            self.assertIn("CoolIcons", ids)
            self.assertNotIn("MyCursors", ids)
            self.assertNotIn("hicolor", ids)

            cool = next(t for t in themes if t["id"] == "CoolIcons")
            self.assertEqual(cool["name"], "Cool Icons")
            self.assertTrue(cool["sampleIcons"])
            self.assertTrue(all(os.path.isabs(p) for p in cool["sampleIcons"]))
            self.assertTrue(all(os.path.exists(p) for p in cool["sampleIcons"]))

    def test_missing_root_is_ignored(self):
        themes = self.run_scanner(["/nonexistent/path/xyz"])
        self.assertEqual(themes, [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 dots/.config/quickshell/ii/tests/test_scan_icon_themes.py`
Expected: FAIL — scanner script does not exist yet (`FileNotFoundError` / non-zero).

- [ ] **Step 3: Write the scanner**

Create `scripts/icons/scan-icon-themes.py`:

```python
#!/usr/bin/env python3
"""Scan icon-theme directories and emit selectable themes as JSON.

Usage: scan-icon-themes.py [ROOT ...]
Defaults to the standard icon roots when no ROOT is given.
Output: JSON array of {id, name, path, sampleIcons:[abs path,...]} sorted by name.
"""
import configparser
import json
import os
import sys

# App-ish icon names we try to preview, in preference order. Whatever resolves
# first (up to SAMPLE_COUNT) is used; a theme that ships none simply gets fewer.
SAMPLE_NAMES = [
    "firefox", "org.mozilla.firefox", "google-chrome", "code",
    "folder", "user-home", "text-editor", "org.gnome.TextEditor",
    "system-settings", "preferences-system", "utilities-terminal", "terminal",
]
SAMPLE_COUNT = 4
ICON_EXTS = (".svg", ".png")
EXCLUDE_IDS = {"hicolor", "default", "locolor"}


def default_roots():
    home = os.path.expanduser("~")
    data_home = os.environ.get("XDG_DATA_HOME", f"{home}/.local/share")
    return [f"{data_home}/icons", f"{home}/.icons", "/usr/share/icons"]


def parse_index(path):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError):
        return None
    if not cp.has_section("Icon Theme"):
        return None
    name = cp.get("Icon Theme", "Name", fallback="").strip()
    dirs = cp.get("Icon Theme", "Directories", fallback="").strip()
    dir_list = [d.strip() for d in dirs.replace(",", " ").split() if d.strip()]
    return {"name": name, "dirs": dir_list, "cp": cp}


def is_selectable(meta, theme_id):
    if theme_id in EXCLUDE_IDS:
        return False
    if theme_id.lower().endswith("cursors") or theme_id.lower().endswith("cursor"):
        return False
    non_cursor = [d for d in meta["dirs"] if "cursor" not in d.lower()]
    return bool(non_cursor)


def find_samples(theme_dir, meta):
    # Prefer larger, scalable, apps/places dirs first for nicer previews.
    def score(d):
        s = 0
        if "scalable" in d:
            s += 1000
        for token in d.replace("/", "x").split("x"):
            if token.isdigit():
                s = max(s, int(token))
        if "apps" in d or "places" in d:
            s += 5
        return s

    ordered = sorted(meta["dirs"], key=score, reverse=True)
    samples = []
    for name in SAMPLE_NAMES:
        for d in ordered:
            hit = None
            for ext in ICON_EXTS:
                candidate = os.path.join(theme_dir, d, name + ext)
                if os.path.isfile(candidate):
                    hit = candidate
                    break
            if hit:
                samples.append(hit)
                break
        if len(samples) >= SAMPLE_COUNT:
            break
    return samples


def scan(roots):
    seen = set()
    themes = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            theme_dir = os.path.join(root, entry)
            index = os.path.join(theme_dir, "index.theme")
            if entry in seen or not os.path.isfile(index):
                continue
            meta = parse_index(index)
            if not meta or not is_selectable(meta, entry):
                continue
            samples = find_samples(theme_dir, meta)
            if not samples:
                # No previewable icons resolved: skip (nothing to show, likely
                # a symbolic-only or incomplete theme).
                continue
            seen.add(entry)
            themes.append({
                "id": entry,
                "name": meta["name"] or entry,
                "path": theme_dir,
                "sampleIcons": samples,
            })
    themes.sort(key=lambda t: t["name"].lower())
    return themes


def main():
    roots = sys.argv[1:] or default_roots()
    json.dump(scan(roots), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 dots/.config/quickshell/ii/tests/test_scan_icon_themes.py`
Expected: `OK` (2 tests).

- [ ] **Step 5: Register the test in the suite**

In `tests/run_tests.sh`, after the `test_expressive_design_system.py` block (around line 149), add:

```bash
echo "Running icon theme scanner tests..."
if ! python3 "$SCRIPT_DIR/test_scan_icon_themes.py"; then
    echo "Icon theme scanner tests failed."
    exit 1
fi
```

- [ ] **Step 6: Commit**

```bash
git add dots/.config/quickshell/ii/scripts/icons/scan-icon-themes.py \
  dots/.config/quickshell/ii/tests/test_scan_icon_themes.py \
  dots/.config/quickshell/ii/tests/run_tests.sh
git commit -m "feat(icons): add installed-icon-theme scanner + tests"
```

---

## Task 3: Apply script (TDD)

**Files:**
- Create: `dots/.config/quickshell/ii/scripts/icons/apply-icon-theme.sh`
- Test: `dots/.config/quickshell/ii/tests/test_icon_theme_apply.py`

- [ ] **Step 1: Write the failing test**

Create `tests/test_icon_theme_apply.py`:

```python
#!/usr/bin/env python3
"""Tests for apply-icon-theme.sh: writes the right keys, rejects bad input."""
import configparser
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/icons/apply-icon-theme.sh"


class ApplyIconThemeTest(unittest.TestCase):
    def run_apply(self, theme_id, home):
        env = dict(os.environ)
        env["HOME"] = str(home)
        env["XDG_DATA_HOME"] = str(home / ".local/share")
        # No gsettings schema in CI: the script must tolerate its failure.
        return subprocess.run(
            ["bash", str(SCRIPT), theme_id],
            capture_output=True, text=True, env=env,
        )

    def make_theme(self, home, theme_id):
        d = home / ".local/share/icons" / theme_id
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.theme").write_text("[Icon Theme]\nName=X\n", encoding="utf-8")

    def read_key(self, path, section, key):
        cp = configparser.ConfigParser(interpolation=None, strict=False)
        cp.optionxform = str
        cp.read(path, encoding="utf-8")
        return cp.get(section, key)

    def test_writes_all_targets(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            self.make_theme(home, "CoolIcons")
            res = self.run_apply("CoolIcons", home)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(
                self.read_key(home / ".config/gtk-3.0/settings.ini",
                              "Settings", "gtk-icon-theme-name"), "CoolIcons")
            self.assertEqual(
                self.read_key(home / ".config/gtk-4.0/settings.ini",
                              "Settings", "gtk-icon-theme-name"), "CoolIcons")
            self.assertEqual(
                self.read_key(home / ".config/kdeglobals", "Icons", "Theme"),
                "CoolIcons")

    def test_preserves_other_gtk_keys(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            self.make_theme(home, "CoolIcons")
            gtk3 = home / ".config/gtk-3.0/settings.ini"
            gtk3.parent.mkdir(parents=True, exist_ok=True)
            gtk3.write_text("[Settings]\ngtk-theme-name=adw-gtk3\n", encoding="utf-8")
            res = self.run_apply("CoolIcons", home)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(
                self.read_key(gtk3, "Settings", "gtk-theme-name"), "adw-gtk3")
            self.assertEqual(
                self.read_key(gtk3, "Settings", "gtk-icon-theme-name"), "CoolIcons")

    def test_rejects_injection_and_traversal(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            for bad in ["../evil", "x; rm -rf ~", "$(touch /tmp/pwned)", "a/b"]:
                res = self.run_apply(bad, home)
                self.assertNotEqual(res.returncode, 0)
            self.assertFalse((home / ".config/gtk-3.0/settings.ini").exists())

    def test_rejects_theme_not_on_disk(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            res = self.run_apply("NotInstalled", home)
            self.assertNotEqual(res.returncode, 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 dots/.config/quickshell/ii/tests/test_icon_theme_apply.py`
Expected: FAIL — script does not exist.

- [ ] **Step 3: Write the apply script**

Create `scripts/icons/apply-icon-theme.sh`:

```bash
#!/usr/bin/env bash
# Apply a system-wide icon theme: GTK 3/4 settings.ini + kdeglobals + gsettings.
# The theme id is the directory name of an installed icon theme. It is validated
# and passed as an argv element to every command (never spliced into a shell
# string), mirroring the injection-safe pattern used across this shell.
set -euo pipefail

id="${1:-}"

# Whitelist the id to filesystem-safe characters (theme directory names). This
# blocks path traversal (no '/'), and command/expansion metacharacters.
if ! printf '%s' "$id" | grep -qE '^[A-Za-z0-9 ._+-]+$'; then
    echo "apply-icon-theme: invalid theme id: '$id'" >&2
    exit 2
fi

# Confirm the theme actually exists under a known icon root before applying, so
# a value that passed the charset check but is not a real theme is still refused.
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
found=0
for root in "$data_home/icons" "$HOME/.icons" /usr/share/icons; do
    if [ -d "$root/$id" ]; then found=1; break; fi
done
if [ "$found" -ne 1 ]; then
    echo "apply-icon-theme: theme not found: '$id'" >&2
    exit 3
fi

# GTK 3/4 settings.ini and kdeglobals are plain ini; edit them with configparser
# so unrelated keys/sections are preserved. matugen owns gtk.css, not these
# files, so these writes are not clobbered by a later color run. id arrives as
# argv (sys.argv[1]), never interpolated into the script text.
python3 - "$id" <<'PY'
import sys, os, configparser
theme = sys.argv[1]
home = os.path.expanduser("~")

def set_key(path, section, key, value):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str  # keep key case (gtk-icon-theme-name, Theme)
    if os.path.exists(path):
        cp.read(path, encoding="utf-8")
    if not cp.has_section(section):
        cp.add_section(section)
    cp.set(section, key, value)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        cp.write(f, space_around_delimiters=False)

set_key(f"{home}/.config/gtk-3.0/settings.ini", "Settings", "gtk-icon-theme-name", theme)
set_key(f"{home}/.config/gtk-4.0/settings.ini", "Settings", "gtk-icon-theme-name", theme)
set_key(f"{home}/.config/kdeglobals", "Icons", "Theme", theme)
PY

# Live signal for running GTK/Qt apps (same idiom as switchwall.sh). Best-effort:
# absent schema (e.g. CI) must not fail the apply - the ini writes already stuck.
gsettings set org.gnome.desktop.interface icon-theme "$id" 2>/dev/null || true

echo "$id"
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x dots/.config/quickshell/ii/scripts/icons/apply-icon-theme.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 dots/.config/quickshell/ii/tests/test_icon_theme_apply.py`
Expected: `OK` (4 tests).

- [ ] **Step 6: Register the test in the suite**

In `tests/run_tests.sh`, after the icon-scanner block from Task 2, add:

```bash
echo "Running icon theme apply tests..."
if ! python3 "$SCRIPT_DIR/test_icon_theme_apply.py"; then
    echo "Icon theme apply tests failed."
    exit 1
fi
```

- [ ] **Step 7: Commit**

```bash
git add dots/.config/quickshell/ii/scripts/icons/apply-icon-theme.sh \
  dots/.config/quickshell/ii/tests/test_icon_theme_apply.py \
  dots/.config/quickshell/ii/tests/run_tests.sh
git commit -m "feat(icons): add system-wide icon-theme apply script + tests"
```

---

## Task 4: Register script paths in Directories.qml

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/common/Directories.qml` (near line 49-50)

- [ ] **Step 1: Add the two paths**

After `aiTranslationScriptPath` (line 49), add:

```qml
    property string iconThemeScanScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/icons/scan-icon-themes.py`)
    property string iconThemeApplyScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/icons/apply-icon-theme.sh`)
```

- [ ] **Step 2: Verify load**

Run: `cd dots/.config/quickshell/ii && QT_QPA_PLATFORM=offscreen ./tests/run_tests.sh 2>&1 | tail -3`
Expected: `All tests passed successfully!`

- [ ] **Step 3: Commit**

```bash
git add dots/.config/quickshell/ii/modules/common/Directories.qml
git commit -m "feat(icons): register icon-theme script paths"
```

---

## Task 5: IconThemes.qml detection service

**Files:**
- Create: `dots/.config/quickshell/ii/services/IconThemes.qml`
- Modify: `dots/.config/quickshell/ii/services/qmldir` (register the singleton)

- [ ] **Step 1: Confirm the qmldir singleton pattern**

Run: `grep -n "WallpaperEngine" dots/.config/quickshell/ii/services/qmldir`
Expected: a line like `singleton WallpaperEngine 1.0 WallpaperEngine.qml`. Mirror it for `IconThemes`.

- [ ] **Step 2: Write the service**

Create `services/IconThemes.qml` (mirrors `WallpaperEngine.qml`'s scanner+Process shape):

```qml
pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// Enumerates installed icon themes (via scripts/icons/scan-icon-themes.py) and
// exposes them for the icon-pack selector. Detection lives in the python scanner
// so it is unit-testable; this singleton just runs it and parses the JSON.
Singleton {
    id: root

    property var themes: []
    property bool loading: false
    readonly property bool available: themes.length > 0

    // The theme the shell/system is currently set to. When the config override
    // is empty we fall back to the live gsettings value so the grid can still
    // mark an active card.
    readonly property string activeId: Config.options.appearance.iconTheme

    signal refreshed()

    function load() {
        if (scanProcess.running) return;
        root.loading = true;
        scanProcess.command = ["python3", Directories.iconThemeScanScriptPath];
        scanProcess.running = true;
    }

    // Apply a theme by id: run the system-wide apply script, then (on success)
    // record it in config and relaunch the shell so its own icons update. The id
    // is validated again inside the script; here we only pass known ids from the
    // scanned list.
    function apply(themeId) {
        if (applyProcess.running) return;
        applyProcess.pendingId = themeId;
        applyProcess.command = [Directories.iconThemeApplyScriptPath, themeId];
        applyProcess.running = true;
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.themes = Array.isArray(parsed) ? parsed : [];
                } catch (e) {
                    root.themes = [];
                }
            }
        }
        onExited: exitCode => {
            root.loading = false;
            root.refreshed();
        }
    }

    Process {
        id: applyProcess
        property string pendingId: ""
        onExited: exitCode => {
            if (exitCode === 0) {
                Config.options.appearance.iconTheme = applyProcess.pendingId;
                // The shell's Qt icon theme is fixed at process launch, so a QML
                // reload will not adopt it - relaunch the process. Double-forked
                // via execDetached so it outlives the shell it kills.
                Quickshell.execDetached(["bash", "-c",
                    "sleep 0.3; qs kill >/dev/null 2>&1; qs -c ii -d >/dev/null 2>&1 &"]);
            }
            applyProcess.pendingId = "";
        }
    }

    Component.onCompleted: root.load()
}
```

- [ ] **Step 3: Register the singleton**

In `services/qmldir`, add (alphabetically near the others):

```
singleton IconThemes 1.0 IconThemes.qml
```

- [ ] **Step 4: Verify load (no QML errors)**

Run: `cd /home/xephy/.config/quickshell/ii && cp -r /home/xephy/dev/imi-unify/dots/.config/quickshell/ii/services/IconThemes.qml services/ && cp /home/xephy/dev/imi-unify/dots/.config/quickshell/ii/services/qmldir services/ && cp /home/xephy/dev/imi-unify/dots/.config/quickshell/ii/modules/common/Directories.qml modules/common/ && timeout 12 qs -c ii 2>&1 | grep -iE "IconThemes|error|Unable to assign" | head; echo done`
Expected: no `error`/`Unable to assign` lines mentioning IconThemes; `done` prints.

- [ ] **Step 5: Commit**

```bash
git add dots/.config/quickshell/ii/services/IconThemes.qml dots/.config/quickshell/ii/services/qmldir
git commit -m "feat(icons): add IconThemes detection service"
```

---

## Task 6: IconPackSelector.qml preview grid

**Files:**
- Create: `dots/.config/quickshell/ii/modules/ii/settings/pages/IconPackSelector.qml`

Follow the existing settings-widget imports (see `InterfaceConfig.qml:1-7`) and reuse `ContentSubsection`, `StyledText`, `RippleButton`, `MaterialSymbol`, `Appearance.*` tokens.

- [ ] **Step 1: Write the grid**

Create `modules/ii/settings/pages/IconPackSelector.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A grid of icon-theme cards. Each card previews a few real sample icons pulled
// straight from that theme's directory (by file path), so a theme that is not
// the active one still previews correctly, then applies it on click.
ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: Appearance.spacing.space50

    StyledText {
        text: Translation.tr("Icon pack")
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer1
    }

    StyledText {
        visible: !IconThemes.available
        text: IconThemes.loading
            ? Translation.tr("Scanning icon themes…")
            : Translation.tr("No icon themes found.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: Appearance.spacing.space50
        rowSpacing: Appearance.spacing.space50

        Repeater {
            model: IconThemes.themes
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool isActive: modelData.id === IconThemes.activeId
                Layout.fillWidth: true
                implicitHeight: cardCol.implicitHeight + Appearance.spacing.space100 * 2
                radius: Appearance.rounding.normal
                color: cardArea.containsMouse
                    ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                border.width: card.isActive
                    ? Appearance.borderWidth.emphasis : Appearance.borderWidth.standard
                border.color: card.isActive
                    ? Appearance.colors.colPrimary : "transparent"

                MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: IconThemes.apply(card.modelData.id)
                }

                ColumnLayout {
                    id: cardCol
                    anchors.centerIn: parent
                    width: parent.width - Appearance.spacing.space100 * 2
                    spacing: Appearance.spacing.space50

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Appearance.spacing.space25
                        Repeater {
                            model: card.modelData.sampleIcons
                            delegate: Image {
                                required property string modelData
                                source: "file://" + modelData
                                sourceSize.width: 32
                                sourceSize.height: 32
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Appearance.spacing.space25
                        MaterialSymbol {
                            visible: card.isActive
                            text: "check_circle"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: card.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.maximumWidth: card.width - Appearance.spacing.space150
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify color/token names exist**

Run: `grep -nE "colLayer2Hover|colSubtext|colLayer2\b|space50|space25" dots/.config/quickshell/ii/modules/common/Appearance.qml | head`
Expected: matches for each token used. If any token name differs, replace with the nearest real one from `Appearance.qml` (e.g. use `colLayer1Hover`/`colOnLayer2` equivalents) before continuing.

- [ ] **Step 3: Commit**

```bash
git add dots/.config/quickshell/ii/modules/ii/settings/pages/IconPackSelector.qml
git commit -m "feat(icons): add icon-pack preview grid widget"
```

---

## Task 7: Host the selector in the Interface settings page

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/ii/settings/pages/InterfaceConfig.qml`

- [ ] **Step 1: Add a section**

Add a new `ContentSection` (matching the existing ones in the file, e.g. around the app-icons area near line 285-297). Use the file's existing `ContentSection`/`ContentSubsection` idiom:

```qml
        ContentSection {
            title: Translation.tr("Icon pack")
            icon: "apps"

            IconPackSelector {
                Layout.fillWidth: true
            }
        }
```

Place it after the closing brace of the section that contains "Tint app icons" (the dock subsection ends near line 296). `IconPackSelector.qml` is in the same directory, so no import is needed.

- [ ] **Step 2: Deploy to live + verify load**

Run:
```bash
D=/home/xephy/.config/quickshell/ii; S=/home/xephy/dev/imi-unify/dots/.config/quickshell/ii
cp $S/modules/ii/settings/pages/IconPackSelector.qml $D/modules/ii/settings/pages/
cp $S/modules/ii/settings/pages/InterfaceConfig.qml $D/modules/ii/settings/pages/
cp $S/modules/common/Config.qml $D/modules/common/
timeout 12 qs -c ii 2>&1 | grep -iE "InterfaceConfig|IconPackSelector|error|Unable to assign" | head; echo done
```
Expected: no error lines; `done` prints.

- [ ] **Step 3: Run the test suite**

Run: `cd dots/.config/quickshell/ii && QT_QPA_PLATFORM=offscreen ./tests/run_tests.sh 2>&1 | tail -3`
Expected: `All tests passed successfully!`

- [ ] **Step 4: Commit**

```bash
git add dots/.config/quickshell/ii/modules/ii/settings/pages/InterfaceConfig.qml
git commit -m "feat(icons): surface the icon-pack selector in Interface settings"
```

---

## Task 8: Manual verification + QS_ICON_THEME fallback decision

This task is not automatable (needs the live compositor + a real restart). Do it by hand and only add the fallback if needed.

- [ ] **Step 1: Full deploy + restart the shell**

Copy all changed files to `~/.config/quickshell/ii` (services, modules, scripts, Config, Directories, qmldir), then fully restart: `qs kill; qs -c ii -d &`.

- [ ] **Step 2: Open Settings → Interface → Icon pack**

Confirm: the grid lists installed themes, each card shows real sample icons, the current theme is marked active.

- [ ] **Step 3: Pick a different theme**

Confirm: GTK apps update within a second (open a GTK app or watch one already open), the shell relaunches, and after relaunch the shell's own app icons (bar/dock/launcher) reflect the new theme.

- [ ] **Step 4: Decide the fallback**

If after the restart the shell's icons did NOT change (only external apps did), the shell is not following kdeglobals/gsettings via its platform theme. In that case:
- Change the relauncher in `IconThemes.qml` (Task 5) to export the theme:
  `"sleep 0.3; qs kill >/dev/null 2>&1; QS_ICON_THEME=" + Quickshell.execDetached-safe-quoted-id + " qs -c ii -d …"`
  — build the command as an argv list, not a spliced string (pass the id as an
  env entry via a small wrapper, consistent with the security rule).
- And make the normal Hyprland launch of the shell read `Config.options.appearance.iconTheme` and export `QS_ICON_THEME` so the choice survives a compositor restart.

If the shell DID follow after restart, no fallback is needed — note that in the commit message and skip.

- [ ] **Step 5: Commit any fallback changes (only if made)**

```bash
git add -A
git commit -m "fix(icons): export QS_ICON_THEME so the shell follows the chosen pack"
```

---

## Verification (whole feature)

- After each code task: `cd dots/.config/quickshell/ii && QT_QPA_PLATFORM=offscreen ./tests/run_tests.sh` stays green.
- Python units (`test_scan_icon_themes.py`, `test_icon_theme_apply.py`) cover the scanner and the apply script, including injection/traversal rejection.
- QML has no rendered-visual auto-test (repo convention); Task 8 is the manual gate.
- Do not push until the user explicitly asks (standing rule).

## Commit strategy

One commit per task as written above (config, scanner+test, apply+test, directories, service, grid widget, settings wiring, optional fallback). Keeps each change small and revertable. Follow the repo's `feat(...)`/`fix(...)` convention; no agent attribution in commit messages.
