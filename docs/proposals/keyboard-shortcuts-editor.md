# Proposal: keyboard shortcuts editor

> Implemented on this branch. This document records the design as built and
> the reasoning behind the decisions the draft left open.

## Goal

Make the cheatsheet's keybind list **editable**: rebind, add, and remove
shortcuts from the settings UI, writing to shell-owned state instead of
requiring the user to hand-edit Lua.

## Current state

Implemented:

- `services/HyprlandKeybindOverrides.qml` owns a declarative JSON sidecar
  (`~/.config/immaterial-impulse/keybind-overrides.json`, raw `FileView` on the
  `PluginState.qml` pattern) and regenerates a Lua shim from it through
  `scripts/hyprland/keybind_overrides.py`.
- The shim (`~/.config/hypr/hyprland/shellOverrides/keybinds.lua`) is sourced
  last by `hyprland.lua`, guarded by `is_file_exists`. The installer already
  excludes `shellOverrides/` from its overwrite-sync, so it survives updates.
- `modules/common/widgets/KeybindEditor.qml` is the single editing surface,
  reached from a hover pencil on every cheatsheet row and from the new
  Keybinds section on the Hyprland settings page (which also hosts the
  add-a-shortcut form and the override list with per-row/global reset).
- `modules/common/functions/keybindOverrides.js` holds the pure logic
  (identity, tree rewriting, rebindability, conflicts), unit-tested in
  `tests/tst_keybind_overrides_logic.qml`; the generator is contract-tested in
  `tests/test_keybind_overrides.py`; the full write path runs against a real
  Quickshell in `tests/test_keybind_overrides_runtime.py`.

## Decisions (formerly open questions)

### Write a declarative sidecar, not Lua

The draft weighed emitting Lua that round-trips the existing file against a
sidecar the shell owns. The sidecar won, decisively:

- Round-tripping hand-written Lua (comments, loops, locals) is not tractable;
  a generator over plain data is. The shipped `hyprland/keybinds.lua` and the
  user's `hypr/custom/keybinds.lua` are **never modified**.
- The generated-file discipline is modelled on
  `scripts/hyprland/hyprconfigurator.py` / `shellOverrides/main.lua`: the
  shell owns the file completely, writes atomically, and never rewrites
  unchanged content (Hyprland reloads on file change, so a no-op rewrite is
  reload churn).

The override mechanism rides Hyprland's Lua config API: `hl.bind()` returns a
keybind object whose `:unbind()` removes **every** bind matching that chord's
modmask+key (`CKeybindManager::removeKeybind`), so the shim's
`unbind_chord(c)` helper — bind a throwaway function, unbind it — clears a
chord including all its hidden sibling binds. A rebind is that unbind plus a
re-emitted `hl.bind` carrying the parsed dispatcher, params, flags and
description; an add is an `exec_cmd` bind.

Re-emission is gated by a literal-only params grammar (strings, numbers,
tables, `..`, plus identifiers naming `variables.lua` globals, which resolve
because the shim loads after both variables files). Binds whose action is a
Lua closure (`function`) or whose params reference `keybinds.lua` locals
(`qsIsAlive`, …) cannot be re-emitted; the UI offers remove-only for those and
says why. No parentheses in params means no function calls can be smuggled
into the generated file.

### Hand-edited override file: detect and refuse

The shim carries a content hash in its header. If the file on disk does not
hash-match, someone edited it by hand; the generator refuses to write **or
delete** it (exit 4), the service surfaces `shimStatus: "foreign"`, and both
UI surfaces show a banner naming the file to delete to hand control back.
Never clobbered, exactly as the draft leaned.

### Overrides are full replacement entries keyed on the default's identity

Sidecar keys are the default binding's identity — sorted mods + key
(`SHIFT+SUPER|C`), so modifier order never splits an identity. Each entry
stores everything needed to emit the replacement (dispatcher, params, flags,
description). A dots update changing the shipped file neither discards
overrides (the entry doesn't depend on the shipped definition surviving) nor
resurrects rebound defaults (the unbind targets the chord, which Hyprland
matches by modmask+key regardless of spelling). The service regenerates on
every startup as reconciliation, and the generator's unchanged-content check
makes that free.

### Conflict detection before write

`get_keybinds.py --flat` scans both keybind files for **every** statically
parseable bind — hidden and undescribed included — tagged with the
`hl.define_submap` block it sits in. The editor and the add form check a
captured chord against those scans plus the chords other overrides claim and
release, list every hit (submap collisions named as such — the
virtual-machine escape bind is `submap_universal` and fires everywhere), and
block Apply while any exist. Loop-generated binds (chords built from Lua
variables at load time, e.g. `SUPER + 1..0`) are invisible to a static parse,
so the clean state is worded "no conflicts detected", never "no conflicts".

### Reset

Per-binding reset and reset-all remove entries from the sidecar. An empty
sidecar deletes the shim (if still hash-managed), returning the system to its
pre-feature state.

## Out of scope (unchanged)

- Editing non-keybind Hyprland config through the same mechanism.
- Rebinding shell-internal shortcuts that are not Hyprland keybinds.
- Making top-level `--##!` sections with direct binds (Utilities, Screen,
  Media) visible in the cheatsheet — they are parsed but the renderer only
  displays second-level sections, a pre-existing gap this feature inherits:
  those binds are editable only once they render.
