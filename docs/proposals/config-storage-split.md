# Proposal: split config.json by domain

> Draft / tracking proposal. Not scheduled. Paths are relative to
> `dots/.config/quickshell/imi/` unless written repo-relative.

## Goal

Store settings as one file per domain (`appearance`, `bar`, `background`,
`ai`, ...) instead of one 40 KB `config.json`, without changing a single
`Config.options.x.y` read or write anywhere in the shell.

## Current state

- `modules/common/Config.qml` (1,901 lines) is one `JsonAdapter` behind one
  `FileView` on `~/.config/immaterial-impulse/config.json` (40 KB on this
  machine). Its header explains the cost model: **one property write
  serializes the whole schema**, the FileView watches the file it just
  wrote, and the shell re-reads and re-deserializes everything. Two timers
  (`readWriteDelay`, 50 ms) coalesce bursts; `ConfigWriteDelayRef` lets a
  surface claim immediate writes.
- Measured section sizes on the live file: appearance 4.3 KB, background
  2.6, bar 2.5, ai 1.7, sidebar 1.7, hyprland 0.95, phone 0.9, cheatsheet
  0.8. A slider on the bar page rewrites the AI system prompt and the
  wallpaper list on every tick.
- The shell already runs **eight other adapters** on their own files:
  `Persistent.qml`, `PluginState` (plugin-state.json), `WallpaperEngineOverrides`,
  `WallpaperEngineCompat`, `HyprlandKeybindOverrides`, `WorldClock`,
  `PhoneContacts`, `PhoneConnect`. Per-file state is the house pattern; the
  main config is the exception.
- Consumers of the file outside QML: `scripts/presets.sh` (reads and writes
  subsets with `jq`), the `get_shell_config`/`set_shell_config` AI tools,
  `switchwall.sh` (reads `appearance.palette`), `setup backup`, and the
  migration in `Directories.configDirReady`.

## Why

- **Blast radius.** A half-written file (power loss, a crash mid-write, a
  bad `jq` from a preset) loses every setting; per domain it loses one page.
- **Write amplification.** Every keystroke in any settings page costs a full
  serialize + inotify + full parse. Per domain it costs one small file.
- **Legibility.** Diffing, backing up, sharing a bar layout, or resetting one
  domain to defaults becomes a file operation; presets become "apply these
  files".
- **Migrations** stop being edits to one growing schema and become
  per-domain steps that can run and be tested alone.

## Approach

**1. Layout.** `~/.config/immaterial-impulse/config.d/<domain>.json`, one
per top-level `JsonObject` in `Config.qml` (about 25). `config.json` stays as
`config.json.pre-split-<date>` after migration and is never read again.

**2. The aggregator keeps the API.** `Config.options` is today an alias to the
adapter. It becomes a `QtObject` whose properties are aliases to one adapter
per domain:

```
property alias options: aggregate
QtObject { id: aggregate
    property alias appearance: appearanceAdapter   // JsonAdapter { ... }
    property alias bar: barAdapter
    ...
}
```

Every existing `Config.options.bar.style` binding compiles and behaves
unchanged. Each domain owns a `FileView` + `JsonAdapter` + its own debounce
timers; `ConfigWriteDelayRef` claims apply per domain (a settings page
usually touches one).

**3. Generic access.** `setNestedValue` (Config.qml) and the AI tools
walk `options.<domain>` first, then the path, so `set_shell_config("bar.style")`
still works. `presets.sh` gains a domain map: a preset file keeps its current
single-object shape and the script splits it on apply (`jq` per top-level
key) and merges on save.

**4. Migration.** On first start with no `config.d/`: read `config.json`, write
each top-level key to its file atomically (temp + rename), rename the old
file, set `ready`. Idempotent; a partial `config.d/` beside a `config.json`
prefers `config.d/` and only fills missing domains. The existing
`configDirTimedOut` gate covers the "never write this session" failure mode.

**5. Everything that lists files.** `setup backup`, the `3.files` deployer's
preserve list, `Directories`, the About page's "what changed" and the
`test_settings_*` contracts learn the directory. `Update Dots` verification
via the user path, as always.

**6. Order.** Land the aggregator with a **single** domain split first
(`appearance`, the largest and the one with the busiest writers), keep the
rest in `config.json`, run a week, then split the remainder in one pass.
The aggregator makes both states equivalent to every consumer.

## Risks

- **Cross-domain atomicity.** A preset apply becomes N writes; a crash
  between them leaves a mixed state. Acceptable (each file is valid) and
  better than today's all-or-nothing loss, but the preset script should write
  all temp files first and rename in one loop.
- **Downgrade.** The current design leaves unknown keys on disk so an older
  shell still reads them. An older shell would not read `config.d/` at all;
  the renamed `config.json.pre-split` is the downgrade path and the CHANGELOG
  must say so.
- **`JsonAdapter` is not a plain object.** Aliases to adapters work for
  bindings; anything that today does `Object.keys(Config.options)` needs the
  aggregator to enumerate domains explicitly (there are a handful: the AI
  tool, presets export, the settings search index).
- **Test surface.** `test_settings_row_grammar.py` and friends parse
  `Config.qml`'s schema text; splitting the schema across adapters must keep
  it greppable (one `JsonAdapter` block per domain in the same file, not 25
  files).

## Open questions

- One file per top-level key, or group the tiny ones (`cheatsheet`, `dock`,
  `osd`...) into `misc.json`? Proposal: one per key; the count is not a cost.
- Keep the schema in one `Config.qml` (greppable, 25 adapters in one file) or
  one QML per domain? Proposal: one file, for the tests and for the reader.
- Should presets move to the per-domain shape on disk too? Proposal: no;
  a preset is a bundle by definition and the script splits it.

## Out of scope

- Changing any setting's name or default.
- Moving state (`Persistent`, plugin state) — already per file.
- A settings sync or profile feature; this makes one possible, it is not one.
