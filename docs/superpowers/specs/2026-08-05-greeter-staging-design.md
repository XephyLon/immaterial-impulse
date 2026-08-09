# Greeter staging dir — root out of the hot path (Option B)

**Status:** implemented — imi-sddm-theme#15, pinned by this PR
**Decisions:** the recommendations below were taken as written, except Q8
(simplify: `set -e` plus the stamp as the last statement, no separate
stamp-after-success bookkeeping). Q4 followed from Q2 — the sudoers rule cannot
retire while matugen-only still escalates, so all three modes converted together.
Q6 (allowlisting the flattened keys) was deferred as orthogonal; staging already
moves Settings.qml from world-readable to 0640.
**Repos:** immaterial-impulse (hub), imi-sddm-theme (satellite)
**Parent:** `docs/superpowers/specs/2026-08-05-reactive-greeter-sync-design.md` (Option B
section is the seed; Option A is shipped and working)

## Problem

Option A made the greeter sync reactive and gated: the hub's `GreeterSync` service
observes the greeter-relevant config leaves, the satellite's `sddm-theme-sync.sh`
fingerprints what the greeter consumes and escalates only on a real change. That fixed
staleness and the still race — but every *real* change still ends in
`sudo sddm-theme-apply.sh`: a root process, fired from a user-space observer chain, that
parses user-controlled files and copies user-authored QML onto `/usr/share`. Root is
still in the hot path; the NOPASSWD sudoers rule that lets it run unprompted is a
standing grant the satellite's own installer has to defend with a path-ownership walk
(`setup.sh setup_sudoers`) precisely because one mistake turns it into `NOPASSWD: ALL`.

Option B moves the greeter's mutable inputs into an sddm-readable staging directory
that the *user* owns. The hot path becomes atomic user-space writes; root's involvement
shrinks to install and uninstall, which are already interactive `sudo` sessions.

## Current state (A), verified against the real scripts

Verified against the reference checkout at `/home/xephy/dev/imi-sddm-theme` and the hub
tree — not against the parent spec's summary.

**Hub — `services/GreeterSync.qml`.** A singleton observing
`Config.options.wallpaperSelector.wallpaperEngine.{activeProject, activePath,
activeType, activePreview, scaling}` and `Config.options.background.wallpaperPath`,
debounced 1.5s, serialized (a request landing mid-run re-arms the debounce instead of
stacking a second process). It runs exactly one thing:
`~/.config/imi-sddm-theme/sddm-theme-sync.sh`, existence-checked at fire time — absent
wrapper is a silent no-op, so the hub works on machines without the theme.
`Background.captureGreeterStill` pokes `GreeterSync.request()` after a successful still
write (`modules/imi/background/Background.qml:340`), closing the still race.
`tests/test_greeter_sync.py` pins the wiring. **The hub never names the apply script
and never invokes sudo** — that contract is what makes Option B a satellite-plus-
installer change with zero hub code edits.

**Satellite — `iiMatugen/sddm-theme-sync.sh` (the wrapper).** Single entry point for
every trigger (matugen's post_hook and the hub's observer). Serializes via
`flock` on `$SRC/.sync-lock`; runs `generate_settings.py`; fingerprints what the
greeter consumes — `sha256sum` of the generated `Settings.qml` + `Colors.qml`, plus the
derived still's identity (`stat -c '%n %Y %s'` on
`~/.cache/quickshell/wallpaperengine-stills/<activeProject>.png`, or `no-still:<proj>`)
— and compares against the `.last-applied` stamp. Unchanged → exit 0. Changed →
`sudo $APPLY`, and the stamp is written only after a successful apply (`set -e`), so a
failed apply is retried by the next trigger rather than recorded.

**Satellite — `iiMatugen/generate_settings.py`.** Copies the shell's
`~/.config/immaterial-impulse/config.json` (with an `illogical-impulse` fallback) into
`$SRC/config.json`, flattens the *entire* nested config into a single
`pragma Singleton` `QtObject` — one sanitized `property` per leaf, `_`-separated keys —
and writes `$SRC/Settings.qml`. Every flattened key lands there, greeter-relevant or
not.

**Satellite — `iiMatugen/sddm-theme-apply.sh` (the root hop).** Installed root-owned at
`/usr/local/lib/imi-sddm-theme/sddm-theme-apply.sh` (outside `$HOME` because the
sudoers rule names it by path). Running as root it:

