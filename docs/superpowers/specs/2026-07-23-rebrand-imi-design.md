# B — Rebrand to Immaterial Impulse (ImI): design

> Sub-project **B** of the Immaterial Impulse initiative. Runs on the unified
> tree produced by **A** (`dots/.config/quickshell/ii/` = theme; suite at root).
> See `2026-07-23-immaterial-impulse-handoff.md` for the decomposition.
>
> Status: **design, pending review.** Next after approval: `writing-plans`.

## Scope

Rename the fork's own identity from `illogical-impulse` / `end4-pC` to
**Immaterial Impulse** (short **ImI**) across the unified tree — 83 files, 217
occurrences of `illogical-impulse` plus the `end4-pC` branding residue A left.

**In scope:** our data dir, our dependency packages, the keyring secret
identity, and every brand-facing string, plus the two user migrations the
renames force.

**Out of scope:** the install TUI (**C**) and qs-wallpaperengine bundling
(**D**). C owns replacing installed `illogical-impulse-*` packages on existing
systems; B only renames the package *definitions*.

## Naming map

| Thing | From | To |
|---|---|---|
| Data dir | `~/.config/illogical-impulse` | `~/.config/immaterial-impulse` |
| Quickshell dir | `ii` | `ii` (unchanged — already fits ImI) |
| Dep packages | `illogical-impulse-*` | `immaterial-impulse-*` |
| Keyring attribute | `application=illogical-impulse` | `application=immaterial-impulse` |
| Keyring label | `illogical-impulse Safe Storage` | `Immaterial Impulse Safe Storage` |
| Brand strings | `end4-pC` / `illogical-impulse` | `Immaterial Impulse` / `ImI` |

Single source for the data dir: `Directories.qml:33`
(`shellConfig: ${config}/illogical-impulse`). ~30 scripts hardcode the path and
change alongside it. Packages: all of `sdata/dist-arch/illogical-impulse-*/`
(dir names + `pkgname` + inter-package `depends` + `install-deps.sh` +
`deps-info.md`, 75 refs).

## Scope boundary — change vs. keep

`illogical-impulse` means two different things; only one is ours.

**Change** (our identity): data-dir paths, package names, keyring
attribute/label, `welcome.qml:31` title, `README` title (`# 💠 end4-pC`),
translations' brand strings.

**Keep** (attribution to the origin project — erasing it would be wrong):
- `README:9` "a personal fork of illogical-impulse by @end-4", `README:120`
  credits, and every `github.com/end-4/dots-hyprland` link.
- Repo names in lineage/commands: `pctrade/end4-pC`, `XephyLon/end4-pC`,
  the dots-hyprland→pctrade→fork chain in `AGENT.md`.
- `LICENSE`.

The test: does the token name *the origin/author/a real repo* (keep) or *our
runtime/brand* (change)?

## Migrations (the two that can break users)

**M1 — data dir.** One-time, at shell startup, before anything reads config:
if `~/.config/immaterial-impulse` is absent and `~/.config/illogical-impulse`
exists, move it (config.json, plugin-state.json, presets/, generated themes).
Idempotent, additive, logged. New installs skip it (nothing to move).

**M2 — keyring secrets.** The `application` secret-tool attribute is the lookup
key for stored API keys; renaming it orphans them. On lookup: query the new
attribute first, **fall back to the old**, and on a fallback hit re-store under
the new attribute (lazy re-key). No user re-enters keys; the old entry can be
cleaned up opportunistically. `KeyringStorage.qml:24,32,80`.

## Execution

- **Atomic rename sweep** — the path/name/attribute renames land together so the
  tree is never half-renamed (a half-rename would point the shell at a dir that
  does not exist). Migrations M1/M2 ship in the same change.
- **README coexist→supersede rewrite** (flagged by A): `README:46` currently
  says the fork "does not overwrite any existing setup" and *requires*
  illogical-impulse alongside. As ImI occupying `~/.config/quickshell/ii` and
  shipping the whole suite, it **supersedes** rather than coexists — rewrite the
  README (and the matching lines in `AGENT.md`) to say so, while keeping the
  end-4 attribution.
- Translations (`translations/*.json`) get the brand string updated where it is
  ImI's own name, not where it credits the origin.

## Upstream divergence (expected)

Renaming pctrade-owned theme files means a future
`git merge -X subtree=dots/.config/quickshell/ii upstream/main` conflicts on the
branded files. This is intentional — the rebrand is the fork's identity — and
conflicts stay confined to genuinely-branded files (resolve to ours).

## Verification

1. `grep -rn "illogical-impulse" .` returns **only** attribution/lineage/origin
   references (the keep-list), zero of our own paths/packages/brand.
2. `grep -rn "end4-pC"` returns only real repo names / lineage.
3. The QML test suite still passes from `dots/.config/quickshell/ii/tests/`.
4. M1: with a fake `~/.config/illogical-impulse` present and no
   `immaterial-impulse`, first startup moves it; second startup is a no-op.
5. M2: a secret stored under the old attribute is readable after the rename and
   gets re-keyed under the new one (unit/contract test on `KeyringStorage`).
6. `Directories.shellConfig` resolves to `~/.config/immaterial-impulse`.
