# Plugin Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In-shell plugin store: curated registry index → browse/search UI in Settings → one-click install/upgrade through the existing hardened installer, with semver update badges.

**Architecture:** Static `index.json` in a dedicated registry repo (CI-generated from per-plugin JSON entries) consumed by a new `PluginStore.qml` singleton; installs delegate to the existing `install_plugin.py`, which learns `--upgrade` and a provenance sidecar. Full spec: `docs/superpowers/specs/2026-07-27-plugin-store-design.md` — read it before any task.

**Tech stack:** Quickshell QML (Material 3 Expressive, `Appearance.*` tokens), Python 3 (installer/validator, stdlib only), qmltestrunner + python contract tests via `./tests/run_tests.sh`.

**Repo:** `/home/xephy/dev/imi-unify`, shell root `dots/.config/quickshell/ii/`. All paths below relative to shell root unless stated. Conventions: `AGENT.md` (hard rules), granular commits, no agent attribution, no push until asked.

---

### Task 1: Installer `--upgrade` + provenance sidecar

**Files:**
- Modify: `scripts/plugins/install_plugin.py`
- Test: `tests/test_plugin_installer.py`

Requirements:
1. New optional CLI flag `--upgrade` (argv parsing is currently positional `<url> <root>`; keep positionals, add flag).
2. Without `--upgrade`: existing refuse-to-overwrite behavior unchanged.
3. With `--upgrade` and existing target dir: read `<target>/manifest.json`; it must parse as JSON and its `id` must equal the incoming plugin id, else abort with a clear error and leave the target untouched. Then stage + verify the new version exactly as today, and swap atomically:
   ```python
   backup = target.with_name(target.name + f".old-{os.getpid()}")
   os.rename(target, backup)
   try:
       os.replace(staged, target)
   except BaseException:
       os.rename(backup, target)
       raise
   shutil.rmtree(backup)
   ```
4. After every successful install/upgrade, write `<target>/.store.json`:
   ```json
   { "manifestUrl": "<the url argument>", "installedVersion": "<manifest version or null>", "installedAt": "<UTC ISO-8601>" }
   ```
   Written by the installer itself post-swap; package files can never claim the name (`safe_relative_path` already rejects dot-prefixed parts — do not weaken it).
5. Tests (extend `test_plugin_installer.py`, follow its existing local-HTTP-server/fixture style):
   - upgrade replaces an existing install and the new content is present
   - upgrade with mismatched existing `id` refuses and leaves the old install intact
   - upgrade with unparseable existing manifest refuses
   - fresh install without `--upgrade` onto existing dir still raises (regression)
   - `.store.json` exists after install with correct `manifestUrl` and `installedVersion`
   - a package declaring `.store.json` in `package.files` is rejected (pin the existing dot-prefix rule)

- [ ] Write failing tests, run `python3 tests/test_plugin_installer.py` (or via run_tests.sh) to see them fail
- [ ] Implement, re-run to green
- [ ] Run full `./tests/run_tests.sh`
- [ ] Commit `feat(plugins): installer upgrade path and install provenance sidecar`

### Task 2: Registry entry validator

**Files:**
- Create: `scripts/plugins/registry_validate.py`
- Test: `tests/test_registry_validate.py`

A stdlib-only module + CLI, shared verbatim with the future registry repo CI. API:

```python
def validate_entry(entry: dict) -> list[str]            # schema errors
def validate_filename(filename: str, entry: dict) -> list[str]
def cross_check(entry: dict, manifest: dict) -> list[str]  # entry vs fetched plugin manifest
```

Rules (spec §3.1/§3.3):
- Required: `id` (regex `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`), `name`, `description` (≤200 chars), `author`, `version` (plain `^\d+\.\d+\.\d+$`, no prerelease), `apiVersion` (int ≥1), `capabilities` (non-empty list of strings), `permissions` (list, subset of the six known: `process, network, filesystem_read, filesystem_write, settings_read, settings_write`), `manifestUrl`, `sourceUrl` (both `https://`).
- Optional typed: `dependencies` (list of str), `screenshot` (https), `icon` (str), `tags` (list of str), `featured` (bool), `minShellVersion` (plain semver).
- `screenshot` required when `capabilities` includes any of `desktop-widget, bar-widget, panel`.
- Warn-level (returned separately or prefixed `warning:`): `manifestUrl` containing `/main/` or `/master/` (should be tag/commit-pinned).
- `validate_filename`: must equal `<author>-<id>.json` lowercased-safe comparison? No — exact `f"{entry['author']}-{entry['id']}.json"`.
- `cross_check`: `id, name, version, apiVersion` equal; entry `capabilities`/`permissions` equal as sets to manifest's; manifest must contain `package.files`, every file entry must carry `sha256`; file count ≤64; `screenshot`/`manifestUrl`/every package file URL same origin (scheme+host) — reuse/port the origin logic from `install_plugin.py`.
- CLI: `python3 registry_validate.py entry.json [--manifest manifest.json]` → prints errors, exit 1 on any non-warning error. No network in v1 (CI fetches the manifest itself and passes `--manifest`).