1. parses `$SRC/Settings.qml` with grep/cut to extract the WE fields, mirroring the
   shell's `weActive` precedence (`activePath` non-empty and `activeType != web` wins
   over the static wallpaper);
2. resolves the wallpaper: a video project's asset (name read from `project.json` via
   an inline python), copied whole if ≤100 MiB, else a frame cut **by ffmpeg running as
   root** on the user's video; a scene's still at the *derived* path
   `$USER_HOME/.cache/quickshell/wallpaperengine-stills/<activeProject>.png` (derived
   from `activeProject`, never read from a stored field — immaterial-impulse#103);
   fallback `activePreview`; else `background_wallpaperPath`; else a comment line in
   `Colors.qml`;
3. `sed -i`-edits `$SRC/ii-sddm.conf` (`Background=`, `BackgroundPlaceholder=`);
4. copies into the installed theme with `chmod 644`:
   `$SRC/Colors.qml → $DEST/Components/Colors.qml`,
   `$SRC/Settings.qml → $DEST/Components/Settings.qml`,
   the wallpaper `→ $DEST/Backgrounds/background.<ext>` (+ `placeholder.png` for
   video), `$SRC/ii-sddm.conf → $DEST/Themes/ii-sddm.conf`.

It **rejects symlinked sources** (`validate_path` and the required-files loop) — a
defense against the user steering the root copy through a link. Note for later: that
threat exists only because root does the copying; it dissolves with the root hop.

**Theme resolution.** `metadata.desktop` names `ConfigFile=Themes/ii-sddm.conf`;
`Main.qml` reads `config.Background` etc. relative to the theme root. The setup-written
drop-in sets `GreeterEnvironment=QML2_IMPORT_PATH=$DEST/Components/`, and
`Components/qmldir` registers `singleton Settings Settings.qml` and
`singleton Colors Colors.qml` — **`Components/Settings.qml` is the registered
singleton; a copy at the theme root is silently ignored** (satellite AGENTS.md,
1793562). The greeter process runs as the `sddm` user: anything it must read has to be
readable by that user, and a background it cannot read is a greeter that fails to draw
(login-path failure class, not cosmetic).

**Installer.** `setup.sh` installs the apply script root-owned, writes the per-user
NOPASSWD sudoers rule (after walking every path component asserting root ownership and
no group/world write), points matugen's post_hook at the sync wrapper, and runs one
apply at install time. `uninstall.sh` reverts references before deleting the theme and
removes the sudoers rule *first* among the root artifacts. `check.sh` verifies, among
much else, that the generated `Colors.qml`/`Settings.qml` match the installed copies
(`check_theme_is_current`) and that the apply script's whole path is root-owned.

## Proposed design

### The staging directory

Created **once, at install time, as root**:

```
/var/lib/imi-sddm-theme/          owner <user>, group sddm, mode 2750
├── Settings.qml                  0640 (or 0644 — the 0750 dir already blocks others)
├── Colors.qml                    0640
├── ii-sddm.conf                  0640
└── Backgrounds/                  2750
    ├── background.<ext>          0640
    └── placeholder.png           0640 (video wallpapers only)
```

- `/var/lib` is root-filesystem, persistent, and the conventional home for
  machine-local mutable state; `/var/lib/<name>` matches the theme's existing naming
  (`/usr/local/lib/imi-sddm-theme`).
- **Owner `<user>`** so the hot path can write without escalation. **Group `sddm`**
  so the greeter can read. **Setgid (`2750`), not `0750`**: the user is not normally a
  member of the `sddm` group and cannot `chgrp` files to a group they don't belong to,
  so without setgid every file the wrapper writes would carry the user's primary group
  and be unreadable by the greeter. The setgid bit makes new files inherit the
  directory's group — that is what makes unprivileged writes come out sddm-readable.
- **Plain owner/group vs ACLs:** an ACL scheme (root-owned dir,
  `setfacl -m u:<user>:rwx,u:sddm:r-x`) expresses the same thing but is invisible to a
  casual `ls -l`, depends on the filesystem mounting with ACL support, and gives
  `check.sh` a harder property to verify. Plain `user:sddm 2750` states the whole
  contract in one `stat -c '%U:%G %a'`. Recommendation: plain owner/group; ACLs only if
  a real system turns up where the `sddm` group doesn't exist (it is created by the
  sddm package everywhere Arch-shaped, and the installer is Arch-only).
