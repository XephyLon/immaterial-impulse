# A — Repo unification: design

> Sub-project **A** of the Immaterial Impulse (ImI) initiative. See
> `2026-07-23-immaterial-impulse-handoff.md` for the four-sub-project
> decomposition and the working constraints.
>
> Status: **design complete, pending review.** Next step after approval is
> `writing-plans` → implementation plan.

## Scope

Combine this repo (the `end4-pC` theme, a fork of dots-hyprland's
`dots/.config/quickshell/ii/` subtree) with the full `end-4/dots-hyprland`
suite, adopting the dots layout at root and relocating the theme into
`dots/.config/quickshell/ii/`.

**In scope:** the git merge, the tree relocation, and every path/identity
reference that breaks as a direct consequence of the move.

**Out of scope (deliberately):**
- Any `illogical-impulse` → ImI rename. That is sub-project **B**, and it must
  stay atomic — `modules/common/Directories.qml:33` and ~13 scripts share the
  `~/.config/illogical-impulse` data dir and have to change in one commit.
- Branding-only `end4-pC` strings (source comments, plugin manifest `author`
  fields). Also **B**.
- The install TUI (**C**) and qs-wallpaperengine bundling (**D**).

## Target layout

```
<repo root>
├── .github/workflows/          # STAYS AT ROOT — GitHub reads workflows only from here
├── dots/
│   └── .config/
│       ├── hypr/               # from dots-hyprland
│       ├── matugen/            # from dots-hyprland
│       └── quickshell/ii/      # ← the entire current repo root moves here
├── dots-extra/                 # from dots-hyprland
├── setup/                      # from dots-hyprland (becomes C's install target)
├── diagnose/                   # from dots-hyprland
├── sdata/                      # from dots-hyprland
├── LICENSE                     # GPL-3.0, identical in both trees — keep one
└── README.md                   # dots-hyprland's, amended (see "Handoffs to B")
```

## Git strategy (approved, part 1)

- **This repo (`XephyLon/end4-pC`) continues** as the combined repo, preserving
  the full theme history including the embedded-wallpaperengine work.
- Absorb dots-hyprland via `git merge --allow-unrelated-histories`; its layout
  lands at root.
- Theme relocates to `dots/.config/quickshell/ii/`; the `ii` collision resolves
  **to ours** every time.
- Dual upstream afterward:
  - `dots-hyprland` (end-4) → normal merge, lands the *suite* only; `ii`
    conflicts always resolved to ours (same pattern used for the pctrade
    lock-theme supersede).
  - `upstream` (pctrade, the theme) → theme now in a subdir, so pull it via
    **`git subtree`** on `dots/.config/quickshell/ii/`. Exact
    subtree-vs-path-filtered-merge plumbing is an implementation-plan detail.

## Path & identity fallout (part 2)

### What survives the move for free

**QML import roots — zero changes.** All ~1705 `import qs.*` statements resolve
against the *shell root* (the directory containing `shell.qml`), not the config
directory name. The same holds for the ~40 `Quickshell.shellPath(...)` call
sites, including `Directories.assetsPath` / `Directories.scriptPath`
(`modules/common/Directories.qml:25-26`). Moving the tree intact requires no
import edits.

**Test suite — self-locating.** Every Python test resolves
`ROOT = Path(__file__).resolve().parents[1]` and every lint script resolves
`PROJECT_ROOT="$SCRIPT_DIR/.."`. They travel with `tests/` and keep working at
the new depth without modification.

### What breaks

| # | Kind | Sites |
|---|---|---|
| 1 | Hardcoded `~/.config/quickshell/end4-pC` | `scripts/presets.sh:12,13,106`; `tests/test_presets.py:26,120` |
| 2 | Self-reinstall command | `modules/ii/settings/pages/About.qml:29` |
| 3 | `qs -c end4-pC` in prose | `README.md:51`; `AGENT.md:23,24,65,72`; `CONTRIBUTING.md:112,113,117,209,244,245,253,254,260` |
| 4 | Repo-root-relative CI invocation | `.github/workflows/tests.yml:22` |

### Decisions

**D1 — Dev infra travels with the theme, except suite-level docs.**
`tests/`, `AGENT.md`, `CONTRIBUTING.md`, `.qmlformat.ini` and `.gitignore` move
into `dots/.config/quickshell/ii/`, keeping the pctrade subtree self-contained
and cleanly `git subtree`-mergeable against theme upstream. This also costs zero
churn — the suite is already self-locating.

`docs/` **splits by altitude**, because burying suite-level planning inside the
theme subtree would be wrong on both counts — it pollutes what we sync with
pctrade, and it hides ImI-wide specs under one component:
- `docs/M3_GUIDELINES.md` — theme-level → travels to
  `dots/.config/quickshell/ii/docs/`.
