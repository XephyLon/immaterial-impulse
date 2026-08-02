# Migrating settings from upstream

Immaterial Impulse descends from `end-4/dots-hyprland` by way of `pctrade/end4-pC`
and became independent at 0.7.0. A user arriving from either of those keeps their
`config.json`, and the shell reads it through a Quickshell `JsonAdapter` — which
**silently drops every key it has no property for**. No error, no warning: a
setting whose key this fork renamed is simply gone and replaced by a default.

This document is the audit trail for what the shell converts on their behalf.

## Where the migration runs, and why

`Config.qml` — `planUpstreamKeyMigration()` / `migrateUpstreamKeys()`, called from
the config `FileView`'s `onLoaded`. Runtime QML, not the installer.

- **The installer cannot see the users who need it most.** `sdata/lib/migrate-existing.sh`'s
  `has_legacy_config()` tests for `~/.config/illogical-impulse`. Anyone whose
  directory migration (`scripts/migrate-config-dir.sh`) already ran no longer has
  that directory — but their `config.json` still holds the upstream key shape.
  A directory test cannot distinguish "converted" from "moved but not converted".
  The marker key below can.
- **It has to run for people who never re-run the installer**, including anyone who
  moved the directory by hand.
- **It has to read keys `Config.options` cannot see.** The planner takes the raw
  parsed file text rather than `Config.options`, because the keys it needs are
  exactly the ones the adapter dropped.
- It follows the three key migrations already in `Config.qml`
  (`migratedDesktopWidgets`, `migratedDesktopWidgetOptions`,
  `migratedWorldClockTimezones`), including their **own marker key** discipline: a
  shared marker would permanently exclude every install that had already run an
  earlier half.

**Marker:** `migratedUpstreamSchema` (top level, default `false`).
**Ordering:** compute the whole plan, apply it, *then* mark. A config that could
not be parsed is left unmarked so the next launch retries, rather than recording a
migration that never happened. A config that was successfully inspected is marked
even when it needed nothing, so the parse does not repeat forever.

### This migration runs *after* the directory move, and that is now enforced

The key migration reads `~/.config/immaterial-impulse/config.json`. For an
arriving upstream user that file only exists because
`scripts/migrate-config-dir.sh` put it there, so the two migrations are ordered
by construction: **directory first, keys second, on the same launch.**

That ordering used to be a coincidence. The directory migration was fired with
`Quickshell.execDetached`, which returns immediately, so it ran concurrently
with `Config`'s asynchronous `FileView` load. Whenever `Config` got there first
it wrote a default `config.json` into the destination, the directory migration
refused to migrate into a directory that already had one, and the key migration
then ran happily against a config with nothing in it — converting a file the
user had never seen and setting `migratedUpstreamSchema` on it, which is the
one thing that cannot be undone: the marker is checked *before* the file is
read, so a launch that marks the wrong file spends the user's single chance.

`Directories.configDirReady` now makes it a happens-before. It is `false` until
the migration script exits; `Config`'s `FileView` binds its `path` to it, and an
unset path in Quickshell emits neither `loaded` nor `loadFailed` and writes
nothing on `writeAdapter()`, so nothing in `onLoaded` — including this
migration — can run against a directory that has not been migrated yet.
`tests/test_config_dir_migration_runtime.py` forces the interleaving that used
to lose (`IMI_MIGRATE_DELAY` holds the script open for seconds) and asserts both
halves land on one launch.

The two migrations stay separate for the reason the table above already gives:
a directory test cannot distinguish "converted" from "moved but not converted",
and only the marker key can. What changed is that the directory move is now
guaranteed to have happened first, rather than usually having happened first.

## The mapping

Derived from this repository's own history — there is no upstream remote and there
must never be one (`CONTRIBUTING.md`). Both reference points are commits here:

