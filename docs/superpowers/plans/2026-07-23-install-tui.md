# Install TUI (+ qs-wallpaperengine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the absorbed dots-hyprland installer into the Immaterial Impulse plug-and-play installer: a whiptail TUI over the existing multi-distro pipeline, a runtime-only config deploy, an optional qs-wallpaperengine build, and an illogical→immaterial migration.

**Architecture:** Implements `2026-07-23-install-tui-design.md`. Wrap `sdata/subcmd-install/*`; do not rewrite per-distro dep logic. The shell is launched by Hyprland as `qs -c ii`, so enabling Wallpaper Engine is purely a PATH swap of the `quickshell` binary. Bash + whiptail; Python `unittest` for the testable filter/migration logic (repo test style).

**Tech Stack:** bash, whiptail, rsync, `secret-tool`-free (keyring done in B), Python unittest, the `XephyLon/qs-wallpaperengine` build (`bootstrap.sh`).

**Working dir:** `~/dev/imi-unify` on `feat/immaterial-impulse`. Repo root has `setup`, `sdata/`, `dots/`.

---

## File structure

- `sdata/subcmd-install/3.files.sh` — modify: add the runtime-only exclude to the `~/.config/quickshell/ii` sync (C2).
- `sdata/lib/deploy-exclude.txt` — new: the single source of excluded dev paths.
- `sdata/subcmd-install/4.wallpaperengine.sh` — new: optional WE build/install (C3/D).
- `sdata/subcmd-install/tui.sh` — new: whiptail menu (C1/C5), maps choices to flags/env.
- `sdata/lib/migrate-existing.sh` — new: detect + transition an illogical-impulse install (C4).
- `sdata/tests/test_deploy_exclude.py`, `sdata/tests/test_migrate_detect.py` — new tests.
- `setup` — modify: no-arg invocation opens the TUI.

---

## Task 1: Runtime-only deploy exclude (C2)

**Files:**
- Create: `sdata/lib/deploy-exclude.txt`
- Create: `sdata/tests/test_deploy_exclude.py`
- Modify: `sdata/subcmd-install/3.files.sh`

- [ ] **Step 1: Write the exclude list**

`sdata/lib/deploy-exclude.txt` (rsync filter patterns, one per line):
```
tests/
docs/
screenshots/
AGENT.md
CONTRIBUTING.md
PLUGINS.md
PLUGIN_DESIGN_SYSTEM.md
README.md
.qmlformat.ini
.gitignore
*RuntimeTest.qml
DesignSystemCompile.qml
```

- [ ] **Step 2: Write the failing test**

`sdata/tests/test_deploy_exclude.py`:
```python
#!/usr/bin/env python3
import subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # sdata/
REPO = ROOT.parent                                   # repo root
EXCLUDE = ROOT / "lib/deploy-exclude.txt"
SRC = REPO / "dots/.config/quickshell/ii"


class DeployExcludeTests(unittest.TestCase):
    def test_dev_files_excluded_runtime_kept(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / "ii"
            subprocess.run(
                ["rsync", "-a", f"--exclude-from={EXCLUDE}", f"{SRC}/", f"{dest}/"],
                check=True,
            )
            # runtime present
            self.assertTrue((dest / "shell.qml").is_file())
            self.assertTrue((dest / "modules").is_dir())
            self.assertTrue((dest / "scripts/migrate-config-dir.sh").is_file())
            # dev excluded
            self.assertFalse((dest / "tests").exists())
            self.assertFalse((dest / "docs").exists())
            self.assertFalse((dest / "AGENT.md").exists())
            self.assertFalse((dest / "DesignSystemCompile.qml").exists())
            self.assertFalse(any(dest.glob("*RuntimeTest.qml")))
```

- [ ] **Step 3: Run it — verify FAIL** (exclude file / behavior not wired)

Run: `cd sdata && python3 tests/test_deploy_exclude.py -v`
Expected: FAIL until `deploy-exclude.txt` exists (Step 1 fixes the file; this test exercises rsync directly so it passes once the file is written — run again).