- [ ] Failing tests first (fixture dicts inline in the test file), then implement to green
- [ ] `./tests/run_tests.sh`
- [ ] Commit `feat(plugins): registry entry validator shared with store registry CI`

### Task 3: PluginManager: apiVersion, upgrade entry point, provenance exposure

**Files:**
- Modify: `modules/common/plugins/PluginManager.qml`
- Test: `tests/test_openrgb_contract.py`-style pin not needed; extend `tests/tst_installed_manifest_state.qml` only if touched; primary coverage lands in Task 4.

Requirements:
1. `readonly property int apiVersion: 1` on the PluginManager singleton (the shell's plugin API level; manifests' `apiVersion` is checked against it by the store).
2. `function upgradeFromManifest(url)`: mirror of `installFromManifest` (`PluginManager.qml:102-116`) that passes `--upgrade` to the installer process and rescans on success. Same https-only client-side guard, same `installMessage` plumbing (distinct wording "Updated <id>").
3. Provenance: for each installed plugin, read `<dir>/.store.json` (sibling of the manifest FileView created in `PluginManager.qml:213-224` — add a second `FileView` per installed path, non-watching is fine) and inject the parsed object as `_store` on that plugin's manifest entry in `availablePlugins` (absent/unparseable sidecar ⇒ no `_store` key). Guard JSON.parse in try/catch.
4. Follow `AGENT.md` dynamic-QML rules (no nested Loaders in hosts; Repeater/FileView patterns as already used in the file). New singleton members only — no new module dirs, so hot reload applies.

- [ ] Implement; verify via `qs -c ii` load in the *dev* tree not required — rely on tests + Task 4's QML tests
- [ ] `./tests/run_tests.sh`
- [ ] Commit `feat(plugins): plugin API level, upgrade entry point, install provenance`

### Task 4: PluginStore service + logic double + tests

**Files:**
- Create: `services/PluginStore.qml`
- Create: `tests/imports/testservices/PluginStore.qml` (logic double)
- Modify: `tests/imports/testservices/qmldir` (add singleton line)
- Create: `tests/tst_plugin_store.qml`
- Create: `tests/test_plugin_store_contract.py`

Service (singleton, `pragma Singleton`, imports as in `services/OpenRgb.qml`):

State: `property var entries: []`, `readonly property bool fetching`, `property string lastError: ""`, `readonly property int updatesAvailable` (derived), `readonly property string indexUrl: "https://raw.githubusercontent.com/XephyLon/imi-plugin-registry/main/index.json"` (constant, https).

Pure functions (byte-identical in the double, pinned by the contract test — same pattern as `services/OpenRgb.qml` / `test_openrgb_contract.py::test_logic_double_is_in_sync`):

```js
// -1 / 0 / 1; dotted numeric segments, missing = 0; non-numeric segment
// falls back to string compare of that segment.
function compareVersions(a, b) {
    const as = String(a ?? "").split("."), bs = String(b ?? "").split(".");
    const n = Math.max(as.length, bs.length);
    for (let i = 0; i < n; i++) {
        const ra = as[i] ?? "0", rb = bs[i] ?? "0";
        const na = Number(ra), nb = Number(rb);
        if (Number.isFinite(na) && Number.isFinite(nb)) {
            if (na !== nb) return na < nb ? -1 : 1;
        } else if (ra !== rb) {
            return ra < rb ? -1 : 1;
        }
    }
    return 0;
}

// Returns { entries: [...], error: string|null }. Never throws.
// Drops malformed entries; rejects wrong index major version.
function parseIndex(text) { /* validate {version:1, plugins:[...]}; per entry
    require non-empty string id, name, version, manifestUrl starting with
    "https://"; coerce missing capabilities/permissions/tags to [];
    keep unknown fields */ }

// status: "installed" | "update" | "bundled" | "incompatible" | "available"
// installedMap: { id: { version, origin } }, bundledIds: [..],
// shellApi: int, shellVersion: "x.y.z"
function statusFor(entry, installedMap, bundledIds, shellApi, shellVersion) {
    if (bundledIds.includes(entry.id)) return "bundled";
    if ((entry.apiVersion ?? 1) > shellApi) return "incompatible";
    if (entry.minShellVersion && compareVersions(shellVersion, entry.minShellVersion) < 0) return "incompatible";
    const inst = installedMap[entry.id];
    if (!inst) return "available";
    return compareVersions(entry.version, inst.version) > 0 ? "update" : "installed";
}
```