- Like today's sudoers rule, the staging dir encodes **one** user. Same single-user
  assumption, now structural (see Security).

### How the theme resolves staged content

Two mechanisms were analyzed; the answer is different for the QML pair than for the
conf/wallpaper, and that asymmetry is forced:

**The QML pair (Settings.qml, Colors.qml) can only be symlinked.**
`Components/Settings.qml` is the registered singleton — the QML import machinery
resolves it via `Components/qmldir` at that exact path, and there is no "absolute path
in a conf" equivalent for a QML module member. (Prepending a staging directory to
`QML2_IMPORT_PATH` so a staging `qmldir` shadows the module was considered and
rejected: it would shadow the whole `Components` module or none of it, and turns
import-order into a load-bearing mechanism.) So, install-time:

```
$DEST/Components/Settings.qml -> /var/lib/imi-sddm-theme/Settings.qml
$DEST/Components/Colors.qml   -> /var/lib/imi-sddm-theme/Colors.qml
```

**The conf and wallpaper could go either way; symlinks win.**

- *Absolute paths in the conf* (`Background="/var/lib/imi-sddm-theme/Backgrounds/…"`)
  would avoid a symlinked directory — but the conf itself still has to be mutable from
  user space (the apply rewrites `Background=`/`BackgroundPlaceholder=` per wallpaper
  type, and `Main.qml` derives image-vs-video from the `Background` value's extension,
  so a stable extensionless name is not available). A mutable conf means
  `Themes/ii-sddm.conf` is a symlink into staging anyway — at which point keeping the
  `Background=` values relative and symlinking `Backgrounds/` too is one mechanism
  instead of two. The conf's own comments also declare the paths relative-only;
  absolute values would ride on unverified behavior.
- *Symlinks throughout* (recommended):

```
$DEST/Themes/ii-sddm.conf -> /var/lib/imi-sddm-theme/ii-sddm.conf
$DEST/Backgrounds         -> /var/lib/imi-sddm-theme/Backgrounds
```

  The conf keeps `Background="Backgrounds/background.<ext>"`, resolved against the
  theme root exactly as today, through the directory symlink into staging. No greeter
  QML changes, no conf format changes, no `check.sh` precedence logic changes.

Everything else in the theme directory — `Main.qml`, the widget QML, fonts, qmldir,
`metadata.desktop` — stays root-owned regular files, exactly as now. The user-mutable
surface is precisely the four names above, and each is a symlink whose *target* sits in
a directory the user owns.

### The new hot path

`sddm-theme-sync.sh` keeps its shape — flock, generate, fingerprint, gate — and the
escalation line becomes an in-process, user-space apply:

1. Resolve the wallpaper exactly as the root apply does today (weActive mirror, video
   cap, ffmpeg frame cut, derived still, preview fallback) — **as the user**. The
   ffmpeg-parses-user-video and python-parses-project.json steps stop running as root.
2. Write each output into staging **atomically**: write to `.<name>.tmp` in the same
   directory (same filesystem, so `rename(2)` is atomic), `chmod 640`, `mv -f` over
   the real name. The setgid dir supplies the group. A reader — the greeter starting
   mid-sync — sees either the old file or the new one, never a partial write.
3. Rewrite `ii-sddm.conf` the same way (generate the new content, rename over), rather
   than `sed -i` in place.
4. Stamp `.last-applied` after all renames land, preserving A's retry-on-failure
   semantics.

**The fingerprint gate survives.** With no root hop the cost of a spurious apply drops
from "root copy onto /usr/share" to "a few user-space renames" — but the gate is still
what turns generous observation into a hash instead of a write burst (every matugen run
plus every observed leaf would otherwise re-cut video frames and rewrite multi-megabyte
backgrounds on no change). It stays as cheap write-avoidance; only its consequence
shrinks.

**The hub changes not at all.** `GreeterSync.qml` invokes the same wrapper path with
the same contract; `tests/test_greeter_sync.py` stays green untouched. matugen's
post_hook likewise keeps calling the wrapper.