- [ ] **Step 4: Wire the exclude into the real deploy**

In `sdata/subcmd-install/3.files.sh`, find the `rsync` that syncs
`dots/.config/quickshell` (the `rsync_dir`/`rsync -a` for the quickshell dir) and
add `--exclude-from="${REPO_ROOT}/sdata/lib/deploy-exclude.txt"` to it. If the
active path is the legacy `install_dir__sync` in `3.files-legacy.sh`, add the
same `--exclude-from` there. Keep the listfile bookkeeping intact.

- [ ] **Step 5: Run the test — verify PASS**

Run: `cd sdata && python3 tests/test_deploy_exclude.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add sdata/lib/deploy-exclude.txt sdata/tests/test_deploy_exclude.py sdata/subcmd-install/3.files.sh
git commit -m "install: deploy runtime-only config, exclude dev/test/doc files (C2)"
```

---

## Task 2: Migration detection + transition (C4)

**Files:**
- Create: `sdata/lib/migrate-existing.sh`
- Create: `sdata/tests/test_migrate_detect.py`

- [ ] **Step 1: Write the failing test** (detection logic is unit-testable via an injected query command)

`sdata/tests/test_migrate_detect.py`:
```python
#!/usr/bin/env python3
import subprocess, unittest
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / "lib/migrate-existing.sh"


def run(installed_list):
    # The script reads installed packages from $IMI_PKG_QUERY_CMD output.
    fake = f"printf '%s\\n' {installed_list}"
    return subprocess.run(
        ["bash", "-c", f'IMI_PKG_QUERY_CMD="{fake}" source "{LIB}"; has_legacy_packages && echo YES || echo NO'],
        capture_output=True, text=True,
    ).stdout.strip()


class MigrateDetectTests(unittest.TestCase):
    def test_detects_legacy(self):
        self.assertEqual(run("illogical-impulse-basic illogical-impulse-audio foo"), "YES")

    def test_no_legacy(self):
        self.assertEqual(run("immaterial-impulse-basic bar"), "NO")
```

- [ ] **Step 2: Run — verify FAIL**

Run: `cd sdata && python3 tests/test_migrate_detect.py -v`
Expected: FAIL (script missing).

- [ ] **Step 3: Write the migration lib**

`sdata/lib/migrate-existing.sh`:
```bash
#!/usr/bin/env bash
# migrate-existing.sh — detect + transition a prior illogical-impulse install.
# Sourced by the installer. Package query is injectable for testing.

: "${IMI_PKG_QUERY_CMD:=pacman -Qq}"   # per-distro caller overrides this

has_legacy_packages() {
    eval "$IMI_PKG_QUERY_CMD" 2>/dev/null | grep -q '^illogical-impulse-'
}

# Print the legacy package basenames (audio, basic, ...) for the caller to map
# onto immaterial-impulse-* and remove.
legacy_packages() {
    eval "$IMI_PKG_QUERY_CMD" 2>/dev/null | grep '^illogical-impulse-'
}
```

- [ ] **Step 4: Run — verify PASS**

Run: `cd sdata && python3 tests/test_migrate_detect.py -v`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire detection into the install flow**

In `sdata/subcmd-install/1.deps-router.sh` (or `2.setups.sh`), source
`migrate-existing.sh` and, if `has_legacy_packages`, prompt (via whiptail when
interactive, else default-no) to install the `immaterial-impulse-*` set and
remove the matching `illogical-impulse-*` packages. Config-dir migration is
already handled at runtime by `migrate-config-dir.sh` (built in B) — do NOT
duplicate it here; only add an `install_file__auto_backup` of an existing
`~/.config/quickshell/ii` before the deploy overwrites it.

- [ ] **Step 6: Commit**

```bash
git add sdata/lib/migrate-existing.sh sdata/tests/test_migrate_detect.py sdata/subcmd-install/1.deps-router.sh
git commit -m "install: detect + offer transition of a prior illogical-impulse install (C4)"
```

