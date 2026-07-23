# A — Repo unification: implementation plan

> Implements `2026-07-23-repo-unification-design.md` (approved).
> Execution is **supervised** — auto-accept off. Every phase below is a stop
> point; nothing proceeds without the gate passing.

## Phase 0 — Environment

This clone has **only `origin`**. The remotes the design assumes do not exist
here yet:

```bash
git remote add upstream       https://github.com/pctrade/end4-pC.git
git remote add dots-hyprland  https://github.com/end-4/dots-hyprland.git
git fetch --all
```

Work in a **fresh clone**, not `~/.config/quickshell/end4-pC`.

Record the pre-relocation fork point — every later step depends on it:

```bash
git merge-base HEAD upstream/main   # → $FORK_BASE, save it
```

**Gate:** `$FORK_BASE` resolves to a real commit present in both histories. If
it does not, our theme does not share ancestry with pctrade and **Phase 1's
mechanism choice changes** — stop and re-plan.

---

## Phase 1 — The dual-upstream spike (do this FIRST, throwaway clone)

This is the one part of A that can quietly go wrong, so it is settled
empirically **before** any real commit is made. Do all of it in a scratch clone
that gets deleted.

### The problem

Our theme sits at repo **root**; pctrade's theme also sits at root. After
relocation ours lives at `dots/.config/quickshell/ii/`. Pulling theme updates
means reconciling a root-level history with a subdirectory-level one.

### Hypothesis (to be proven or refuted, not assumed)

**`git subtree pull` is likely the *wrong* tool here, and the requirement to
prove it round-trips may prove the opposite.** The reasoning:

`git subtree` is built for the case where the subdirectory has **no shared
ancestry** with the remote — it synthesises a fake split history by scanning
commits for `git-subtree-dir:` / `git-subtree-split:` trailers. Our repo has
**no such trailers**, because the theme arrived by ordinary fork ancestry, not
by `git subtree add`. So `git subtree split --prefix=dots/.config/quickshell/ii`
sees only commits that touched that prefix — i.e. the relocation commit onward.
The synthesised history is effectively rootless against `upstream/main`, the
merge base degenerates, and the pull conflicts across the entire theme.

Meanwhile we *do* have genuine shared ancestry (`$FORK_BASE`), which git's
normal merge-base machinery can use directly — if we shift the paths:

```bash
git merge -X subtree=dots/.config/quickshell/ii upstream/main
```

`-X subtree=<path>` tells the ort strategy to shift one side's paths by that
prefix before matching. Real merge base, real three-way merge, conflicts only
where we actually diverged from pctrade.

### The spike — test BOTH, record actual output

In the scratch clone, complete Phase 2 and 3 (merge + relocation), then:

**Candidate A — path-shifted ordinary merge**
```bash
git merge -X subtree=dots/.config/quickshell/ii upstream/main
```
Record: conflict count, and whether conflicting paths are genuinely
theme-diverged files or the whole tree.

**Candidate B — git subtree, with a fabricated link**

`git subtree add` refuses an existing prefix, so the link must be established by
hand: an empty commit carrying the trailers that tell subtree "this prefix
currently corresponds to upstream commit `$FORK_BASE`".

```bash
git commit --allow-empty -m "Establish subtree link for dots/.config/quickshell/ii

git-subtree-dir: dots/.config/quickshell/ii
git-subtree-split: $FORK_BASE"

git subtree pull --prefix=dots/.config/quickshell/ii --squash upstream main
```

`--squash` is deliberate: subtree's `find_latest_squash` reads exactly those two
trailers, so the fabricated link is well-defined in squash mode. The non-squash
path relies on `find_existing_splits` walking the whole history and is markedly
more fragile.

Record the same metrics, then also test the **round-trip** the requirement
names: a second `git subtree pull` after a new upstream commit must be a
no-op-or-clean-merge, not a re-conflict of the same files.

### Decision rule

Adopt whichever candidate produces a merge base at `$FORK_BASE` and conflicts
confined to genuinely diverged files. If both work, prefer **Candidate A** — it
needs no fabricated metadata and keeps real history. If A fails and B works,
adopt B and the empty link-commit becomes a permanent part of Phase 3.

**Gate:** the chosen mechanism has been run twice against two different upstream
commits, with the second run clean. Written up in the spec before Phase 2 starts
for real. **If neither round-trips, A stops here and the dual-upstream design is
revisited** — do not proceed to a real merge on an unproven mechanism.

### Result (spike, 2026-07-23, git 2.55.0) — Candidate A adopted

Run in a throwaway clone; nothing real touched. **Candidate A
(`git merge -X subtree=dots/.config/quickshell/ii upstream/main`) adopted.**

- Our theme is caught up with pctrade (`$FORK_BASE` = upstream tip `8b068181`),
  so the round-trip was proven with two synthetic future-pctrade commits
  (theme-file edits at root).
- Rounds 1 and 2: both `Automatic merge went well`, **zero conflicts**. Root-path
  edits (`modules/common/Appearance.qml`, `README.md`) shifted into
  `dots/.config/quickshell/ii/` correctly, **no leak to root**. Round 2 did not
  re-conflict Round 1.
