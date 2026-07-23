# Rebrand to Immaterial Impulse (ImI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the fork's identity from `illogical-impulse`/`end4-pC` to Immaterial Impulse (ImI) across the unified tree, with safe one-time migrations so existing users keep their config and stored secrets.

**Architecture:** Implements `2026-07-23-rebrand-imi-design.md`. Runs on the A-unified tree (`dots/.config/quickshell/ii/` = theme; suite at root). Data dir `~/.config/illogical-impulse` → `~/.config/immaterial-impulse`; a startup migration moves an existing dir; keyring lookups fall back to the old attribute and lazily re-key. Mechanical rename sweeps are guarded by grep audits. Attribution to end-4 and real repo names are preserved.

**Tech Stack:** Quickshell/QML, bash scripts, Python `unittest` (repo's test style), Arch PKGBUILDs, `secret-tool` (libsecret).

**Working dir:** the unified clone (`~/dev/imi-unify`) on `feat/immaterial-impulse`. Theme prefix `D=dots/.config/quickshell/ii`.

---

## File structure

- `D/scripts/migrate-config-dir.sh` — **new**, one-time data-dir move (M1). Self-locating, idempotent. Testable in isolation like `presets.sh`.
- `D/modules/common/Directories.qml` — data-dir constant + calls the migration on init.
- `D/services/KeyringStorage.qml` — new keyring attribute/label + old-attribute fallback & lazy re-key (M2).
- `D/tests/test_config_migration.py` — **new**, M1 behavior test.
- `D/tests/test_keyring_migration.py` — **new**, M2 contract test.
- `sdata/dist-arch/immaterial-impulse-*/` — renamed package dirs + PKGBUILDs; `sdata/dist-arch/install-deps.sh`, `sdata/dist-arch/uninstall-deps.sh`, `sdata/deps-info.md`.
- Brand strings: `D/welcome.qml`, `D/README.md`, `D/AGENT.md`, `D/CONTRIBUTING.md`, `D/translations/*.json`.

---

## Task 1: Data-dir migration script (M1)

**Files:**
- Create: `dots/.config/quickshell/ii/scripts/migrate-config-dir.sh`
- Test: `dots/.config/quickshell/ii/tests/test_config_migration.py`

- [ ] **Step 1: Write the failing test**

```python
#!/usr/bin/env python3
import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATE = ROOT / "scripts/migrate-config-dir.sh"


class ConfigMigrationTests(unittest.TestCase):
    def _run(self, home):
        subprocess.run(["bash", str(MIGRATE)],
                       env=dict(os.environ, HOME=str(home)), check=True)

    def test_moves_old_dir_when_new_absent(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"marker": 1}')
            self._run(home)
            new = home / ".config/immaterial-impulse"
            self.assertTrue(new.is_dir())
            self.assertEqual((new / "config.json").read_text(), '{"marker": 1}')
            self.assertFalse(old.exists())

    def test_noop_when_new_exists(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            (home / ".config/illogical-impulse").mkdir(parents=True)
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            (new / "config.json").write_text('{"keep": 1}')
            self._run(home)
            self.assertEqual((new / "config.json").read_text(), '{"keep": 1}')
            self.assertTrue((home / ".config/illogical-impulse").exists())

    def test_noop_when_nothing_to_migrate(self):
        with tempfile.TemporaryDirectory() as d:
            self._run(Path(d))  # must exit 0, create nothing


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dots/.config/quickshell/ii && python3 tests/test_config_migration.py -v`
Expected: FAIL — `migrate-config-dir.sh` does not exist.

- [ ] **Step 3: Write the migration script**

```bash
#!/usr/bin/env bash
# migrate-config-dir.sh — one-time move of the ImI data dir from the old
# illogical-impulse name. Idempotent: no-op if the new dir exists or the old
# one is absent.
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
old="$config_home/illogical-impulse"
new="$config_home/immaterial-impulse"

if [[ -d "$new" ]]; then
    exit 0            # already migrated / fresh install
fi
if [[ ! -d "$old" ]]; then
    exit 0            # nothing to migrate
fi

mv "$old" "$new"
echo "[ImI] migrated config dir: $old -> $new" >&2
```

- [ ] **Step 4: Make it executable and run the test**

Run: `chmod +x dots/.config/quickshell/ii/scripts/migrate-config-dir.sh && cd dots/.config/quickshell/ii && python3 tests/test_config_migration.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add dots/.config/quickshell/ii/scripts/migrate-config-dir.sh dots/.config/quickshell/ii/tests/test_config_migration.py
git commit -m "feat(migration): one-time config-dir move illogical-impulse -> immaterial-impulse (M1)"
```

---

## Task 2: Point Directories at the new dir + run M1 on startup

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/common/Directories.qml`

- [ ] **Step 1: Change the data-dir constant (line 33)**

Replace:
```qml
    property string shellConfig: FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse`)
```
with:
```qml
    property string shellConfig: FileUtils.trimFileProtocol(`${Directories.config}/immaterial-impulse`)
```

- [ ] **Step 2: Run the migration before the dir is read**

In `Directories.qml`'s `Component.onCompleted` (the "Cleanup on init" block), add as the FIRST statement, before the `mkdir` calls:
```qml
        Quickshell.execDetached(["bash", Quickshell.shellPath("scripts/migrate-config-dir.sh")])
```
(Verify `Quickshell` is already imported in this file — it is, for `execDetached`/`shellPath`. If not, add `import Quickshell`.)

- [ ] **Step 3: Verify the constant resolves**

Run: `grep -n "immaterial-impulse" dots/.config/quickshell/ii/modules/common/Directories.qml`
Expected: the `shellConfig` line shows `immaterial-impulse`; no `illogical-impulse` remains in this file.

- [ ] **Step 4: Commit**

```bash
git add dots/.config/quickshell/ii/modules/common/Directories.qml
git commit -m "feat(config): shellConfig -> ~/.config/immaterial-impulse, run M1 on init"
```

---

## Task 3: Data-dir path sweep across scripts

Scripts hardcode `.config/illogical-impulse`. They contain no attribution prose, so a blanket rename of the token is safe here. Prose files (README/AGENT/CONTRIBUTING) are handled in Task 6.

**Files:** every non-prose file under `dots/.config/quickshell/ii/` that references the path.

- [ ] **Step 1: List the target files (exclude prose + the migration/tests already done)**

Run:
```bash
cd dots/.config/quickshell/ii
grep -rIl "illogical-impulse" . | grep -vE "\.md$|/tests/test_(config|keyring)_migration\.py$|scripts/migrate-config-dir\.sh$"
```
Expected: a list of `scripts/**`, `services/**`, `modules/**`, `tests/**`, `translations/**` (translations handled in Task 6 — exclude `.json` here too if the hit is a brand string, keep if a path).

- [ ] **Step 2: Rewrite the path token in those files**

```bash
cd dots/.config/quickshell/ii
grep -rIl "illogical-impulse" . \
  | grep -vE "\.md$|\.json$|tests/test_(config|keyring)_migration\.py$|scripts/migrate-config-dir\.sh$" \
  | xargs sed -i 's/illogical-impulse/immaterial-impulse/g'
```

- [ ] **Step 3: Verify no path refs remain in code**

Run: `grep -rIn "illogical-impulse" scripts services modules tests`
Expected: **empty** (all code path refs now `immaterial-impulse`; keyring handled next; prose/translations later).

- [ ] **Step 4: Run the QML + preset tests**

Run: `./tests/run_tests.sh && python3 tests/test_presets.py -v`
Expected: all pass (paths still resolve; the fake-HOME preset test uses `illogical-impulse` for the *config_dir* it creates — update those two literals to `immaterial-impulse` so it matches `presets.sh`'s `CONFIG_DIR`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: rename data-dir path illogical-impulse -> immaterial-impulse (scripts/services/modules/tests)"
```

---

## Task 4: Keyring rename + lazy re-key (M2)

**Files:**
- Modify: `dots/.config/quickshell/ii/services/KeyringStorage.qml` (lines 24, 32, and the lookup/store logic)
- Test: `dots/.config/quickshell/ii/tests/test_keyring_migration.py`

- [ ] **Step 1: Write the contract test**

```python
#!/usr/bin/env python3
import unittest
from pathlib import Path

SRC = (Path(__file__).resolve().parents[1] / "services/KeyringStorage.qml").read_text()


class KeyringMigrationTests(unittest.TestCase):
    def test_new_attribute_is_immaterial_impulse(self):
        self.assertIn('"application": "immaterial-impulse"', SRC)
        self.assertNotIn('"application": "illogical-impulse"', SRC)

    def test_label_rebranded(self):
        self.assertIn("Immaterial Impulse", SRC)

    def test_falls_back_to_old_attribute(self):
        # a legacy lookup path must still reference the old application id
        self.assertIn("illogical-impulse", SRC)  # only survives as the fallback id

    def test_rekeys_after_fallback_hit(self):
        self.assertIn("legacyLookup", SRC)  # fallback+re-store helper exists


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd dots/.config/quickshell/ii && python3 tests/test_keyring_migration.py -v`
Expected: FAIL (attribute still `illogical-impulse`, no `legacyLookup`).

- [ ] **Step 3: Implement the rename + fallback**

In `KeyringStorage.qml`:
- Line 24: `"application": "illogical-impulse",` → `"application": "immaterial-impulse",`
- Line 32: `.arg("illogical-impulse")` → `.arg("Immaterial Impulse")`
- Add a constant for the legacy id and a fallback lookup used when the primary lookup misses. Concretely, where the code looks a secret up by `application=immaterial-impulse` and gets nothing, retry with `application=illogical-impulse`; on a hit, re-store under the new attribute and return it. Name the helper `legacyLookup`. Follow the file's existing `secret-tool lookup`/`store` process pattern (see line 80). The old id lives only in this fallback:

```qml
    readonly property string legacyApplication: "illogical-impulse"
    // ... in the lookup flow, when the immaterial-impulse lookup returns empty:
    //   run: secret-tool lookup application <legacyApplication> <key...>
    //   if non-empty: secret-tool store ... application immaterial-impulse ... (re-key), then use it.
    function legacyLookup(/* key args */) { /* ... */ }
```

- [ ] **Step 4: Run the contract test**

Run: `cd dots/.config/quickshell/ii && python3 tests/test_keyring_migration.py -v`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add dots/.config/quickshell/ii/services/KeyringStorage.qml dots/.config/quickshell/ii/tests/test_keyring_migration.py
git commit -m "feat(keyring): rebrand attribute + fall back to old id and lazily re-key (M2)"
```

---

## Task 5: Rename the dependency packages

**Files:** `sdata/dist-arch/illogical-impulse-*/` (dirs + PKGBUILDs), `sdata/dist-arch/install-deps.sh`, `sdata/dist-arch/uninstall-deps.sh`, `sdata/dist-arch/previous_dependencies.conf`, `sdata/deps-info.md`.

- [ ] **Step 1: Rename the package directories (git mv, preserves history)**

```bash
cd sdata/dist-arch
for d in illogical-impulse-*/; do
  git mv "$d" "immaterial-impulse-${d#illogical-impulse-}"
done
```

- [ ] **Step 2: Rewrite pkgnames, inter-package deps, and referencing files**

```bash
cd sdata
grep -rIl "illogical-impulse-" . | xargs sed -i 's/illogical-impulse-/immaterial-impulse-/g'
```

- [ ] **Step 3: Verify package consistency**

Run:
```bash
cd sdata/dist-arch
grep -rn "^pkgname" immaterial-impulse-*/PKGBUILD | grep -c immaterial-impulse   # every pkgname renamed
grep -rn "illogical-impulse-" .                                                  # want EMPTY
```
Expected: pkgname count == number of packages; second grep empty. Spot-check one PKGBUILD's `depends=(... immaterial-impulse-...)` resolves to a package that now exists.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "packaging: rename illogical-impulse-* dep packages to immaterial-impulse-*"
```

---

## Task 6: Brand strings + README supersede rewrite

**Files:** `D/welcome.qml`, `D/README.md`, `D/AGENT.md`, `D/CONTRIBUTING.md`, `D/translations/*.json`.

- [ ] **Step 1: welcome.qml title**

`dots/.config/quickshell/ii/welcome.qml:31`: `Translation.tr("illogical-impulse Welcome")` → `Translation.tr("Immaterial Impulse Welcome")`.

- [ ] **Step 2: README — title, identity, supersede rewrite; KEEP attribution**

In `dots/.config/quickshell/ii/README.md`:
- Line 7 title `# 💠 end4-pC` → `# 💠 Immaterial Impulse`.
- Line 46 — rewrite the coexist claim. Replace "manages its own configuration folder independently — it does **not** overwrite ... requires illogical-impulse to be installed and running." with a supersede statement: ImI ships the whole suite and installs to `~/.config/quickshell/ii` + `~/.config/immaterial-impulse`, replacing a prior illogical-impulse install rather than coexisting.
- Any `~/.config/illogical-impulse` path in prose → `~/.config/immaterial-impulse`.
- **KEEP** line 9's "fork of [illogical-impulse](...end-4...)" attribution and line 120's credits and all `github.com/end-4/dots-hyprland` links.

- [ ] **Step 3: AGENT.md — description + supersede; keep lineage**

`dots/.config/quickshell/ii/AGENT.md`: line 9 "`end4-pC` is a Quickshell shell configuration" → "`Immaterial Impulse` (ImI) is a Quickshell shell configuration". Update the coexist/`~/.config/quickshell/end4-pC`-drop-in framing to the ImI supersede + `~/.config/quickshell/ii`. **KEEP** the fork-chain lines (13,14,17,21) — they name real repos (`pctrade/end4-pC`) and the accurate lineage.

- [ ] **Step 4: CONTRIBUTING.md — any remaining data-dir path prose** → `immaterial-impulse`; keep repo names.

- [ ] **Step 5: Translations**

```bash
cd dots/.config/quickshell/ii
grep -rIln "llogical" translations/
```
For each hit, update the string only where it is ImI's own name (e.g. the "Welcome" title), not where a translation credits the origin. Edit the JSON values by hand (small set).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs: rebrand strings to Immaterial Impulse; README/AGENT coexist -> supersede (keep attribution)"
```

---

## Task 7: Full verification audit

- [ ] **Step 1: illogical-impulse only survives as attribution/lineage**

Run: `grep -rIn "illogical-impulse" . | grep -v '\.git/'`
Expected: **only** end-4 attribution, `github.com/end-4/dots-hyprland` links, credits, and the KeyringStorage `legacyApplication` fallback id. Zero of our own paths/packages/brand/keyring-primary.

- [ ] **Step 2: end4-pC only survives as real repo names / lineage**

Run: `grep -rIn "end4-pC" . | grep -v '\.git/'`
Expected: only `pctrade/end4-pC`, `XephyLon/end4-pC`, and lineage prose.

- [ ] **Step 3: Test suite green**

Run:
```bash
cd dots/.config/quickshell/ii
./tests/run_tests.sh
python3 tests/test_presets.py -v
python3 tests/test_config_migration.py -v
python3 tests/test_keyring_migration.py -v
```
Expected: all pass.

- [ ] **Step 4: Config constant + migration wired**

Run: `grep -n "immaterial-impulse" dots/.config/quickshell/ii/modules/common/Directories.qml`
Expected: `shellConfig` → `immaterial-impulse`; migration script invoked on init.

- [ ] **Step 5: Push**

```bash
git push gh feat/immaterial-impulse
```

---

## Self-review notes

- **Spec coverage:** naming map → Tasks 2/4/6; M1 → Tasks 1–2; M2 → Task 4; change/keep boundary → Tasks 3 (code-only sweep) + 6 (prose, attribution kept) + 7 (audit); upstream-divergence is inherent (no task). All spec sections map to a task.
- **Handoff to C:** the installer must (a) call/rely on M1 for existing users, (b) uninstall old `illogical-impulse-*` packages when installing `immaterial-impulse-*`, (c) deploy to `~/.config/quickshell/ii` + `~/.config/immaterial-impulse`, (d) re-point About.qml's stubbed update action. Recorded here, built in C.
