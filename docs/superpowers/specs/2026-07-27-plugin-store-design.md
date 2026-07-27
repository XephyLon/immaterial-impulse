# Plugin Store — Design Spec

Status: draft for review
Date: 2026-07-27
Prior art studied: DankMaterialShell (danklinux.com/plugins, dms-plugin-registry) and
Noctalia (noctalia.dev/plugins, official-plugins + community-plugins). Findings that
shaped this design are inlined where relevant.

## 1. Goal & scope

An in-shell plugin store: browse a curated catalog of community plugins from
Settings → Plugins, see honest metadata (permissions, capabilities, screenshots)
before installing, install in one click through the existing hardened installer,
and get update badges + one-click upgrades for store-installed plugins.

**In scope (v1):** official registry (single source), in-shell browse/search/
install/update UI, semver-based update detection, installer upgrade path,
registry repo scaffold + CI validation + submission rules.

**Out of scope (v1), deliberately left room for:** website storefront (the index
is static JSON — a site can consume it later), multiple/custom registry sources
(index carries a `source` field from day one), popularity metrics (DMS runs a
hosted upvote API; we have no server), runtime permission enforcement/sandboxing
(QML plugins run unsandboxed in the shell process — curation and transparency are
the gate, same trust model as both DMS and Noctalia), auto-update.

## 2. Architecture overview

```
XephyLon/imi-plugin-registry (new GitHub repo)
  plugins/<author>-<id>.json     ← one entry per plugin (PR-submitted)
  index.json                     ← CI-generated, never hand-edited
  schema/registry-entry.schema.json
  CONTRIBUTING.md                ← submission + transparency rules
  .github/workflows/validate.yml ← validates entries, regenerates index.json

shell (this repo)
  services/PluginStore.qml           ← fetch/cache/parse index, status merge, update check
  modules/ii/settings/pages/PluginStorePage.qml  ← browse UI (new settings page)
  scripts/plugins/install_plugin.py  ← learns --upgrade + provenance sidecar
  scripts/plugins/registry_validate.py ← entry validator, shared logic with registry CI
  modules/common/plugins/PluginManager.qml ← exposes installed versions + provenance
```

Plugins themselves stay in their authors' repos (DMS model). The registry entry
points at the author's hosted `manifest.json`; the existing `install_plugin.py`
transport (HTTPS-only, same-origin, size caps, path-traversal rejection, atomic
staging) is reused unchanged for the download itself. This was the deciding
argument for the DMS-style registry: our remote-install pipeline already exists
and is tested — the store is a catalog + UX layer on top of it, not a new
distribution mechanism. (Noctalia's monorepo model would have meant replacing
that pipeline with git clones and materialization.)

## 3. Registry repo

### 3.1 Entry format — `plugins/<author>-<id>.json`

```json
{
  "id": "pomodoroTimer",
  "name": "Pomodoro Timer",
  "description": "A desktop pomodoro timer widget with bar pill integration",
  "author": "somebody",
  "version": "1.2.0",
  "apiVersion": 1,
  "capabilities": ["desktop-widget", "bar-widget"],
  "permissions": ["settings_read", "settings_write"],
  "dependencies": ["libnotify"],
  "manifestUrl": "https://raw.githubusercontent.com/somebody/imi-pomodoro/v1.2.0/manifest.json",
  "sourceUrl": "https://github.com/somebody/imi-pomodoro",
  "screenshot": "https://raw.githubusercontent.com/somebody/imi-pomodoro/v1.2.0/screenshot.png",
  "icon": "timer",
  "tags": ["productivity", "clock"],
  "minShellVersion": "0.9.0"
}
```

Field notes:
- `id`, `name`, `version`, `apiVersion`, `capabilities`, `permissions` MUST match
  the plugin's own `manifest.json` — CI fetches the manifest and diffs them, so
  the store UI can honestly display permissions *before* download. (DMS enforces
  id/name match only; Noctalia gets this for free by hosting the source. We get
  it by CI cross-check.)
- `manifestUrl` SHOULD be a tag- or commit-pinned raw URL, not a branch URL, so a
  registry version means one immutable artifact. CI warns on branch URLs
  (`/main/`, `/master/`), and the entry's plugin manifest MUST carry a `sha256`
  for every `package.files` item (the installer already verifies these;
  optional-per-file today, required for registry submissions).
- `dependencies` = external tools the plugin shells out to (Noctalia's model);
  informational, displayed in the UI, not auto-installed.
- `screenshot` required for plugins with any visual entry point.
- `featured: true` (optional) — maintainer-set, sorts first.
- `minShellVersion` compared against the shell `VERSION` file; `apiVersion`
  compared against the shell's plugin API level (a new
  `PluginManager.apiVersion` constant, currently `1` — the manifest field
  finally gets read). Either mismatch renders the entry as "needs newer shell",
  install disabled.