| Reference | Commit | Date |
| --- | --- | --- |
| `end-4/dots-hyprland` schema | `2212c9b7` (`dots/.config/quickshell/ii/modules/common/Config.qml`) | 2026-07-23 |
| `pctrade/end4-pC` schema (last merge, `78c58b84`'s upstream parent) | `99f6dfcd` (`modules/common/Config.qml`) | 2026-07-30 |
| Immaterial Impulse | `HEAD` | — |

Leaf key counts: end-4 284, pctrade 405, ImI 526.

### Renamed — migrated

| Old key | New key | Notes |
| --- | --- | --- |
| `bar.floatStyleShadow` (bool) | `bar.shadow` (bool) | Not a straight copy. See below. |

`bar.floatStyleShadow` defaulted to `true` upstream, but end-4 only ever drew the
shadow when the Float corner style was active (`BarContent.qml`:
`showBackground && cornerStyle === 1 && floatStyleShadow`). Ours draws it under
every corner style that paints a background. Copying the boolean across would
switch on a shadow the great majority of arriving users have never seen, so what
migrates is what was **on screen**, not what was on disk:

```
bar.shadow = floatStyleShadow === true && cornerStyle === 1
```

Absence of `floatStyleShadow` is the only signal that a config was already written
by this fork, so a config without it is never touched — otherwise the migration
would revert a `bar.shadow` the user set here.

**Known imprecision, stated deliberately:** in *pctrade's* tree `floatStyleShadow`
was a dead schema entry with no consumer at all, so a pctrade user on the Float
corner style gains a shadow they did not have. That is one switch in
Settings → Bar; the alternative — dropping a setting that was live and on by
default for the whole end-4 population — is worse. The two forks are separable by
key fingerprint, but not worth branching a cosmetic shadow on.

### Value changes — migrated

| Key | Old value | New value | Notes |
| --- | --- | --- | --- |
| `panelFamily` | `"ii"` | `"imi"` | The shell rename (`f43485e8`). |
| `panelFamily` | `"waffle"` | `"imi"` | end-4's second family; never ported here. |

`panelFamily` is a value rather than a key, so the adapter carries it across
intact and *then* nothing matches it. `"waffle"` is the severe one: no panel
loader activates, so the desktop comes up **completely blank with no error
anywhere**. `shell.qml`'s `PanelFamilyLoader.legacyFamilies` also aliases both at
read time, as a backstop that does not depend on the write having landed. Any
other value is left alone — it is not ours to guess at.

### Removed — not migrated, no destination invented

| Old key | Present in | Why there is nowhere to put it |
| --- | --- | --- |
| `notifications.monitor.enable` | end-4 only | Dead schema entry: nothing in the end-4 tree read it. Nothing was ever configurable, so nothing is lost. |
| `notifications.monitor.name` | end-4 only | Same. Note this is **not** the same concept as our `notifications.position`, which picks a screen corner, not a monitor. |
| `waffles.bar.bottom` | end-4 only | The waffle panel family is not part of this shell. |
| `waffles.bar.leftAlignApps` | end-4 only | ” |
| `waffles.actionCenter.toggles` | end-4 only | ” |
| `waffles.calendar.force2CharDayOfWeek` | end-4 only | ” |
| `waffles.tweaks.smootherMenuAnimations` | end-4 only | ” |
| `waffles.tweaks.smootherSearchBar` | end-4 only | ” |
| `waffles.tweaks.switchHandlePositionFix` | end-4 only | ” |

These keys are not preserved. An undeclared key is not merely hidden from
`Config.options` — the adapter serializes exactly its declared properties, so the
first `writeAdapter()` (which happens on essentially every launch, even one that
changed nothing) removes it from the file. Verified end to end against an isolated
`XDG_CONFIG_HOME`.

**This gives the migration exactly one launch.** It runs in `onLoaded` off the raw
file text, before anything can write. A user who has already launched *any*
post-fork ImI build has already lost `bar.floatStyleShadow` to that build's first
write, and this migration cannot recover it — their `bar.shadow` stays at the
default and they set it themselves. `panelFamily` is unaffected by this, since it
is a declared key whose *value* is stale rather than a key that disappears; it
migrates whenever the user gets here.

### Already handled elsewhere — deliberately not duplicated here

| Concern | Where |
| --- | --- |
| `~/.config/illogical-impulse` → `~/.config/immaterial-impulse` | `scripts/migrate-config-dir.sh` (+ `tests/test_config_migration.py`, `tests/test_config_dir_migration_runtime.py`) |
| `background.widgets.*` → `plugins.enabled` / plugin options | `Config.qml` `migrateDesktopWidgets*` (+ `tests/test_widget_plugin_migration.py`) |
| Secrets keyed `illogical-impulse` → `immaterial-impulse` | `services/KeyringStorage.qml` (+ `tests/test_keyring_migration.py`) |
| `illogical-impulse-*` packages | `sdata/lib/migrate-existing.sh` (+ `tests/test_installer_legacy_migration.py`) |

### Everything else

Beyond the rows above, ImI's key schema is a **strict superset** of pctrade's, with
zero type changes and no key moved to a different parent. Verified by extracting
every leaf key path from all three `Config.qml` trees and diffing the sets; the
only pctrade key absent from ImI is `bar.floatStyleShadow`. Keys ImI added that
upstream never had need no migration — a missing key just takes the QML default.

Two default values changed (`panelFamily`, and `bar.layouts.rightLayout` gaining
`submapIndicator`/`privacyIndicator`). Defaults do not affect an existing config,
which carries its own values; an arriving user simply does not get the two new bar
widgets until they add them.

## What this does *not* cover

Stated explicitly rather than half-done:

- **`~/.config/hypr/`.** This fork's Hyprland config diverged heavily and uses a
  Lua layer (`hl.bind`, `hl.dsp.*`) that upstream's plain-text config has no
  counterpart for. Converting keybinds and rules between the two is a different
  problem from converting a JSON schema, and is not attempted.
- **`~/.config/matugen/`.** Owned by the theming pipeline, not by the shell.
- **Anything outside the shell's `config.json`** inside the data directory
  (`actions/`, `presets/`, `ai/prompts`, `plugin-state.json`). The directory move
  carries these across byte-for-byte; no format inside them changed in a way this
  fork introduced.
- **Upstream commits newer than the reference points above.** The delta is
  reconstructed from the two snapshots in this repository's history, which is the
  only source available and the only one permitted. A user arriving from an
  `end-4/dots-hyprland` newer than 2026-07-23 may carry keys that did not exist at
  that snapshot; those cannot be enumerated here, and the migration silently and
  correctly ignores them rather than guessing. If upstream renames something after
  that date, this table will not know.