I/O: `refresh()` runs a curl Process (`["curl", "-sfL", "--max-time", "15", "-o", tmpPath, indexUrl]` then atomic `mv` to `~/.cache/immaterial-impulse/plugin-store/index.json` — see `services/OnlineWallpapers.qml:107-131` for the Process/curl idiom and `Directories.qml` for cache paths; add a `plugin-store` cache dir entry if Directories has that pattern). On process success read the file (FileView or cat-collector) → `parseIndex` → `entries` / `lastError`. Cache file loaded once at startup for offline render. `refreshIfStale()`: fetch only if cache mtime older than 24h (stat via Process or FileView metadata) — called by the store page on open. `install(entry)` / `upgrade(entry)` delegate to `PluginManager.installFromManifest` / `upgradeFromManifest`. `installedMap` derived from `PluginManager.availablePlugins` (`_origin === "installed"`, version from manifest, `_store` presence marks store-managed). `bundledIds` derived from `_origin === "bundled"`. Shell version: read the same source the About page uses (find it; `VERSION` file).

Double: pure functions + property stubs only, no Process/Config (see `tests/imports/testservices/Tailscale.qml` for the shape).

`tst_plugin_store.qml`: compareVersions ordering table (1.2.0>1.1.9, 1.10.0>1.9.0, equal, missing segments, non-numeric fallback); parseIndex (valid fixture, garbage JSON, wrong version:2, malformed entries dropped while good ones survive, http:// manifestUrl dropped); statusFor all five statuses incl. minShellVersion gate.

`test_plugin_store_contract.py`: logic-double sync pin (reuse `_function_block` helper approach from `test_openrgb_contract.py`), indexUrl constant is https + raw.githubusercontent, service never uses `bash -c` with interpolated values, `curl` argv is a static list plus paths.

- [ ] Double + failing QML tests first, then service, then contract test
- [ ] `./tests/run_tests.sh`
- [ ] Commit `feat(plugins): PluginStore service - registry index, semver status, update counts`

### Task 5: Store UI + PluginsPage wiring

**Files:**
- Create: `modules/ii/settings/pages/PluginStorePage.qml`
- Modify: `modules/ii/settings/pages/PluginsPage.qml`
- Possibly modify: settings navigation host (find how `IconPackSelector.qml` is reached from InterfaceConfig — replicate that sub-page mechanism)

PluginsPage: top row button "Browse plugins" (icon `storefront`) with count badge when `PluginStore.updatesAvailable > 0`, navigating to the store page. Installed cards: show `version` next to name when present; when `PluginStore` reports status `update` for that id, an "Update" `RippleButtonWithIcon` calling `PluginStore.upgrade(entry)`.

PluginStorePage:
- Header: search `MaterialTextArea`/`ConfigTextArea` (contains-match on name+description+tags, case-insensitive), filter chips for capability (`desktop-widget`/`bar-widget`/`panel`) + "Installed", refresh button (`OpenRgb`-style disabled-while-fetching), `PluginStore.lastError` surfaced via `StyledText` when non-empty.
- List: `Repeater` over filtered+sorted entries (featured first, then name). Card per entry mirroring PluginsPage card visuals (`Rectangle` + `Appearance.colors.colLayer1`, rounding tokens): Material icon (`entry.icon`, fallback `extension`), name (+author "By X"), description, capability chips, permission chips (compact pills), screenshot as async `Image` (`asynchronous: true`, fixed slot `Layout.preferredHeight`, `fillMode: PreserveAspectCrop`, rounded clip; skip when no screenshot), action button by status: Install / Update / Installed (disabled) / "Needs newer shell" (disabled) / Bundled (disabled).
- Install/Update tap → confirm dialog (`WindowDialog` pattern, see `modules/ii/sidebarRight/wifiNetworks/WifiDialog.qml` and the uninstall dialog `modules/ii/settings/PluginUninstallDialog.qml` for hosting): plugin name, permission list with one-line human descriptions (`process` → "Can run system commands", `network` → "Can access the network", `filesystem_read/write` → "Can read/write your files", `settings_read/write` → "Can read/change shell settings"), external `dependencies` list, "Review the code" link opening `sourceUrl` via `Qt.openUrlExternally`, trust warning line, Cancel/Install buttons. Confirm → `PluginStore.install(entry)`; result toast via existing `PluginManager.installMessage` binding (as PluginsPage does).
- ALL registry-sourced strings rendered with `textFormat: Text.PlainText` — contract-tested.
- On page shown: `PluginStore.refreshIfStale()`.
- "Update all" button visible when ≥2 updates: sequential `upgrade()` calls (chain on installMessage/rescan completion, or simply iterate — installer runs are serialized by PluginManager's single process object; verify and match its behavior).
- M3 compliance per `docs/M3_GUIDELINES.md` + `AGENT.md` design rules; spacing via `Appearance.spacing.*`.

Verification: deploy changed files to `~/.config/quickshell/ii` (cp, then check live log `/run/user/1000/quickshell/by-id/*/log.log` for QML errors — new page file under existing module dir hot-reloads; if the page doesn't register, full restart: `pkill -f "quickshell -c ii"` alone, then separate `setsid -f qs -c ii`). Point `indexUrl`… do NOT: instead test rendering with the real (empty/404) URL — error path must render gracefully. Optionally drop a hand-made index.json into the cache path to see populated cards.

- [ ] Implement page + wiring
- [ ] `./tests/run_tests.sh` (lint_qml_* suites cover imports/module dirs)
- [ ] Deploy + live-log check + screenshot-free visual sanity (ask user to glance)
- [ ] Commit `feat(settings): plugin store page - browse, install, update` (+ separate commit if PluginsPage changes are sizable)

### Task 6: Registry repo scaffold

**Files (new local repo `/home/xephy/dev/imi-plugin-registry`, git init, NOT on GitHub yet):**
- `README.md` — what this is, index URL consumers use, link to shell repo docs
- `CONTRIBUTING.md` — submission rules verbatim from spec §3.4 (transparency rules, one plugin per PR, filename rule, reserved bundled ids list, review stance)
- `schema/registry-entry.schema.json` — JSON Schema mirroring `registry_validate.py` rules (documentation artifact; CI runs the python validator, not the schema)
- `plugins/.gitkeep`
- `index.json` — `{ "version": 1, "generatedAt": "<now>", "source": "official", "plugins": [] }`
- `scripts/registry_validate.py` — copied from shell repo with a header comment naming the canonical path (`dots/.config/quickshell/ii/scripts/plugins/registry_validate.py`) and "keep in sync"
- `scripts/generate_index.py` — reads `plugins/*.json`, validates each (import registry_validate), writes `index.json` deterministically (sorted by id)
- `.github/workflows/validate.yml` — PR: validate changed entries (schema + filename; cross-check via fetched manifest with curl + `--manifest`); push-to-main: regenerate `index.json` and commit if changed

- [ ] Scaffold, `git init`, initial commit `feat: registry scaffold - validation CI and empty index`
- [ ] Note to user: create GitHub repo `XephyLon/imi-plugin-registry` + push when ready (index URL in PluginStore.qml assumes it)

### Task 7: Docs + changelog

**Files:**
- Create: `docs/PLUGIN_STORE.md` — user guide (browse/install/update, trust model in plain words) + submitter guide (entry format, rules, PR flow) + maintainer notes (CI, index regeneration, validator sync)
- Modify: `docs/PLUGINS.md` — cross-reference store install alongside "Remote installation"; document `.store.json` sidecar and `--upgrade`
- Modify: `AGENT.md` — directory-map lines for the new service/page/scripts if the map lists siblings (check)
- Modify: `CHANGELOG.md` — Unreleased → Added entry

- [ ] Write, commit `docs: plugin store guide and cross-references`

---

## Execution notes

- Sequential tasks, one implementer subagent per task, two-stage review per subagent-driven-development. Tasks 1–2 are pure python — cheap model fine; Tasks 4–5 need QML pattern-following care.
- Full `./tests/run_tests.sh` after every task; suite currently 175 green.
- Deploy-to-live only in Task 5.
- Commits granular per task as listed; no push until user asks.