**The sudoers rule leaves the hot path.** Install and uninstall already authenticate
interactively (`sudo -v`), so the NOPASSWD rule is not *needed* at all once the wrapper
stops escalating — see Open questions for whether to retire it outright or keep a
manual repair path.

## Login-safety analysis

The satellite's AGENTS.md opens with the failure class this section is about: if SDDM
cannot load its greeter there is no graphical login. Option B introduces a new
login-critical dependency — the staging directory — and four symlinks that can dangle.
That is the cost of the design and it has to be engineered, not hoped away.

**Severity is not uniform across the four links.**

- `Components/Settings.qml` and `Components/Colors.qml` dangling = a registered
  singleton that fails to import = the greeter's QML fails to load = **broken login**.
  These two are the critical pair.
- `Themes/ii-sddm.conf` dangling = SDDM's theme config read fails; `Main.qml` guards
  most `config.*` reads with fallbacks (`config.BackgroundSpeed || 1` etc.), but the
  conf also carries install-written `[General]` defaults, and a missing ConfigFile's
  exact behavior is SDDM-version-dependent — treat as **potentially login-breaking**.
- `Backgrounds` dangling = `AnimatedImage` gets `Image.Error`, `showFallbackColor`
  kicks in, the greeter draws on a flat color = **cosmetic degradation**, login works.
  `Main.qml` already handles this path today (it is what a missing background always
  did).

**Atomicity discipline, install-time and forever after:** the ordering rule the
satellite already lives by — *replacement first, repoint second, delete last* — applies
verbatim:

1. **Replacement first:** create staging and fully populate it (as root, at install)
   *before any theme file becomes a symlink*. Fresh install: populate from the shipped
   defaults (`Components/Settings.qml`, `Components/Colors.qml`, the source
   `ii-sddm.conf`, the default background) so the pre-first-matugen greeter renders
   exactly as it does today. Migration from A: populate from the *currently installed*
   theme copies (`$DEST/Components/*.qml`, `$DEST/Themes/ii-sddm.conf`,
   `$DEST/Backgrounds/*`) — the live state, not defaults, so the greeter is
   pixel-identical across the migration.
2. **Repoint second, atomically where it matters:** the three *file* symlinks are
   created at a temp name and `mv -f`/`renameat`'d over the regular file — `rename(2)`
   replaces a file with a symlink atomically, so there is no instant where
   `Components/Settings.qml` does not resolve. The `Backgrounds` *directory* cannot be
   atomically replaced by a symlink (`rename` refuses to clobber a non-empty
   directory); the swap is `mv Backgrounds Backgrounds.old && ln -s … Backgrounds`,
   whose failure window is confined to the one link whose dangling/absence is
   cosmetic — deliberately so. This asymmetry is why the critical pair must be file
   symlinks and never live behind a directory swap.
3. **Delete last:** `Backgrounds.old` is removed only after the symlink exists; on
   uninstall, staging is removed only after nothing references it (below).
4. An interruption at any step leaves every login-critical name resolving to valid
   content: before its rename, the old regular file; after, a symlink into
   already-populated staging.

**Half-migrated states:** each swap is per-file and idempotent — re-running setup
converges (a name that is already the correct symlink is left alone, a regular file is
swapped). There is no state where the migration must be completed before the machine
can boot; every intermediate state is a working greeter, matching how
`migrate_legacy_theme_name` was engineered.

**Staging missing entirely** (deleted by an aggressive cleaner, a botched uninstall, a
restored root partition without `/var`): the critical pair dangles and login breaks.
Mitigations, layered:

- **Self-healing (recommended):** ship a root-owned factory copy inside the theme
  (`$DEST/factory/` — the same four defaults staging is first populated from) plus a
  `tmpfiles.d` snippet (`/usr/lib/tmpfiles.d/imi-sddm-theme.conf`) that recreates the
  directory (`d /var/lib/imi-sddm-theme 2750 <user> sddm`) and copies the factory
  content in **only if missing** (`C` entries). `systemd-tmpfiles-setup.service` runs
  before display managers at boot, so a wiped staging heals into "fresh-install
  defaults" — a wrong-colored but working login — before SDDM starts. The next sync
  restores the user's actual state.