---

## Task 3: qs-wallpaperengine optional build (C3 / D)

**Files:**
- Create: `sdata/subcmd-install/4.wallpaperengine.sh`
- Modify: per-distro dep lists to add WE build deps (gated).

- [x] **Step 1: Write the WE build/install step**

`sdata/subcmd-install/4.wallpaperengine.sh`:
```bash
#!/usr/bin/env bash
# 4.wallpaperengine.sh — OPTIONAL. Builds the patched quickshell (with the
# Quickshell.WallpaperEngine module) + linux-wallpaperengine, and installs it so
# `qs`/`quickshell` on PATH is the WE-capable build. No-op unless INSTALL_WE=1.
set -euo pipefail
[[ "${INSTALL_WE:-0}" == "1" ]] || { echo "[ImI] Wallpaper Engine: skipped."; exit 0; }

WE_REPO="${WE_REPO:-https://github.com/XephyLon/qs-wallpaperengine}"
WE_REF="${WE_REF:-main}"                       # pin in the real commit
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/immaterial-impulse/qs-wallpaperengine-build}"

rm -rf "$BUILD_DIR"
git clone --depth 1 --branch "$WE_REF" "$WE_REPO" "$BUILD_DIR"
cd "$BUILD_DIR"
bash ./bootstrap.sh                             # builds linux-wallpaperengine + patched quickshell

# Install the built quickshell so it shadows the distro one on PATH.
QS_BIN="$BUILD_DIR/build/quickshell/build2/src/quickshell"
sudo install -Dm755 "$QS_BIN" /usr/local/bin/quickshell
sudo ln -sf /usr/local/bin/quickshell /usr/local/bin/qs
echo "[ImI] Wallpaper Engine: installed custom quickshell to /usr/local/bin."
```
NOTE (resolved during implementation, against the actual `~/dev/qs-wallpaperengine`
repo): `bootstrap.sh` only clones+patches both upstreams and leaves its cmake
configure/build lines as *comments* ("Scaffold only" status) — the real script
runs those itself. The real working Quickshell build dir is `build2` (confirmed
via `launch-shell.sh`, the actual runtime launcher), not the `build` dir named
in bootstrap.sh's comments. `launch-shell.sh` also confirms the runtime
`LD_LIBRARY_PATH` need (WE's own `build/output` + `/opt/linux-wallpaperengine{,/lib}`),
so the install is a wrapper at `/usr/local/bin/quickshell` (+ `qs` symlink) that
sets `LD_LIBRARY_PATH` and execs the real binary in the cache dir, not a bare
copy. Also changed from the sketch's `rm -rf` + shallow clone to reusing an
existing `BUILD_DIR` across re-runs (fetch/checkout in place), so the nested
upstream builds can rebuild incrementally instead of from scratch every
install — bootstrap.sh's own `clone_at()` already assumes this idempotency.

- [x] **Step 2: Add gated WE build deps per distro**

Arch: exact `depends`/`makedepends` from linux-wallpaperengine's
`packaging/archlinux/PKGBUILD`. Fedora: the dnf list from its README's
"RHEL/Fedora-based systems" (Fedora 42) section. Gentoo and Nix: left as
marked TODO blocks — the upstream README has no Gentoo/Nix package lists, and
both distros' dep mechanisms here are a whole ebuild-overlay pipeline /
home-manager flake respectively, not ad-hoc package-manager calls, so atom/attr
names aren't confidently verifiable from this repo alone.

- [x] **Step 3: Hook it into the pipeline**

Added `bash ${SUBCMD_DIR}/4.wallpaperengine.sh` in `setup`'s `install)` case,
right after `3.files.sh` (config deploy). Run via `bash`, not `source` — the
step's own `exit 0` skip path would otherwise exit the whole `setup` process.

- [x] **Step 4: Verify (structure/dry-run — full build needs a build env)**

`bash -n sdata/subcmd-install/4.wallpaperengine.sh` passes.
`INSTALL_WE=0 bash sdata/subcmd-install/4.wallpaperengine.sh` prints
"[ImI] Wallpaper Engine: skipped." and exits 0. A real build is verified
manually in a VM/container (not attempted here — the FBO driver in
qs-wallpaperengine still has real TODOs per its own README's Status section).

- [x] **Step 5: Commit**

```bash
git add sdata/subcmd-install/4.wallpaperengine.sh sdata/dist-*/install-deps.sh
git commit -m "install: optional qs-wallpaperengine build + custom quickshell on PATH (C3/D)"
```

---

## Task 4: whiptail TUI (C1 + C5)

**Files:**
- Create: `sdata/subcmd-install/tui.sh`
- Modify: `setup` (no-arg → TUI)

- [ ] **Step 1: Write the TUI**

`sdata/subcmd-install/tui.sh` — a `whiptail --checklist` for components (Core
[on], Deps [on], Wallpaper Engine [off]) + a `whiptail --menu` fontset picker
over `ls dots-extra/fontsets` + an fcitx5 IME toggle. Map results to the env/flags
the existing steps read: set `INSTALL_WE=1` when WE is checked; set the
`--fontset <name>` / IME options `options.sh` already parses. Then exec the
existing install pipeline with those. Provide a `--help`/cancel path.

- [ ] **Step 2: Guard for non-interactive / missing whiptail**

If stdout isn't a TTY or `whiptail` is absent, print a hint and fall back to
`setup install` (the existing non-interactive path). This keeps CI/automation
working.

- [ ] **Step 3: Wire `setup` no-arg → TUI**

In `setup`, when invoked with no subcommand, run `sdata/subcmd-install/tui.sh`
instead of printing help. `setup install` and the other subcommands stay direct.

- [ ] **Step 4: Verify**

`bash -n sdata/subcmd-install/tui.sh sdata/../setup`. Non-interactively,
`printf '' | setup` (no TTY) falls back cleanly (doesn't hang). Interactive
menu behavior is verified manually.

- [ ] **Step 5: Commit**

```bash
git add sdata/subcmd-install/tui.sh setup
git commit -m "install: whiptail TUI menu — component + extras selection (C1/C5)"
```

---

## Task 5: Verification pass

- [ ] **Step 1: Runtime-only deploy is real**

Run the deploy against a temp dest (as in Task 1's test) and confirm
`~/.config/quickshell/ii`-shaped output has no `tests/`, `docs/`, `AGENT.md`,
`*RuntimeTest.qml`, `DesignSystemCompile.qml`, and does have `shell.qml`,
`modules/`, `scripts/migrate-config-dir.sh`.

- [ ] **Step 2: All new tests pass**

Run: `cd sdata && python3 tests/test_deploy_exclude.py && python3 tests/test_migrate_detect.py`

- [ ] **Step 3: Scripts are syntactically valid**

Run: `for f in sdata/subcmd-install/{tui,4.wallpaperengine}.sh sdata/lib/migrate-existing.sh setup; do bash -n "$f"; done`

- [ ] **Step 4: Non-interactive path unaffected**

Confirm `setup install` still routes through the existing steps (no TUI needed);
`INSTALL_WE=0` skips the WE build.

- [ ] **Step 5: Push**

```bash
git push gh feat/immaterial-impulse
```

---

## Self-review notes

- **Spec coverage:** C1→Task 4; C2→Task 1; C3/D→Task 3; C4→Task 2; C5→Task 4. All mapped.
- **Known soft spot:** Task 3's exact `bootstrap.sh` flow, built-binary path, and runtime-lib handling depend on the qs-wallpaperengine repo — the step says to read its README and adjust. A full WE build isn't unit-testable here; it's verified manually in a build env. The gate (`INSTALL_WE`) and skip path ARE tested.
- **No M1/M2 duplication:** the config-dir + keyring migrations were built in B; C only invokes/backs-up around them.