### 3.2 `index.json` (CI-generated)

```json
{
  "version": 1,
  "generatedAt": "2026-07-27T00:00:00Z",
  "source": "official",
  "plugins": [ ...entries verbatim... ]
}
```

Served from `https://raw.githubusercontent.com/XephyLon/imi-plugin-registry/main/index.json`.
`version` is the index schema version (client rejects unknown majors);
`source` labels provenance now so multi-source support later needs no format change.

### 3.3 CI validation (`validate.yml` + shared `registry_validate.py`)

On every PR:
1. JSON schema check of each changed entry (required fields, types, id regex
   `[A-Za-z0-9][A-Za-z0-9_.-]{0,63}` — same as the installer's).
2. All URLs HTTPS; `manifestUrl`, `screenshot` and every `package.files` URL in
   the fetched manifest share one origin (mirrors `install_plugin.py` rules so a
   listed plugin can't fail at install time).
3. Fetch `manifestUrl`; diff `id/name/version/apiVersion/capabilities/permissions`
   against the entry; require `package.files` present, each with `sha256`; total
   declared size within installer caps (64 files / 8 MiB file / 32 MiB total).
4. Screenshot URL resolves (HEAD request) for visual plugins.
5. Filename must be `<author>-<id>.json`, one plugin per PR.

On merge to main: regenerate `index.json`, commit. The validator lives in this
repo as `scripts/plugins/registry_validate.py` and is vendored/pip-invoked by the
registry workflow, so shell tests and registry CI can't drift.

### 3.4 Submission & curation rules (CONTRIBUTING.md)

Noctalia's transparency rules, adopted nearly wholesale — they are the only
mitigation that works without sandboxing:
- All shipped code must be readable in the linked repo: no obfuscated, minified,
  or generated-unreadable QML/JS. A reviewer must be able to read every line.
- No runtime download-and-execute: all logic versioned in the repo; network use
  only for the plugin's stated data (and declared via the `network` permission).
- The PR description must account for every `Process` invocation, network call,
  and filesystem write, and the `permissions` array must honestly cover them.
- External binaries invoked must be listed in `dependencies`.
- Names first-come-first-served; `id` collisions with bundled plugins rejected
  (bundled ids are reserved: clock, docker, discordVoice, nandoroid-*, notes,
  screenshot-result).
- Human review by maintainer before merge. Explicit user-facing stance (same as
  DMS/Noctalia): plugins are trusted, unsandboxed code — review before install.

## 4. Shell client

### 4.1 `services/PluginStore.qml` (new singleton)

- `refresh()`: curl fetch of the index URL (pattern: `services/OnlineWallpapers.qml`
  Process+curl) into `~/.cache/immaterial-impulse/plugin-store/index.json`
  (atomic write via temp + rename), then parse. On-disk cache is loaded at
  startup so the store renders instantly offline; a fetch runs when the store
  page opens if the cache is older than 24 h, plus a manual refresh button.
- `parseIndex(text)` (pure): validates shape (`version === 1`, `plugins` array,
  per-entry required fields), drops malformed entries with a warning, returns
  clean list. Malformed index ⇒ keep last good cache.
- `entries`: parsed list. `statusFor(entry)` / derived `model` (pure merge):
  - `installed` — `PluginManager` has the id with `_origin === "installed"` and
    equal version
  - `update` — installed and registry `version` semver-greater than installed
    manifest version
  - `bundled` — id matches a bundled plugin (shown, not installable; installed
    override of bundled ids is an existing footgun, the store refuses to add to it)
  - `incompatible` — `apiVersion` > shell API level or `minShellVersion` >
    shell VERSION
  - `available` — everything else
- `compareVersions(a, b)` (pure): numeric dotted-segment compare, missing
  segments = 0, non-numeric segments compared lexically as tiebreak. No
  prerelease semantics (registry rule: plain `X.Y.Z` only, CI-enforced).
- `install(entry)` / `upgrade(entry)`: delegate to
  `PluginManager.installFromManifest(entry.manifestUrl)` (upgrade passes the new
  `--upgrade` flag through a new `PluginManager.upgradeFromManifest`).
- `updatesAvailable`: count, for the badge on the Plugins page nav.
- Pure functions (`parseIndex`, `compareVersions`, status merge) mirrored in a
  `testservices/PluginStore.qml` logic double, sync pinned by a contract test
  (established OpenRgb/Tailscale pattern).

### 4.2 Installer changes (`scripts/plugins/install_plugin.py`)

- New `--upgrade` flag: when the target dir exists, require its current
  `manifest.json` to parse and carry the same `id`; then stage the new version
  fully (existing staging + verification), move old dir to `<id>.old-<pid>`,
  `os.replace` staged dir in, delete the backup; on any failure restore the
  backup. Without `--upgrade`, the existing refuse-to-overwrite behavior stands.
- Provenance sidecar: after successful install/upgrade the installer writes
  `<plugin dir>/.store.json` — `{ "manifestUrl": ..., "installedVersion": ...,
  "installedAt": ... }`. Dot-prefixed names are already unreachable by package
  files (`safe_relative_path` rejects them), so a package cannot ship or
  clobber its own provenance. `PluginManager` reads it to distinguish
  store-installed plugins (update-checkable) from manually URL-installed ones
  (shown as "installed from URL", no update tracking unless the URL matches a
  registry entry's id+origin).
- All existing hardening (HTTPS, same-origin, caps, traversal, sha256, atomic
  staging) unchanged and still test-covered.

### 4.3 UI — `modules/ii/settings/pages/PluginStorePage.qml` (new page)

- Entry: a "Browse plugins" button row at the top of the existing PluginsPage
  (with the update-count badge when > 0), navigating to the store page —
  same sub-page navigation as IconPackSelector.
- Layout: search field (name/description/tags fuzzy-ish contains match) +
  capability filter chips (desktop widget / bar widget / panel) + "installed"
  filter; card grid. Featured first, then alphabetical.
- Card: icon (Material Symbol from `icon`), name, author, one-line description,
  capability chips, screenshot thumbnail (async `Image` with fixed-slot
  placeholder; Qt's network image loading with disk cache dir set — no custom
  downloader), status button: Install / Update / Installed / Needs newer shell.
- Install tap opens a confirm dialog (existing `WindowDialog` pattern) showing:
  permissions (each with a one-line human description, e.g. `process` → "Can run
  system commands"), external dependencies, source link ("Review the code"),
  and the standing trust warning. Confirm → install → toast via
  `PluginManager.installMessage`; newly installed plugin appears on PluginsPage
  (enable stays an explicit user step there, matching current behavior).
- Update-all button when multiple updates pending (sequential installs).
- Screenshot tap → enlarged preview (reuse the wallpaper preview overlay pattern
  if cheap, else skip in v1).

### 4.4 PluginsPage additions

- Store-installed cards show version + "Update" button when
  `PluginStore.statusFor` says `update`.
- The existing manual "Plugin manifest URL" install field stays (power-user
  path), unchanged.

## 5. Security posture (unchanged boundary, honest surfacing)

- The trust boundary remains transport hardening + curation. No new execution
  paths: the store only ever feeds URLs from the validated index into the same
  installer users can already invoke by hand.
- Index fetch is read-only data; `parseIndex` treats every field as untrusted
  display text (no rich text, `textFormat: PlainText` in all store labels —
  registry descriptions must never become QML/HTML injection).
- Screenshot URLs are same-origin with the plugin repo (CI-enforced), loaded as
  images only.
- The permission chips shown pre-install are CI-verified against the actual
  manifest, closing the "store says X, package does Y" gap DMS has.
- Existing threat noted in memory (malicious preset `apps.*` injection) is
  orthogonal — presets, not plugins — but the confirm-dialog permission listing
  establishes the pattern a future preset sanitizer can reuse.

## 6. Testing

- `tst_plugin_store.qml` + `testservices/PluginStore.qml` double:
  `compareVersions` (ordering table, missing segments, equal), `parseIndex`
  (valid, malformed entries dropped, wrong index version rejected, empty/garbage),
  status merge (installed/update/bundled/incompatible/available).
- `tests/test_plugin_installer.py` additions: `--upgrade` happy path, id
  mismatch refusal, rollback on staged-verify failure, sidecar written and
  excluded from package-controlled paths.
- `tests/test_registry_validate.py`: entry schema, cross-check mismatch
  detection, origin rules, sha256-required, size caps — the same module the
  registry CI runs.
- Contract test `test_plugin_store_contract.py`: logic-double sync pin, index
  URL is HTTPS constant, store page uses PlainText for registry strings,
  installer still refuses overwrite without `--upgrade`.

## 7. Implementation order

1. Installer: `--upgrade` + sidecar + tests (self-contained, unblocks everything).
2. `registry_validate.py` + tests.
3. `PluginStore.qml` service + double + tests (against a fixture index.json).
4. Store page UI + PluginsPage wiring.
5. Registry repo scaffold (schema, CI workflow invoking the validator,
   CONTRIBUTING.md, first entries: promote 1–2 suitable plugins as guinea pigs).
6. Docs: `docs/PLUGIN_STORE.md` (user + submitter guide), update
   `docs/PLUGINS.md` cross-references, CHANGELOG.

## 8. Open questions (defaults chosen, flag if wrong)

- Registry repo name: `imi-plugin-registry` under the same GitHub account as the
  shell repo.
- Index refresh TTL 24 h + manual refresh (no background polling service).
- `compareVersions` rejects prerelease tags entirely (CI enforces plain semver)
  rather than implementing precedence.