- **Detection:** `check.sh` gains a hard-FAIL check that every one of the four links
  resolves (`readlink -e`), with the critical pair called out as login-breaking.
- **Uninstall ordering** (below) never removes staging while the theme still links
  into it.

**Symlink-rejection inversion:** the apply script's current "no symlinked sources" rule
defends the *root copier* against link-following. Under B the copier is the user
touching their own directory, and the *installed theme* now contains symlinks by
design. The check disappears with the threat it guarded; `check.sh`'s
"root-owned along the whole path" walk retargets from the apply script to a new
assertion — the four link *names* live in root-owned directories (so only root can
repoint them) while their targets live in staging.

## Security analysis

**Trust equivalence — what B does not change.** Today, root copies user-authored QML
verbatim into the greeter: `Settings.qml` is generated from the user's config,
`Colors.qml` from the user's wallpaper via matugen, and `sddm-theme-apply.sh` moves
them into `/usr/share` unexamined. The greeter then *executes* that QML as the `sddm`
user, pre-authentication. User-to-greeter code flow is the existing design, with root
acting as a courier that inspects nothing. B changes who carries the bytes, not what
code the greeter runs — a wash, exactly as the parent spec called it.

**What improves.**

- **No routine root execution triggered from user-writable inputs.** Under A, every
  real change runs a root bash script that greps user-controlled QML, runs python over
  a user-controlled `project.json`, and runs **ffmpeg as root over a user-controlled
  video file** — a large, actively-exploited parser given root and fed attacker-
  shapeable input on every wallpaper switch. Under B all parsing and transcoding runs
  as the user; root executes nothing in the steady state.
- **The standing NOPASSWD grant can go.** The rule is the artifact `setup.sh` and
  `check.sh` spend the most defensive code on (the path-ownership walks exist because
  a rule naming a user-writable path is `NOPASSWD: ALL`). Retiring it removes the
  grant *and* the class of misconfiguration around it.
- **Confidentiality, incidentally.** `generate_settings.py` flattens the *entire*
  config into `Settings.qml` — every key, including any the user would consider
  private (quote text, launch commands, and whatever the schema grows, e.g. AI
  provider fields). Today that file sits world-readable (`chmod 644`) under
  `/usr/share/sddm/themes`. In a `2750` staging directory it is readable by the owner
  and the `sddm` user only. (Filtering the generated keys to an allowlist is a
  further, orthogonal improvement — see Open questions.)

**The multi-user caveat, stated honestly.** The greeter is a shared, pre-auth surface:
every user of the machine types their password into it. Under both A and B, *one*
user's config drives the QML that surface executes — that user can, by construction,
run code as `sddm` while any other user authenticates, which is keystroke distance
from every account's password. A did this with root's help; B does it with a
user-owned directory, making the single-user assumption structural rather than
procedural. Neither is appropriate on a machine with mutually-untrusting users, and B
does not pretend to fix that: fixing it would mean a root-curated pipeline (which is A,
kept) or greeter-side sandboxing of theme QML (which does not exist). The spec's claim
is strictly: *on the single-human machines this project targets, B removes real attack
surface (root parsers, a standing sudoers grant) while changing nothing about who can
influence the greeter.*

## Migration from A

All satellite + hub-installer work; zero hub QML changes.