- **Candidate B (`git subtree`) not exercised** — the decision rule prefers A
  when it works, and it does. Real history, no fabricated trailers.

Also validated in the same spike: Phase 2 (only `.gitignore` conflicts; dots
README is at `.github/README.md`, no root collision; `.github/` merges as a
union) and Phase 3 (pure renames, `git log --follow` reaches pre-merge history).

---

## Phase 2 — Absorb dots-hyprland

**Merge before relocating.** Our files are at root, dots-hyprland's are under
`dots/`, `setup/`, etc., so the trees barely overlap and the merge is quiet.
Relocating first would instead pit our whole theme against dots-hyprland's `ii/`
as add/add conflicts at every path.

```bash
git merge --allow-unrelated-histories dots-hyprland/main
```

Expected conflicts — root-level only: `README.md`, `LICENSE`, `.gitignore`,
possibly `.github/`.

Resolution:
- `LICENSE` — GPL-3.0 both sides, same lineage. Take either, keep one.
- `.gitignore` — union: their root rules plus our `__pycache__/`, `*.py[cod]`.
- `README.md` — take **theirs** at root; ours is preserved and moves with the
  theme in Phase 3.
- `.github/` — take **ours**; `tests.yml` is fixed in Phase 4.

**Gate:** `git status` clean; `dots/`, `setup/`, `dots-extra/`, `diagnose/`,
`sdata/` present at root; our theme still intact at root.

---

## Phase 3 — Relocate the theme (pure renames)

Two commits, kept separate so the supersede is explicit and reviewable.

**3a — drop dots-hyprland's `ii`:**
```bash
git rm -r dots/.config/quickshell/ii
git commit -m "Supersede dots-hyprland's ii with the pC theme"
```

**3b — move ours in, as renames only:**
```bash
git mv shell.qml modules/ services/ panelFamilies/ scripts/ assets/ \
       defaults/ translations/ tests/ screenshots/ \
       AGENT.md CONTRIBUTING.md PLUGINS.md PLUGIN_DESIGN_SYSTEM.md README.md \
       .qmlformat.ini .gitignore \
       <root .qml files> \
       dots/.config/quickshell/ii/
mkdir -p dots/.config/quickshell/ii/docs
git mv docs/M3_GUIDELINES.md dots/.config/quickshell/ii/docs/
```

Per **D1 as amended**: `docs/superpowers/specs/` — the handoff, the design, this
plan, and every future B/C/D spec — **stays at repo-root `docs/`**. Suite-level
planning does not belong inside one component's subtree, and keeping it out
keeps what we sync with pctrade clean.

No content edits in this phase. Renames only, so `git log --follow` survives.

**Gate:** `git show --stat` reports 100% renames, zero content changes.
`git log --follow dots/.config/quickshell/ii/shell.qml` reaches pre-merge
history.

---

## Phase 4 — Path fixes

One commit per item, per the granular-commits constraint.

| # | Change | Sites |
|---|---|---|
| 4a | CI path → `./dots/.config/quickshell/ii/tests/run_tests.sh` | `.github/workflows/tests.yml:22` |
| 4b | **D2** — derive root from `$0`: `SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"`, and `qs -p "$SHELL_ROOT"` | `scripts/presets.sh:12,13,106` |
| 4c | Rework to invoke via a synthetic shell root instead of asserting the literal path | `tests/test_presets.py:26,120` |
| 4d | **D3** — stub the self-reinstall action; TODO pointing at C | `modules/ii/settings/pages/About.qml:29` |
| 4e | `qs -c end4-pC` → `qs -c ii` in prose | `README.md:51`; `AGENT.md:23,24,65,72`; `CONTRIBUTING.md:112,113,117,209,244,245,253,254,260` |

Explicitly **not** touched: `illogical-impulse` (13 sites, B's atomic rename)
and branding-only `end4-pC` (9 sites, also B).

---

## Phase 5 — Verification

Straight from the design's verification section:

1. `./dots/.config/quickshell/ii/tests/run_tests.sh` passes from a fresh clone.
2. The same passes through the CI workflow path.
3. `qs -p <clone>/dots/.config/quickshell/ii` launches and renders — proves
   `qs.*` imports and `shellPath()` resolve at the new depth.
4. `scripts/presets.sh` applies a preset from that clone with
   `~/.config/quickshell/ii` **absent** — proves 4b's `$0` derivation.
5. `git log --follow` on a representative theme file reaches pre-merge history.
6. The Phase 1 mechanism pulls a fresh upstream commit cleanly — the
   dual-upstream link still works after all of the above.

---

## Risks

| Risk | Mitigation |
|---|---|
| **Subtree link doesn't round-trip** — the main failure mode | Phase 1 spike settles it in a throwaway clone before any real commit; A halts if neither candidate works |
| `-X subtree=` behaves inconsistently across git versions | Spike runs on the actual execution machine's git (2.55.0 here); record the version in the write-up |
| Relocation recorded as delete+add, destroying provenance | Phase 3 gate asserts 100% renames |
| dots-hyprland merge drags in a conflicting `.github/` | Resolve to ours; 4a is the only workflow change |
| Fabricated subtree trailers mislead a future maintainer | If Candidate B is adopted, the link commit's message states plainly why it exists |
