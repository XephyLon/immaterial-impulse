# Plugin store

The in-shell plugin store is a browsable catalog of community plugins served from a curated
registry. It is a catalog and UX layer on top of the existing remote-installation pipeline
described in [PLUGINS.md](PLUGINS.md) — the store only ever feeds URLs from the validated registry
index into the same hardened installer users can already invoke by hand with a manifest URL.

Registry entries live in the dedicated registry repo `XephyLon/imi-plugin-registry`, one JSON file
per plugin, and its CI generates the `index.json` the shell consumes. (The repo is scaffolded and
not yet published on GitHub; until it is, the store fetch fails gracefully and the catalog renders
empty.)

> **The store UI ships gated off.** Until the public registry goes live, the whole feature is
> hidden behind `plugins.storeEnabled` (config-file-only, default `false`, no settings toggle).
> Set it to `true` in `config.json` to reveal the Browse button, update badges, and store page.

## Using the store

Open **Settings → Plugins → Browse plugins**. The button carries a count badge when updates are
available for installed plugins.

The catalog is fetched from the registry index and cached at
`~/.cache/quickshell/plugin-store/index.json`, so the page renders instantly offline from the last
good copy. Opening the page refetches only when the cache is older than 24 hours; the **Refresh**
button forces a fetch. A failed fetch or a malformed index shows an error and keeps the last good
entries.

Search matches name, description, and tags (case-insensitive contains). The filter chips narrow by
capability — Desktop widget, Bar widget, Panel — and **Installed** shows only plugins that are
installed (including ones with a pending update). Featured plugins sort first, then alphabetical.

Each card's action button reflects the plugin's status:

* **Install** — listed and not installed.
* **Update** — installed, and the registry lists a newer version.
* **Installed** — installed and up to date (disabled).
* **Bundled** — ships with the shell; the store refuses to install over a bundled id (disabled).
* **Needs newer shell** — the entry's `apiVersion` is above the shell's plugin API level, or its
  `minShellVersion` is above the shell's `VERSION` (disabled).

### The install dialog

Install and Update from a store card open a confirmation dialog before anything is downloaded. It
shows the plugin name and version, the declared permissions with plain descriptions, any external
`dependencies` (tools the plugin shells out to — displayed, not auto-installed), a **Review the
code** link opening the plugin's source repo, and a standing trust warning. The permission names
mean:

| Permission | Meaning |
| --- | --- |
| `process` | Can run system commands |
| `network` | Can access the network |
| `filesystem_read` | Can read your files |
| `filesystem_write` | Can write to your files |
| `settings_read` | Can read shell settings |
| `settings_write` | Can change shell settings |

Confirming runs the same installer as manual URL installs (HTTPS-only, same-origin, size caps,
SHA-256 verification, atomic staging). A newly installed plugin appears on the Plugins page;
enabling it stays an explicit toggle there, exactly as with a manual install.

### Updates

Update detection compares the registry version against the installed manifest's version (plain
dotted-numeric compare — the registry only accepts `X.Y.Z`). When a newer version is listed:

* the **Browse plugins** button on the Plugins page shows the update count;
* the installed plugin's card on the Plugins page gains an **Update** button that upgrades
  directly (the permissions were already accepted at install time);
* the store card shows **Update**, which goes through the confirm dialog again;
* **Update all (n)** appears on the store page when two or more updates are pending and runs them
  sequentially — installer runs are serialized, so queued upgrades wait for the previous one.

Upgrades stage and verify the new version completely before atomically swapping it over the old
one; a failed upgrade restores the previous version.

### Trust model, in plain words

The registry is curated: every entry is reviewed by a human before merge, and CI cross-checks the
entry's `id`/`name`/`version`/`apiVersion`/`capabilities`/`permissions` against the plugin's actual
manifest, so the permission chips you see before download are verified, not self-reported. But
there is no sandbox — an installed plugin is QML executed inside the shell process with the same
access as the shell itself. Curation and transparency are the gate. Use the **Review the code**
link; only install plugins from authors you trust.

## Submitting a plugin

The registry repo's `CONTRIBUTING.md` is the authoritative submission guide. In short: your
plugin's code stays in your own repo; you PR one JSON entry pointing at your hosted
`manifest.json`. The hard rules:

* One plugin per PR; entry file name exactly `plugins/<author>-<id>.json`, matching the `author`
  and `id` fields inside the entry. Ids are first-come-first-served, and the bundled plugin ids are
  reserved.
* `id`, `name`, `version`, `apiVersion`, `capabilities`, and `permissions` must match your plugin's
  own `manifest.json` — CI fetches the manifest and diffs them.
* `manifestUrl` should be a tag- or commit-pinned raw URL, not a branch URL, so a registry version
  names one immutable artifact (CI warns on `/main/` and `/master/`).
* Every `package.files` item must carry a `sha256` (required for registry submissions, not merely
  recommended); at most 64 files; all URLs HTTPS and sharing one origin.
* Plain `X.Y.Z` versions only — no prerelease or build suffixes. Description at most 200
  characters. A `screenshot` is required for any visual entry point (`desktop-widget`,
  `bar-widget`, or `panel` capability).
* Transparency rules: all shipped code readable in the linked repo (no obfuscated or minified
  QML/JS), no runtime download-and-execute, the PR description accounts for every `Process`
  invocation, network call, and filesystem write, the `permissions` array honestly covers them, and
  external binaries are listed in `dependencies`.

Validate locally before opening the PR:

```
python3 scripts/plugins/registry_validate.py plugins/<author>-<id>.json
# optionally, with your manifest downloaded next to it:
python3 scripts/plugins/registry_validate.py plugins/<author>-<id>.json --manifest manifest.json
```

Exit code 0 (warnings allowed) means CI's offline checks will pass. The validator never touches the
network — CI fetches the manifest itself and passes `--manifest`.

## Maintainer notes

* `index.json` in the registry repo is CI-generated on merge to main (deterministic, sorted by id)
  and never hand-edited. The shell reads it from the repo's raw URL; the index carries a schema
  `version` (the client rejects unknown majors) and a `source` label so multiple sources need no
  format change later.
* The validator's canonical copy is this repo's `scripts/plugins/registry_validate.py` (theme
  root). The registry repo vendors it as `scripts/registry_validate.py` with a header naming the
  canonical path — changes land here first and are copied over, so shell tests and registry CI
  cannot drift. It must stay stdlib-only and self-contained.
* After every successful install or upgrade the installer writes a provenance sidecar,
  `<plugin dir>/.store.json`, recording `manifestUrl`, `installedVersion`, and `installedAt`. The
  dot-prefixed name is unreachable by package files (the installer rejects dot-prefixed paths), so
  a package can never ship or clobber its own provenance. `PluginManager` exposes it as the
  `_store` key on the plugin's manifest entry.
* `PluginManager.apiVersion` (currently `1`) is the shell's plugin API level. Bump it when the
  plugin API changes incompatibly — entry points, manifest semantics, or the component/binding
  surface plugins rely on. Registry entries declare the `apiVersion` they were written against, and
  the store renders entries requiring a higher level as "Needs newer shell" rather than letting the
  install fail later.
