# Immaterial Impulse (ImI) — brainstorm handoff

> WIP brainstorm state, committed to the repo so it survives a session/machine
> move (Claude Code memory is machine-local + cwd-scoped, doesn't travel).
> Resume: start Claude Code **inside the repo**, say "continue the ImI
> brainstorm", read this file, pick up at **A part 2**.

## The initiative
Turn the current place-in Quickshell theme into a full plug-and-play desktop
suite:
- **Rebrand** `illogical-impulse` → **Immaterial Impulse**, short **ImI**
  (user typed "Immaterial Impule" — treat as *Impulse*; confirm exact
  casing/slug in sub-project B). ~44 files reference `illogical-impulse`, plus
  the live data dir `~/.config/illogical-impulse`.
- **Unify** with `end-4/dots-hyprland` (the full suite: hypr configs, matugen,
  `setup/` installer, packages). This repo **is** a fork of dots-hyprland's
  `dots/.config/quickshell/ii/` subtree.
- **Install script / TUI** — plug-and-play install of the whole suite.
- **Bundle qs-wallpaperengine** (native WE renderer, `XephyLon/qs-wallpaperengine`).

## Decomposition — 4 sub-projects, each its own spec → plan → build
- **A — Repo unification** (deps: none)
- **B — Rebrand → ImI** (deps: A — rebrand after the tree is combined)
- **C — Install TUI** (deps: A, B; folds in D)
- **D — Bundle qs-wallpaperengine** (deps: A, C)

**Chosen order: A and B first.** C/D later.

## A — Repo unification (decisions so far)

**Structure — APPROVED** ("adopt dots layout, keep upstreams"):
- Repo becomes the full dots-hyprland layout at root: `dots/`
  (`.config/{hypr,quickshell/ii,matugen,…}`), `setup/`, `dots-extra/`,
  `diagnose/`, `sdata/`.
- Our theme moves from repo root → `dots/.config/quickshell/ii/`, replacing
  dots-hyprland's `ii`.

**Git strategy (part 1) — APPROVED:**
- **This repo (`XephyLon/end4-pC`) continues** as the combined repo — keeps the
  full theme history including the embedded-wallpaperengine work.
- Absorb dots-hyprland via `git merge --allow-unrelated-histories`; its layout
  lands at root.
- Theme relocates to `dots/.config/quickshell/ii/`; the `ii` collision resolves
  **to ours** every time.
- Dual upstream afterward:
  - `dots-hyprland` (end-4) → normal merge, lands the *suite* only; `ii`
    conflicts always resolved to ours (same pattern used for the pctrade
    lock-theme supersede).
  - `upstream` (pctrade, the theme) → theme now in a subdir, so pull it via
    **`git subtree`** on `dots/.config/quickshell/ii/` (root→subdir path shift).
    Exact subtree-vs-path-filtered-merge plumbing = implementation-plan detail.

**Naming coincidence to exploit in B:** dots-hyprland's quickshell dir is
already `ii` (illogical-impulse); rebranding to **I**mmaterial **I**mpulse keeps
`ii` valid, so `~/.config/quickshell/ii/` survives. Only the data dir
`~/.config/illogical-impulse/` needs a rename/migration decision (B).

## Where we stopped / NEXT
A part 1 (git strategy) **approved**. A part 2 (path/identity fallout)
**approved** — decisions D1/D2/D3 below.

A design **approved** (reviewed on the other machine).
A plan written to `docs/superpowers/specs/2026-07-23-repo-unification-plan.md`.

**NEXT: execute A, starting with the Phase 1 dual-upstream spike** — in a
throwaway clone, auto-accept OFF, supervised. A halts at that gate if neither
subtree candidate round-trips. Then repeat the spec → plan → build cycle for B.

> `writing-plans` is **not installed on this machine** — no superpowers skills
> present; `docs/superpowers/` is only a repo convention here. The A plan was
> written directly in the same style. If the other machine has the skill, the
> plan can be regenerated through it.

### D1 amendment (approved)
`docs/` splits by altitude: `docs/M3_GUIDELINES.md` travels with the theme;
`docs/superpowers/specs/` (handoff, designs, plans for A/B/C/D) **stays at
repo-root `docs/`** — suite-level planning must not be buried inside the theme
subtree, and keeping it out keeps the pctrade sync clean.

### A part 2 decisions (approved)
- **D1** — dev infra (`tests/`, `docs/`, `AGENT.md`, `CONTRIBUTING.md`) travels
  with the theme into `dots/.config/quickshell/ii/`, keeping the pctrade subtree
  self-contained and subtree-mergeable. **Exception:** `.github/` stays at repo
  root (GitHub reads workflows only from there); `tests.yml` gets the new path.
- **D2** — `scripts/presets.sh` derives its root from `$0`
  (`readlink -f`) instead of hardcoding `~/.config/quickshell/end4-pC`;
  location-independent and survives B untouched.
- **D3** — `About.qml:29` self-reinstall is stubbed in A, wired to `setup/` in C.

### Key finding: the move is cheaper than expected
`import qs.*` (~1705 sites) and `Quickshell.shellPath()` (~40 sites) resolve
against the **shell root** (dir containing `shell.qml`), not the config dir
name — so relocating the tree needs **zero** import edits. Tests are likewise
self-locating (`parents[1]` / `$SCRIPT_DIR/..`).

### Logged for B
- `README.md:46` promises the fork *coexists* with illogical-impulse and never
  overwrites it. Occupying `~/.config/quickshell/ii` makes that a **supersede** —
  both READMEs must be rewritten (also `README.md:9,120`, `AGENT.md:13,23,25`).
- `services/KeyringStorage.qml:24,32` uses `illogical-impulse` as a `secret-tool`
  **attribute**, not a path — renaming it orphans stored secrets, so it needs a
  real migration, not a sed pass.

## Constraints / working defaults (carry over)
- No Claude/agent attribution in commits or PR bodies.
- Granular commits preserving the trial-and-error journey; don't squash.
- PR merges into `main` are always **rebase** (feature branch won't be a literal
  ancestor after merge — verify by content).
- `gh pr create` defaults base to the parent (pctrade) repo; pass
  `--repo XephyLon/end4-pC` for an internal PR.
- Remotes: `origin`=XephyLon/end4-pC, `upstream`=pctrade/end4-pC (theme),
  `dots-hyprland`=end-4/dots-hyprland (suite).
- Execution (the actual restructure) intended for an unrestricted env / fresh
  clone, not the live `~/.config/quickshell/end4-pC` dir.
