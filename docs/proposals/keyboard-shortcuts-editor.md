# Proposal: keyboard shortcuts editor

> Draft / tracking proposal. Not scheduled.

## Goal

Make the cheatsheet's keybind list **editable**: rebind, add, and remove
shortcuts from the settings UI, writing to the user override file instead of
requiring the user to hand-edit Lua.

## Current state

Most of the hard part already exists.

- `services/HyprlandKeybinds.qml` parses keybinds and already understands the
  two-file model:
  - `defaultKeybindConfigPath` → `~/.config/hypr/hyprland/keybinds.lua`
  - `userKeybindConfigPath` → `~/.config/hypr/custom/keybinds.lua`
- `modules/imi/cheatsheet/CheatsheetKeybinds.qml:11` renders
  `HyprlandKeybinds.keybinds` — **read-only**.
- Keybinds carry a `description` field (see `keybinds.lua:38`), so the list is
  already human-readable rather than raw dispatcher strings.

So this is largely "add a writer and an edit UI to an existing parser", not a
new subsystem.

## Why

- Rebinding is the single most common reason a user has to open a config file
  by hand. Everything else the shell exposes through settings.
- The read-only cheatsheet already trains users to look there for shortcuts,
  which makes the absence of editing feel like a missing feature rather than a
  design choice.
- The user override file (`hypr/custom/keybinds.lua`) already exists as the
  supported customization point, so writes have a safe destination that survives
  updates — unlike editing the shipped defaults, which the updater overwrites.

## Approach

- Extend `services/HyprlandKeybinds.qml` with a writer that emits only to
  `userKeybindConfigPath`. Never write to the shipped defaults file.
- Represent an override as a full replacement entry keyed on the default's
  identity, so the shipped file can change across updates without silently
  discarding user overrides or resurrecting rebound defaults.
- Capture new bindings with a key-capture control that reads modifiers plus one
  key and renders them in the same notation the parser already produces.
- Detect conflicts before writing: two bindings on the same chord, and bindings
  that collide with a Hyprland submap (`services/HyprlandSubmap.qml`).
- Offer a per-binding "reset to default" and a global "reset all", both of which
  just remove entries from the override file.
- Surface it from both the cheatsheet (an edit affordance on each row) and a
  settings page, sharing one component.

## Open questions

- Whether to write Lua (matching the existing file format, but meaning the
  writer has to emit valid Lua and round-trip comments) or to write a
  declarative sidecar that the Lua file sources. The sidecar is safer to
  generate but adds a file to the config surface.
- What to do when the user has already hand-edited `hypr/custom/keybinds.lua`.
  Overwriting it would destroy their work; merging into arbitrary Lua is not
  tractable. Likely answer: detect hand-editing and refuse to write, with a
  clear message.

## Out of scope

- Editing non-keybind Hyprland config through the same mechanism.
- Rebinding shell-internal shortcuts that are not Hyprland keybinds.
