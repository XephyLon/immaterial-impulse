# Proposal: integration test script

**Status:** parked (2026-07-24). Captured from the wallpaper-freeze debugging
session so the idea and findings survive until someone picks it up.

## Why

Unit coverage exists (84 qmltestrunner logic tests + the pytest script suites),
but nothing exercises real *flows*. The 2026-07-24 wallpaper-switch freeze
cascade (basic render loop × WE video GL, kde-material-you icon re-apply,
desktop-entry rescans → multi-second QV4 GC pauses) was only findable by
driving the live shell and measuring responsiveness — exactly what an
integration test would automate.

## Candidate scopes (highest value first)

1. **Updater/installer lifecycle** — install → user-modify → update → assert.
   The update path has real data-loss semantics: `setup install` deploys
   `~/.config/quickshell/ii` with `rsync -a --delete` (local edits wiped by
   contract), while `hypr/custom`, `hyprlock.conf`, `hypridle.conf`, the user
   `config.json` and presets must survive. Two divergent code paths
   (`setup install` vs `setup exp-update`) share zero coverage; only
   `exp-update-tester.sh` exists, testing exp-update in isolation.
2. **Live shell flows** — boot the shell, drive wallpaper/preset switches,
   assert GUI responsiveness. Working recipe already proven in-session: an IPC
   roundtrip latency probe (`qs -c ii ipc call …` every 300 ms; idle ≈ 85 ms,
   a stall is a freeze) plus log-heartbeat gap analysis. This caught the
   preset-cycle regression (11 stalls ≤ 4.8 s → 0 after the fixes).
3. **Theming pipeline** — switchwall → matugen → assert generated files and
   applied configs (kdeglobals, GTK, terminal). File assertions only, no
   display server needed; cheapest to put in CI.
4. **Shell boot smoke** — the shell starts, all QML loads without errors,
   exits clean.

## Feasibility notes

- Scopes 1 & 3 are container-friendly (Arch container, same pattern as
  qs-wallpaperengine's release CI; scope 1 wants a throwaway `$HOME`).
- Scope 2 needs a Wayland compositor (headless Hyprland or similar) plus the
  WE-capable quickshell build — heavier; likely a local/self-hosted script
  before it can be GitHub CI.
- Scope 4 might run headless with a nested compositor + software rendering;
  needs a spike.

## Suggested first increment

A bats/pytest harness for scope 1 in a throwaway `$HOME`: run `setup install`
non-interactively, mutate user-owned files, run the update, and assert the
preserve/wipe contract per path. The per-dir mode table already documented in
`sdata/subcmd-install/3.files-exp.yaml` is the contract to assert against.