**`setup.sh`:**
- New install step (root, once, after `install_theme`): create staging `2750
  <user>:sddm`, populate (fresh install → shipped defaults; existing install → the
  currently-installed theme's copies), then swap the four names to symlinks with the
  ordering above. Idempotent, so re-running setup migrates an A install in place.
- `setup_sudoers` retires (or shrinks to whatever Open question 2 decides). The
  path-ownership walk goes with the rule it defended.
- The apply script stops being installed to `/usr/local/lib`; its resolution logic
  moves into the wrapper (or a user-space `sddm-theme-apply.sh` the wrapper sources —
  naming TBD, but *no* copy outside `$HOME` and no sudoers rule naming one). An
  existing A install's root-owned copy and rule are removed on migration, mirroring
  what `remove_sudoers` does today: rule first, then the script dir.
- The install-time "apply once" becomes a plain run of the wrapper as the user.
- If the tmpfiles.d hardening is adopted: install `$DEST/factory/` and the snippet, and
  run `systemd-tmpfiles --create` once.
- matugen-only mode's post_hook currently calls `sudo $APPLY` directly with no
  wrapper; under B it must switch to a wrapper-style user-space apply too (the
  `Matugen/` variant grows the same sync script, minus `generate_settings.py`). Scope
  question 4 covers sequencing.

**`uninstall.sh`:**
- Existing reference-reverting order is untouched and still first.
- `remove_theme`'s `rm -rf $DEST` already handles a theme containing symlinks
  (removes the links, not their targets). Staging is removed **after** the theme
  directory is gone — with the theme gone nothing dangles, honoring delete-last.
- Removes the tmpfiles.d snippet (if adopted) alongside.
- `remove_sudoers` **stays**, permanently: it is what cleans up A-era installs (the
  rule, `/usr/local/lib/imi-sddm-theme`, and the pre-move in-home copy), and B's
  uninstall must keep removing artifacts B itself no longer creates.

**`check.sh`:**
- New: staging exists, is `2750 <user>:sddm` (the setgid bit is load-bearing —
  check it explicitly), and each of the four theme names is a symlink that resolves
  (`readlink -e`); the critical pair failing is FAIL, `Backgrounds` failing is WARN.
- `check_theme_is_current` retargets: compare `$SRC` generated files against
  *staging*, not against `$DEST/Components`.
- `check_apply_script` inverts: the root-owned apply script and the sudoers rule
  become "leftover from a pre-staging install — re-run setup.sh" warnings rather than
  requirements; `check_sudoers`'s "rule names the right path" logic goes with it.
- `check_matugen_conf`'s "post_hook calls `$APPLY_SCRIPT`" expectation updates to the
  wrapper.

**The sync wrapper:** survives as the single entry point with flock and the
fingerprint gate intact (cheap write-avoidance, per above); only the escalation line
is replaced by the atomic staged writes. The hub's `GreeterSync` contract — "invoke
the wrapper, absent is a no-op" — is untouched, which is the payoff of A having routed
everything through one script.

**Sequencing:** satellite implements and releases first; the hub then bumps `SDDM_REF`
in `sdata/subcmd-install/5.sddm-theme.sh` *and* `sdata/subcmd-uninstall/0.run.sh`
together (`test_sddm_theme_source.py` pins them). Existing A installs migrate on their
next Update Dots run; until then A keeps working unchanged — nothing in B breaks an
un-migrated install.

## Open questions for the user

1. **Ownership mechanism:** plain `user:sddm 2750` (recommended: visible, greppable,
   no ACL dependency) vs a root-owned dir with POSIX ACLs?
2. **Sudoers rule:** retire outright (install/uninstall already prompt), or keep a
   NOPASSWD rule + minimal root apply as a documented manual repair path? Retiring is
   cleaner; keeping preserves a recovery lever that works when staging is broken.
3. **Self-healing:** adopt the `factory/` + tmpfiles.d recreate-if-missing hardening,
   or keep the footprint smaller and rely on `check.sh` detection plus re-running
   setup? (Recommended: adopt — it converts the one new login-breaking state into a
   cosmetic one, at the cost of one shipped directory and a 3-line snippet.)
4. **Scope:** convert only the `ii-matugen` mode first, or all three install modes
   (`matugen-only` currently sudo-applies directly from the post_hook; `no-matugen`
   only applies at install time) in the same change?
5. **Wallpaper mechanism:** confirm the symlinked-`Backgrounds`-directory choice over
   absolute paths in the conf (the analysis above recommends symlinks; absolute paths
   would need verifying SDDM/QML behavior the conf's comments advise against).
6. **Settings.qml key filtering:** should B also narrow `generate_settings.py` to an
   allowlist of greeter-consumed keys, closing the "entire flattened config readable
   by the sddm user" exposure (today it is world-readable, so B already improves
   this)? Orthogonal, but the same PR could carry it.
7. **Path:** is `/var/lib/imi-sddm-theme` the right home, or is a subdirectory of the
   theme's existing `/usr/local/lib/imi-sddm-theme` preferred (keeps one prefix, but
   mixes executable and mutable-data conventions)?
8. **A's stamp semantics:** with the root hop gone, "apply failed" collapses to
   disk-full/ENOSPC-class errors. Keep the stamp-after-success discipline as is
   (recommended, it costs nothing), or simplify?