- `docs/superpowers/specs/` — suite-level ImI initiative specs → **stays at
  repo-root `docs/`**. This includes the handoff doc, this design, and every
  spec for B/C/D. (So this file does not move.)

**Exception: `.github/` stays at repo root.** GitHub only reads workflows from
`<root>/.github/workflows/`. `tests.yml:22` changes from
`./tests/run_tests.sh` to `./dots/.config/quickshell/ii/tests/run_tests.sh`.
No other workflow change is needed — `run_tests.sh` `cd`s to its own
`PROJECT_ROOT` before running anything.

*Accepted trade-off:* `tests/` and `docs/` ship inside the deployed config dir,
so a naive `dots/` → `~/` copy installs them to
`~/.config/quickshell/ii/tests/`. Harmless (nothing loads them at runtime); if
it matters, **C** adds installer excludes. Noted for C, not solved here.

**D2 — Scripts derive their own location from `$0`.**
`scripts/presets.sh` replaces its hardcoded `$HOME/.config/quickshell/end4-pC`
prefix with `SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"`, deriving the shell
root from that. This makes the script location-independent — it works from the
live dir, a git worktree, or a disposable `qs -p <path>` instance — and it
survives **B** untouched, since it never names the directory.

Consequences:
- `presets.sh:106`'s `qs -p "$HOME/.config/quickshell/end4-pC"` becomes
  `qs -p "$SHELL_ROOT"` derived the same way.
- `tests/test_presets.py:26,120` currently assert the literal path while
  building a fake `$HOME`; they must be reworked to invoke the script from a
  synthetic shell root instead of asserting the hardcoded one.

**D3 — `About.qml` self-reinstall is stubbed in A, wired in C.**
The current one-liner clones `pctrade/end4-pC` into `~/.config/quickshell/` and
relaunches `qs -c end4-pC`. Post-unification the repo is an entire suite rather
than a drop-in config dir, so the command is invalid on its own terms — and
running it would now also overwrite `hypr/` and `matugen/` configs. **A** stubs
the action (disabled, or removed from the page); **C** re-points it at the real
`setup/` installer once the TUI exists.

### Root-level collisions

- **`LICENSE`** — GPL-3.0 in both trees, same lineage. Keep one at repo root;
  the theme copy is redundant but harmless if it rides along.
- **`.gitignore`** — ours is two lines (`__pycache__/`, `*.py[cod]`). Merge
  them into the root `.gitignore` *and* keep a copy with the theme, so the
  subtree stays independently usable.
- **`.qmlformat.ini`** — theme-only, travels with the theme. No collision.
- **`README.md`** — dots-hyprland's wins at root; ours becomes the theme
  README. See below.

## Handoffs

### To B (rebrand)

1. **The coexist → supersede promise.** `README.md:46` currently states this
   fork "does not overwrite or modify any existing setup" and *requires*
   illogical-impulse to be installed separately. Once we occupy
   `~/.config/quickshell/ii`, we **are** ii — we replace end-4's install rather
   than sit beside it. Both READMEs need rewriting to say so plainly. Same
   framing appears at `README.md:9,120` and `AGENT.md:13,23,25`.
2. **The data dir.** `~/.config/illogical-impulse` → ImI equivalent, plus a
   migration path for existing users. Touches `Directories.qml:33`,
   `SettingsContent.qml:393,396`, `services/KeyringStorage.qml:24,32`
   (a `secret-tool` **keyring attribute** — renaming it orphans stored
   secrets, so this one needs real migration, not sed), `LauncherSearch.qml:98`,
   and ~9 scripts under `scripts/{ai,colors,keyring,hyprland}/`.
3. **Branding-only `end4-pC`** — 9 sites: 5 plugin manifest `author` fields,
   4 source comments.
4. **`welcome.qml:31`** and `translations/*.json` carry user-visible
   "illogical-impulse" strings.

### To C (install TUI)

- Re-point the `About.qml` reinstall action at `setup/`.
- Decide whether the installer excludes `tests/` and `docs/` from the deployed
  config dir.

## Verification

The move is correct when, from a fresh clone of the combined repo:

1. `./dots/.config/quickshell/ii/tests/run_tests.sh` passes (proves the
   self-locating suite survived the depth change).
2. The same command passes via the CI workflow path in `tests.yml`.
3. `qs -p <clone>/dots/.config/quickshell/ii` launches the shell and renders
   (proves `qs.*` imports and `shellPath()` resolve at the new depth).
4. `scripts/presets.sh` applies a preset when invoked from that clone *without*
   `~/.config/quickshell/ii` existing (proves D2's `$0` derivation).
5. `git log --follow` on a representative theme file still reaches the
   pre-merge history (proves the relocation preserved provenance).

Execution happens in an unrestricted env / fresh clone, **not** the live
`~/.config/quickshell/end4-pC` dir.
