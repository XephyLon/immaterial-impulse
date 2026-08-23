# AGENT.md

Reference for coding agents (and humans) working in this repository. This file explains what the
project is, how it's put together, and where things live. See `CONTRIBUTING.md` for how to work in
it day to day.

> **Read this file and then `CONTRIBUTING.md` sequentially, in full, top to bottom, before any
> work — and again after a context compaction.** Grep hits and section jumps are not reading:
> the rules that get broken are the ones adjacent to the section someone jumped to, and that is
> how 5d4bfa773 ("feat(wallpaperEngine): reinstate activeStill, this time with a writer") shipped
> a regression this file had the material to prevent. Every point added to this file or
> `CONTRIBUTING.md` must cite the commit that motivated it as `<sha> ("<subject>")` — format and
> enforcement in `CONTRIBUTING.md` → "Keep AGENT.md in sync".

> **Repository layout.** This repo bundles more than the shell. The Quickshell theme lives under
> `dots/.config/quickshell/imi/`; the installer is `setup` + `sdata/`; project docs are in `docs/`.
> **Unless a path is written repo-relative (e.g. `dots/...`, `sdata/...`, `docs/...`), file paths in
> this document are relative to the theme root `dots/.config/quickshell/imi/`** (so `modules/...`,
> `services/...`, `shell.qml` mean `dots/.config/quickshell/imi/modules/...`, etc.).

## What this is

`Immaterial Impulse` (ImI) is a **Quickshell** shell configuration for **Hyprland** — a full desktop
UI (bar, docks, sidebars, on-screen displays, notifications, launchers, lock screen, etc.) written
entirely in QML and run by the [Quickshell](https://quickshell.org) runtime (`qs`), not a compiled
application.

It originated as a fork of [illogical-impulse](https://github.com/end-4/dots-hyprland) (by `end-4`)
by way of `pctrade`'s `end4-pC`, but **it is no longer a fork in any operational sense** — it is an
independent project that happens to share ancestry.

```
end-4/dots-hyprland  →  pctrade/end4-pC  →  Immaterial Impulse (independent as of 0.7.0)
```

**There is no upstream.** The `pctrade/end4-pC` and `end-4/dots-hyprland` remotes are gone and
neither is fetched, merged, or diffed against any more. Do not add them back, do not "check what
upstream does" when making a design decision, and do not preserve a shape purely because it keeps a
future merge tractable — that constraint no longer exists. `gh` is the publishing remote
(`XephyLon/immaterial-impulse`).

Attribution to `end-4` and `pctrade` stays in `LICENSE`, `licenses/`, and the README credits — the
project is GPL-3.0 and the ancestry is real. Independence is about direction, not erasure.

This directory is **not a standalone app repo** — it's dropped into `~/.config/quickshell/imi`
on a running Hyprland system and loaded by `qs -c imi`. ImI ships the whole suite, so it supersedes
a prior illogical-impulse install rather than coexisting with one: the companion Hyprland config
lives alongside it in this repo (installed separately to `~/.config/hypr/`) and provides the
keybinds, IPC event names, and layer-shell behavior assumptions this shell depends on.

## Before you restore something that was removed

**If code, a field, or a file is missing where you expected one, find out why it went before you put
it back.** "It looks like an oversight" is not a finding. The removal has a commit, and usually an
issue, and that reasoning is the requirement you are about to work against.

Concretely, before re-adding anything:

1. `git log -S '<the thing>' --all` for the commit that removed it, and read the **whole** message.
2. If it cites an issue or PR, read that too — `gh issue view N` / `gh pr view N`, not the title.
   These are separate: `gh pr view 103` fails on this repo because 103 is an **issue**.
3. Only then decide. If the reasoning still holds, the gap is intentional and your problem needs a
   different answer. If it no longer holds, say so explicitly in the commit message and address what
   the original removal was protecting against.

The worked example, because it cost a full day and shipped a regression:

`wallpaperSelector.wallpaperEngine.activeStill` (introduced by 6a0c19e45 ("feat(wallpapers):
render and cache a full-scene still per live wallpaper"), orphaned a day later by ce7e90327
("refactor(wallpaperEngine): gut runtime renderer to selector-only")) was removed by
[#103](https://github.com/XephyLon/immaterial-impulse/issues/103) — a stored path to a rendered
wallpaper still, with no writer after the Wallpaper Engine renderer moved in-process, frozen at
whatever project was active that day, and served to the SDDM greeter for months.
[#113](https://github.com/XephyLon/immaterial-impulse/issues/113) then reported the low-resolution
greeter background that #103 had **explicitly predicted and accepted** as the cost.

[#117](https://github.com/XephyLon/immaterial-impulse/pull/117) "fixed" #113 by re-declaring the
field and giving it a writer (5d4bfa773 ("feat(wallpaperEngine): reinstate activeStill, this time
with a writer")) — a subprocess that launched a **second** `linux-wallpaperengine` to photograph a
frame this shell was already rendering in-process. Nobody had read #103. Three things followed:

- the fix rebuilt the exact pre-embed mechanism the embedded renderer exists to eliminate;
- re-declaring the property re-armed the stale values still sitting in every saved preset (see the
  `JsonAdapter` note under [The Config system](#the-config-system-settings-page--persisted-json) —
  presets are separate files it never rewrites), so #103's bug came back;
- #103's actual fix direction ("derive it, don't store it") was sitting in the issue the whole time.

The correct answer was in the removal's reasoning. Reading it first would have skipped all of it —
the eventual fix (03b8b0298 ("fix(wallpaperEngine): derive the greeter's still path, do not store
it")) is #103's own fix direction, implemented a day and two reverted mechanisms late.

## Runtime model — read this before assuming anything about "building" or "compiling"

There is no build step. Every `.qml` file is interpreted live by the `qs` process. When any `.qml`
file under this directory changes on disk, **the entire shell hot-reloads** (you'll see
`[To Do] File loaded` / `[Notifications] File loaded` lines in the log when this happens — those
two singletons happen to log on every full reload, which makes them a convenient reload marker even
though the message text doesn't literally describe what changed).

Do not perform a long series of edits or file moves against this checkout while its live
Quickshell instance is running. Each write can trigger a full reload; repeated reloads during an
inconsistent module move have coincided with shell and whole-session starvation. Stop Quickshell
or use a worktree, validate headlessly, then perform one controlled live load.

- Entry point: `shell.qml` → loads a **panel family** (currently only `"imi"`, from
  `panelFamilies/ImmaterialImpulseFamily.qml`) which is a flat list of `PanelLoader { component: X {} }`
  entries, one per top-level feature module.
- Singletons (declared with `pragma Singleton`) are the shell's shared state and services. They are
  addressed by their QML type name directly (e.g. `Config`, `GlobalStates`, `Audio`) — no explicit
  import needed beyond the directory-level `import qs.services` / `import qs.modules.common`.
- QML singletons appear to **persist across most hot-reloads** rather than being torn down and
  recreated the same way scene components are — don't assume editing a singleton always produces
  an immediately-visible fresh instance; when in doubt, verify with a temporary `console.log` in an
  `onXChanged` handler (see CONTRIBUTING.md's verification workflow).
- **A singleton is constructed on first use, so a service whose only caller is a lazily-evaluated
  binding does not start when you think it does.** Anything a singleton kicks off at construction
  — a detection `Process`, a poll timer, a file read — is deferred until something actually reads
  one of its properties. `PrismLauncher` is reached only from `LauncherSearch`'s `results` binding,
  which does not evaluate until the user types, so its "run at startup" detection had in fact not
  started when the first query was answered: measured, the first search came back with no modpacks
  and only the second had them. If a service must be warm before its first consumer runs, construct
  it explicitly from a `Component.onCompleted` that does run early — reading any property is what
  constructs it. This is separate from the reactive-observation rule below: the binding was correctly
  reactive, it just had nothing to observe yet. (feat(search): launch Minecraft modpacks from the
  search bar.)

### Where to look when something goes wrong

The running `qs` process writes two logs per instance, found under
`/run/user/<uid>/quickshell/by-id/<hash>/`:

- `log.log` — human-readable, this is the one to `tail`/`grep`. Contains `DEBUG qml:` lines (your
  `console.log` output), `WARN scene:` (QML runtime errors/warnings with file:line), and other
  component warnings (D-Bus, desktop entries, etc.).
- `log.qslog` — a much larger structured/binary trace log. Rarely worth reading directly; `log.log`
  covers almost everything needed.

Find the current instance's log with:
```bash
ls -la /proc/$(pgrep -x quickshell)/fd | grep log.log
```

**Match the process by exact name, never with `pgrep -f`/`pkill -f`.** `-f` matches against whole
command lines — *including the command line of the shell running the `pgrep`*. So
`pkill -f "quickshell -c imi"` kills the shell and the tool process that invoked it; it has
truncated a file copy mid-deploy here and left a half-written config behind. `-x` matches the
executable name and cannot match its own caller:
```bash
pgrep -x quickshell        # the running shell's pid
pgrep -a quickshell        # ...with its full command line
```
`qs` and `quickshell` are both fine to *launch* with — `qs` resolves to
`/usr/local/bin/quickshell`, and the prebuilt the installer pins runs from
`~/.cache/immaterial-impulse/prebuilt/<ref>/bin/quickshell`. But whichever you type, the process
name is `quickshell`, so that is what `-x` has to match: `pgrep -x qs` returns nothing even while
the shell is up, which reads as "the shell is down" and leads to launching a second instance on top
of the user's.

When `-f` is genuinely required — matching on an argument rather than a name — use the bracket
trick so the pattern cannot match its own literal text: `pkill -f '[m]pvpaper'`.
`tests/lint_self_matching_process_patterns.py` fails the suite on a bare `-f`. It is a check rather
than a note because the note existed: two plan documents already warned about this trap, and it was
hit anyway. d1ac2da36 ("test(lint): fail on a pgrep/pkill pattern that matches its own caller").

Do not leave the primary shell running through a rapid multi-file patch series. Each source change
hot-reloads QML and rebuilds the desktop-entry registry; large Wine/Steam application collections
can turn repeated reloads into millions of parses, multi-gigabyte RSS, and an apparent freeze. Kill
the one primary instance before the edit batch and start exactly one clean daemon after validation.

**Grep `ERROR`, not just `WARN`.** A `WARN scene:` line is a runtime warning in an otherwise
working shell; `ERROR: Failed to load configuration` means the config did not load *at all* and the
user has no panels. The error is reported as a cascade from `shell.qml` down to the file that
actually failed — the **last** `caused by` line is the real culprit:
```
ERROR: Failed to load configuration
ERROR:   caused by @shell.qml[50:20]: Type ImmaterialImpulseFamily unavailable
...
ERROR:   caused by @modules/imi/sidebarRight/calendar/CalendarHeaderButton.qml[13:5]: Cannot override FINAL property
```
Because a single bad widget takes down every panel that transitively reaches it, **confirm
`Configuration Loaded` appears after the reload** rather than only checking that no warnings did.

**`tests/run_tests.sh` cannot catch this class of bug.** The QML suite instantiates pure-logic
singletons and never builds these widgets, so a widget that fails to compile leaves the suite fully
green. Only a live load surfaces it.

**Gotcha — FINAL properties:** anything deriving from `RippleButton` (and so from QQC2 `Control`)
must not declare `horizontalPadding`, `verticalPadding`, `padding`, `spacing`, `font`, `palette`, or
`icon` as its own property; those are `FINAL` and overriding one is a hard compile failure. Pick a
distinct name (`labelInset`, not `horizontalPadding`). A plain `Item`/`Rectangle` has no such
restriction, which is why `property real padding` is fine in the many non-`Control` widgets here.

**A `qml6` probe's `console.log` goes to the journal, not to your terminal.** Qt is built with
journald support here, so `qml6 probe.qml` prints *nothing at all* — which reads as "the probe never
ran" and invites rewriting a probe that was working. Export `QT_FORCE_STDERR_LOGGING=1` alongside
`QT_QPA_PLATFORM=offscreen` whenever a probe is supposed to tell you something.
f6a7e251e ("feat(designsystem): VisualizerCookie, a cookie driven by one level per lobe").

**Known quirk:** `console.log` output to `log.log` can appear noticeably delayed (stdio buffering) —
a print can sit unflushed for several seconds before showing up, sometimes interleaved with later
events in a way that looks like a stale/wrong value at first glance. If a debug print looks wrong,
wait and re-check before concluding the code is broken.

## External binaries the shell drives

Two non-obvious traps live here, both found the expensive way.

**`DT_RUNPATH` is not transitive, and `LD_LIBRARY_PATH` is.** The Wallpaper Engine build the shell
loads (`~/.cache/immaterial-impulse/prebuilt/<ver>/`) bundles its own libraries. Setting a correct
`RUNPATH` on the *executable* resolves only that executable's **direct** dependencies — a bundled
`liblinux-wallpaperengine-lib.so` looks up *its* dependencies (e.g. `libcef.so`, sitting in the same
directory) through **its own** `RUNPATH`, which was the build machine's. Every bundled `.so` must be
patched, not just the binary. The `LD_LIBRARY_PATH` fallback appears to work precisely because it
*is* transitive — and it leaks into every process the shell spawns, shadowing system libraries for
every application launched from the desktop. If you find yourself exporting it, the `RUNPATH` is
still wrong. `patchelf` rewrites in place, so patching a **running** executable fails with `ETXTBSY`;
copy, patch the copy, then `rename(2)` over the original. Learned across 156b4703b ("fix(install):
repair the RUNPATH via a rename, not in place") and 3e07c2a5d ("fix(install): repair the bundled
libraries' RUNPATH too, not just the binary") — the first shipped believing it was the whole fix.

**`gpu-screen-recorder` does not tonemap.** Handed an HDR surface with an SDR codec it encodes 8-bit
and tags the file `bt709`, so a PQ signal is decoded as gamma — flat, grey, desaturated, with nothing
in the logs. `scripts/videos/record.sh` therefore detects HDR and selects the `_hdr` codec variant.
The authoritative signal is Hyprland's `colorManagementPreset` (`hdr`/`hdredid`), **not**
`currentFormat`: a wide-gamut SDR monitor also reports `XBGR2101010`. H.264 cannot carry HDR at all,
so an explicit H.264 choice is respected and explained rather than silently overridden.
(307c8b4ae ("fix(record): pick the HDR codec when capturing an HDR monitor").)
The capture fix only moves the wash-out to the consumer's machine — a correct HDR10 file still
renders flat in anything that does not tonemap (VLC defaults, Discord, browsers). Delivery is the
opt-in `screenRecord.tonemapSdr`: `scripts/videos/tonemap-sdr.sh`, invoked from the `gsr-saved.sh`
hook on every save (recordings *and* replays — replays never pass through `record.sh`), probes and
tonemaps to bt709 in the background, replacing the file atomically (d7113f84c ("feat(record):
opt-in SDR tonemap after every save")). Probe trap from that commit: ffprobe's **CSV output grows
an extra field from a real recording's side data**, so a strict match on the transfer value
silently classifies every real HDR file as SDR — synthetic fixtures have no side data, which is why
only a live file catches it. Use value-only output (`-of default=nw=1:nk=1`) and trim delimiters.

Three more from the same pipeline (4a33f970e ("feat(record): capture SDR through the portal when
SDR delivery is on"), acb9b4906 ("perf(record): GPU encoder ladder, and the pipefail bug that hid
the GPU")):

- **Hyprland tonemaps screencopy for capture clients** — grim screenshots of an HDR desktop look
  right, and gsr's *portal* capture rides the same compositor path, yielding native SDR. Its KMS
  capture reads the scanout plane and gets raw PQ. **Portal restore tokens are opt-in and default
  OFF**: xdph only issues one when the share picker's "Allow a restore token" checkbox is ticked
  (`src/portals/Screencopy.cpp` gates `restore_data` on the picker's `r` flag), and
  `screencopy:allow_token_by_default = true` — shipped in `dots/.config/hypr/xdph.conf` — is what
  pre-checks it. Without that, `-restore-portal-session` is a silent no-op and the picker prompts
  on **every** recording; gsr's log line `saved restore token to cache ()` in that state is gsr
  echoing its own empty cache buffer, **not** an xdph response — an earlier version of this entry
  misread it as "xdph returns an empty token" and portal capture was removed on that misdiagnosis
  ("fix(record): drop portal capture - xdph returns an empty restore token"), then restored with
  the shipped config once a 22-byte token was demonstrated round-tripping live: second recording
  produced frames within one second, zero interaction. Lesson: a log line about a cache is
  evidence about the cache, not about the peer — read the source of *both* sides before blaming
  either.
- **`cmd | grep -q` under `set -o pipefail` reads as failed on success**: grep -q exits at the
  first match, the producer takes SIGPIPE, and the pipeline's status is the producer's 141. The
  converter's GPU detection was invisible-broken this way from its first version — every tonemap
  ran on the CPU, nothing logged. Capture to a variable and match on that.
- **NVENC's H.264 tops out at 4096px wide** and rejects wider frames with a misleading "No capable
  devices found" — at 5120x1440 the h264_nvenc rung can never succeed; use HEVC past 4096. And
  ffmpeg's `-encoders` list advertises build capability, not working hardware — try encoders for
  real, in a ladder with a CPU floor.

**ffmpeg's `tonemap` filter assumes a signal peak of 10× reference white (2030 nits) for PQ input,
and that assumption is the difference between a recording that looks like the desktop and one that
does not.** A desktop capture peaks around 235 nits — roughly 1.16× — so the converter was
normalising the curve against a peak eight times too high and squeezing the whole image into the
bottom eighth of it: SDR white came out of `tonemap-sdr.sh` at **136/255**, contrast collapsed with
it, and every recording the user made was a region capture, which is the path that converts. The
10× is a constant, not something derived from the file: `peak=10.0` reproduces the old output byte
for byte. `scripts/videos/tonemap-sdr.sh` now measures the peak off the pixels (`signalstats` over
keyframes only, downscaled first — bounded at 0.3s on a 5s 5120x1440 clip, and the result lands on
the content's p99.99 rather than on one stray pixel) and passes it to every chain.
fb9556757 ("fix(record): measure the tonemap's signal peak instead of assuming 10x").

Four things around that are worth not re-deriving:

- **gpu-screen-recorder stamps the *monitor's* EDID luminance into every recording** as
  mastering-display and content-light-level metadata — on a 1015-nit panel every file claims
  `MaxCLL 1015` whatever is on screen. This is a real defect and it is **not** what caused the
  wash-out: the CPU `tonemap` filter never reads that metadata, and two fixtures tagged 250 and
  1015 nits tonemap identically. It reaches only libplacebo, which does read it, which is why that
  chain gets `src_max`. Correcting the file's metadata would fix nothing on the path that runs.
  This is the same shape as the `playerctld` misdiagnosis under
  [State propagation is reactive](#state-propagation-is-reactive-or-it-is-a-bug-waiting): a correct
  observation about a real bug, that was not the bug in front of anyone.
- **A peak *below* the signal's own values blacks the frame out**, it does not stretch it — measured
  Y'=16 on a 100-nit clip given `peak=0.49`. So the measured peak is floored at 1.0, and a test for
  that floor needs a two-sided band; the first version asserted only "not brighter than" and passed
  on a black frame.
- **The compositor is the only thing that converts this correctly, and the portal is how to reach
  it.** grim and gsr's portal capture agree to 4.0/255 against each other, so either serves as the
  reference for "what the desktop looks like"; the best ffmpeg chain scores 15.2. That gap is
  Hyprland's own screencopy curve, which is not a linear-light inverse and cannot be matched by
  `npl` alone — measured, the `npl` that reproduces white (134) and the one that minimises overall
  error (203) are different numbers. Fullscreen recordings already take the portal. **Regions
  cannot**: `-region` is rejected outright with `-w portal` ("option -region can only be used when
  option '-w region' is used"), so the conversion is unavoidable there and its quality is capped.
- **Scoring a colour conversion needs a static-pixel mask, not a screenshot pair.** A desktop moves
  between two captures, and the drift swamps the effect being measured — the first pass here
  "measured" a reference white of 204 nits that way and 134 once only pixels identical across
  bracketing shots were compared. Bracket the recording with screenshots, keep pixels that match in
  both *and* whose 3×3 neighbourhood is uniform (which kills subpixel edges), and report RMSE plus
  what code 255 became.

**A sound event is one `pw-play` on a path the shell resolved, and neither half of that sentence
was true before.** `Audio.playSystemSound()` built
`/usr/share/sounds/<theme>/stereo/<event>.oga` and the same with `.ogg`, spawned an `ffplay` at
each, and let the wrong one fail silently. Measured against the six themes on this machine, that
guess is wrong in four distinguishable ways at once, and none of them reaches a log: no theme ships
both extensions for the same event, so the second spawn is *always* wasted (~50 ms, ~38 ms CPU,
53 MiB peak, 165 shared objects mapped, to print `No such file or directory`); `oxygen` and
`harmony2` are `.ogg`-only while the other four are `.oga`, so which of the two is the wasted one is
a property of the theme; `Pop` declares `Directories=stereo/alert stereo/action stereo/notification`
and keeps every file under those, so a hardcoded `stereo/` reached 0 of its 25 sounds and that theme
was **entirely silent**; and with no `Inherits=` walk, `oxygen` — which ships neither `complete` nor
`suspend-error` — lost the battery-charged chime and the suspend-failure alert even with
`freedesktop` installed beside it. `~/.local/share/sounds` was never searched at all.

Three things about the replacement generalise past sound.

- **Playback stays a process spawn even though QtMultimedia works here.** Probed with `qml6`: it
  decodes and plays a `.oga` fine. It also takes a bare QtQuick process from 65 MiB / 133 mapped
  shared objects to **113 MiB / 238** and keeps it there for the life of the shell whether or not a
  sound is ever played, writes a three-line ffmpeg `Input #0, ogg, from '<path>'` decode banner to
  stderr on *every* play, and floods five multi-kilobyte `spaVisitChoice: parse error` lines from
  PipeWire when the first player is constructed — all of it into the `log.log` this document tells
  you to tail. A spawn is 6.3 ms of CPU, freed on exit, and is a command list a test can read. Prefer
  the mechanism you can observe.
- **`pw-play`, not `ffplay`, and the reason is dependency declaration rather than taste.** `pw-play`
  ships in `pipewire-audio`, a hard dependency of the `pipewire-pulse` that `sdata/deps-info.md`
  lists; `ffplay` comes from `ffmpeg`, which this repo installs only inside the Wallpaper Engine
  build's dependency list and names nowhere as a shell dependency. It is also 7.4x cheaper (15
  mapped libraries against 165). Before adding a `Process` command here, check `sdata/deps-info.md`
  for the binary rather than for whether your machine happens to have it.
- **The engine is three pieces so that the decisions are testable.** `scripts/sounds/
  scan-sound-themes.py` reports what is on disk and judges nothing — it does not even filter by
  extension, because "that file is not a sound" is a judgement and `ocean` ships
  `power-unplug.oga.license` beside its sounds to catch anyone making it loosely.
  `services/sound_theme.js` makes every decision and touches no disk. `services/SoundTheme.qml`
  owns only the process lifetimes. That split is what lets `tests/tst_sound_theme.qml` cover the
  `Inherits=` walk (breadth-first with a visited set, so a cycle terminates and a diamond is visited
  once), the implicit fallback to the default theme, the per-theme subdirectory list, and the
  `.disabled` marker — which stops the walk rather than falling through, since inheriting past it
  plays a *wrong* sound rather than a missing one.

`SoundTheme` is also a live instance of the "a singleton is constructed on first use" trap under
[Runtime model](#runtime-model--read-this-before-assuming-anything-about-building-or-compiling): the
only thing that reaches it is a `play()` call, so the theme scan has not *started* when the first
sound is asked for. Measured with a `qs -p` probe — a `play()` from `Component.onCompleted` reports
`ready=false pending=1`, and a moment later `ready=true pending=0` with one `pw-play` carrying the
resolved path. It holds up to four events and flushes them from the scan's `onExited` rather than
from a successful parse, so a scan that fails outright still clears the queue.
8b31496c3 ("feat(sounds): a testable XDG sound-theme resolver"),
cbd8e707e ("feat(sounds): scan the sound-theme roots into one catalogue"),
a3a8f65cf ("fix(sounds): play one resolved file instead of two guessed ones").

## The suite checkout, and why the updater cannot just reset it

`get.sh` keeps the whole suite in `~/.local/share/immaterial-impulse/src` (`Directories.suiteSrc`),
clones it once and re-uses it for every update — Settings > About > **Update Dots** spawns a kitty
running the same script. That directory is a **normal git repository the user can work in**, and
someone hacking on their own shell does exactly that, so the update path may not simply make it
match `$REF`: `git checkout -f` + `git reset --hard FETCH_HEAD` destroy commits made there,
uncommitted edits, and any untracked file the incoming tree carries a path for (`-f` overwrites
those; untracked files it does *not* name, and stashes, both survive a reset untouched).

It still resets — landing on `$REF` is the updater's whole job, and aborting on a dirty tree would
tax every user who has no local work for the sake of the one who does. What it does first is move
whatever those two commands would eat somewhere git can name it back: the old HEAD onto
`imi-rescue/<short-sha>` (named for the commit, so re-running does not litter the checkout with one
ref per update), and the at-risk working-tree paths into a stash.

Three non-obvious pieces:

- **In a `--depth 1` checkout, ancestry cannot answer "does this HEAD belong to the remote".** Both
  HEAD and the incoming tip are grafted, so `merge-base --is-ancestor` walks nothing and says "not
  an ancestor" for a checkout that is merely a few commits *behind* — indistinguishable from one
  that is ahead. The script therefore records what it installed in `refs/imi/installed` and trusts
  a HEAD equal to that marker; the ancestry test stays as the answer for the full-clone fallback.
  A checkout predating the marker gets rescued conservatively, once.
- **A stash needs a git identity, and a machine being installed for the first time often has
  none** — git then refuses to write the stash commit. `get.sh` borrows one (`git var
  GIT_COMMITTER_IDENT` is the probe) rather than losing the work. Any other stash failure aborts
  the update, because proceeding *is* the data loss.
- **Printing the rescue to the terminal is not telling the user.** `setup`'s whiptail menu paints
  over the scrollback seconds later, in a terminal the shell spawned, so the same text is appended
  to `rescued-local-work.log` beside the checkout and — when stdin is a tty — the script waits for
  Enter before handing off.

`tests/test_get_sh_preserves_local_work.py` drives all of it against throwaway origin/DEST repos in
a tempdir; the clean-checkout case asserts the update stays *silent*, which is the half that keeps
the fix from becoming a nuisance for everyone who has no local work.
d5d2f69b0 ("fix(get.sh): rescue local work before resetting the update checkout").

**A Python dependency is declared in `sdata/uv/requirements.in` and installed
from `sdata/uv/requirements.txt`, and adding it to the first does nothing.**
`install-python-packages` runs `uv pip install -r requirements.txt`, which is a
compiled lock; the `.in` is the input a human edits and nothing at install time
reads. `onnxruntime` was added to the `.in` when the subject-mask producer landed
and the lock was never recompiled, so **every venv the installer has ever built
lacks it** — and the only symptom is a raw `ModuleNotFoundError` surfacing in the
depth picker at the moment the user presses a button, on a machine where that
path has never once worked. It ran on the author's machine because it had been
installed by hand. Recompile with the existing lock as preferences
(`uv pip compile requirements.in -o requirements.txt` in that directory, with
`requirements.txt` already present) rather than from scratch, or the diff for one
package moves every pin in the file — and this venv exists precisely because a
moving `numpy` is what breaks segmentation stacks (the design doc's own §1.1
finding). A check that reads the `.in` is checking the wrong file and stays green
for the whole life of the bug; `tests/test_clock_depth_cache.py` reads both now.
(fix(install): put onnxruntime in the lock the installer actually installs.)

## Directory map

```
shell.qml                  Entry point, loads the active panel family
GlobalStates.qml            Singleton: ephemeral UI state (sidebar open?, bar open?, OSD open?, ...)
ReloadPopup.qml, welcome.qml, killDialog.qml   Misc top-level overlays

modules/common/             Shared, feature-agnostic building blocks
  Config.qml                 Singleton: the entire settings schema + JSON persistence (see below)
  Appearance.qml              Singleton: design tokens - colors (M3 color roles), font sizes,
                              rounding, spacing, border widths, animation curves/durations, sizes.
                              Every widget reads from here rather than hardcoding values.
  motion_policy.js           The motion policy as arithmetic, beside interaction_motion.js and for
                              the same reason - the DECISIONS are testable and the rendering is not.
                              How a catalogued duration is scaled by the speed multiplier, where the
                              reduce-motion floor is and who may reach it, and how a group of things
                              arrives in sequence (visible rank, clamped ladder, step as a fraction
                              of a tier). Pure: every input arrives as an argument, and Appearance
                              is its only importer - see the design-language section
  Directories.qml            Singleton: XDG paths + shell-specific cache/state paths
  Icons.qml, Images.qml       Icon/image lookup helpers
  Persistent.qml              Helper for persisting fixed-schema values outside Config's JSON
  WallpaperTransitions.qml   Singleton: the wallpaper switch transitions the shell ships, one
                              entry per shader in modules/imi/background/shaders. The random
                              pool, the settings combo and the desktop menu all read this
                              rather than each keeping a copy - which is how the menu ended up
                              offering four of eight
                              (f5fba110c ("refactor(background): give the wallpaper transitions one catalogue"))
  plugins/                    Declarative + package-QML plugin renderer/validator/manager. It scans
                              bundled and user-installed manifests; PluginState.qml keeps dynamic
                              per-plugin, per-monitor layout in raw plugin-state.json.
                              bundled/ is where every desktop widget the shell ships lives -
                              there are no built-in desktop widgets (see docs/PLUGINS.md).
                              BarWidgets.qml is the bar's widget catalogue - the built-ins
                              plus every installed plugin's bar widget - promoted out of
                              BarConfig.qml so Settings > Bar and Edit Mode's bar stage read
                              one list. Layouts store ids and nameFor(id) is the only
                              resolution to a display name; the built-in names stay spelled
                              as Translation.tr("...") literals because the translation
                              extractor only sees that form and its clean pass strips what
                              it cannot see. test_bar_widgets_catalogue.py reddens on a
                              second copy growing back in BarConfig
                              71daefe9 ("feat(bar): promote the bar widget catalogue to a BarWidgets singleton")
  widgets/                   Shared UI components: StyledText, StyledComboBox, StyledSlider,
                              StyledToolTip(+Content), RippleButton, MaterialSymbol, ResourceCard,
                              PopupToolTip, StyledPopup, GroupedList, ConfigSwitch/ConfigSpinBox/
                              ConfigSelectionArray (settings-page form controls), DockIconMotion
                              (M3E feedback-motion wrapper for dock icons), SchemePaletteCircle
                              (a colour scheme drawn as its own palette), MarqueeText
                              (a label that scrolls only while it overflows),
                              CatalogueRow (one entry of a catalogue drawn: icon,
                              name, description, affordance - not interactive, so
                              the call site keeps the gesture), etc.
  functions/, models/, utils/, panels/   Supporting JS logic, list models, window-panel base classes

modules/imi/                 The "imi" (Immaterial Impulse) panel family - one directory per feature:
  bar/                        The top/bottom bar and everything docked in it (Resources, Media,
                              SysTray, Workspaces, clock, quick toggles, ...). BarPopupOverlay.qml
                              is the one static layer surface per screen that hosts every bar
                              popup's content on a single morphing card - it serves the vertical
                              bar too, which loads the same widget files
                              (d29cd6e45 ("feat(bar): add the static overlay surface the popup card will live on"))
  sidebarLeft/, sidebarRight/ Slide-out panels (AI chat, quick settings, notifications, volume mixer)
  onScreenDisplay/            Transient toast/OSD popups (volume, brightness, gamma, keyboard
                              layout, audio device switches) - see "OSD system" below
  screenCorners/              Decorative fake screen-rounding + corner hover/click zones that open
                              the sidebars
  background/                 Desktop background + the canvas the draggable desktop widgets sit on.
                              ClockDepthCutout.qml is the wallpaper's subject cut out by its mask -
                              the ONE place the mask's registration is computed, drawn by the depth
                              layer, by the picker that shows per-wallpaper state, and by the
                              desktop selector that authors it (see the clock-depth notes below).
                              The widgets themselves are all bundled plugins now (see
                              modules/common/plugins/bundled/); background/widgets/ holds only
                              AbstractBackgroundWidget.qml, which is the plugin host's base class.
  clockDepthSelect/           Picking that subject ON the desktop: a transparent, screen-sized
                              Overlay surface per output that draws the candidate cutout into the
                              box Background publishes, over the live widgets, and turns a click
                              into a MobileSAM prompt. It redraws neither the wallpaper nor the
                              widgets - both are already on screen, which is what makes the pixels
                              clicked the pixels the depth layer will mask
  editMode/                   Edit Mode's CHROME only - the toolbar above the shrunk desktop
                              and the tab bar below it, on one full-screen Overlay surface per
                              output (quickshell:editMode) whose mask is those two rects and
                              nothing else, so every other pixel falls through to the desktop
                              being edited. The desktop itself is not here: it stays on the
                              background surface, which is what the mode transforms.
                              EditModeInsets.qml is the one derivation of what the bar and
                              the dock occupy - both surfaces read it, and nothing else in
                              the mode may work out where either panel is
  overview/                   Workspace/window overview (like GNOME Activities)
  notificationPopup/          Desktop notification popups
  settings/                   The in-shell settings UI (pages/ = one file per settings category)
  dock/, lock/, mediaControls/, overlay/, polkit/, regionSelector/, screenTranslator/,
  sessionScreen/, onScreenKeyboard/, wallpaperSelector/, verticalBar/, desktopMenu/

services/                  Singletons wrapping external state/processes - one per concern:
  Audio.qml                  PipeWire default sink/source wrapper (Quickshell.Services.Pipewire).
                              Devices and volume only - it does not play sounds
  SoundTheme.qml             The shell's sound events, as an XDG sound-theme engine. Three pieces
                              on purpose: scripts/sounds/scan-sound-themes.py reports what is on
                              disk and decides nothing, services/sound_theme.js decides everything
                              and touches no disk (event name -> file, the Inherits= walk, the
                              subdirectory and extension rules, the .disabled marker), and this
                              singleton owns the process lifetimes. Playback is a spawned
                              `pw-play` - see "External binaries the shell drives"
  ResourceUsage.qml           Polls /proc/meminfo, /proc/stat, df, nvidia-smi on a timer
  HyprlandData.qml            Polls `hyprctl clients/monitors/layers/workspaces -j` on Hyprland IPC
                              events - the source of truth for "what does hyprctl currently see",
                              since Quickshell's own Hyprland IPC bindings don't expose everything
                              (e.g. per-monitor special-workspace state)
  HyprlandXkb.qml              Tracks active keyboard layout via Hyprland's `activelayout` IPC event
  HyprlandKeybinds.qml         Parses hyprland/keybinds.lua + custom/keybinds.lua (via
                              scripts/hyprland/get_keybinds.py) into the cheatsheet's tree, then
                              rewrites it through the keyboard-shortcuts editor's override map
  HyprlandKeybindOverrides.qml Owns the keyboard-shortcuts editor's sidecar
                              (~/.config/immaterial-impulse/keybind-overrides.json, raw FileView on
                              the PluginState pattern) and regenerates the Lua shim
                              hypr/hyprland/shellOverrides/keybinds.lua through
                              scripts/hyprland/keybind_overrides.py. Never edits user keybind
                              files; refuses to touch a hand-edited shim (content hash). See
                              docs/proposals/keyboard-shortcuts-editor.md
  PrismLauncher.qml            Prism Launcher modpacks for the launcher search, enumerated by
                              scripts/prism/list_instances.py. Feature-detected (native binary or
                              flatpak): without Prism the script never runs, `available` stays
                              false, and the '%' prefix plus its settings row disappear. Launches
                              by instance FOLDER name, which is not the display name
  AppUsage.qml                 Launch history for the launcher's frecency ranking, in
                              Directories.appUsagePath. The arithmetic is services/frecency.js
                              (five time-window buckets over a bounded per-app timestamp list);
                              this owns the file, the atomic write and the degradation. Keyed on
                              the DESKTOP-ENTRY id, which is not services/DockLaunchTracker.qml's
                              Wayland app_id - the two stores stay separate, and the dock's launch
                              buttons record here through the desktop entry they already hold
  Notifications.qml            org.freedesktop.Notifications server + notification history
  Notes.qml                    The note store: a JSON array in Directories.notesPath. Sole owner -
                              the bundled `notes` desktop plugin (one instance per monitor) and the
                              overlay notes editor both go through it rather than opening the file,
                              and it imports the legacy desktopnotes.txt array once
                              (Config.options.notes.importedLegacyStore) without ever writing to it
  Clight.qml                   Clight daemon wrapper (busctl --json=short; the shell has no D-Bus
                              binding). Feature-detected: a machine without the clight binary never
                              spawns a busctl. While the daemon is up, Brightness.qml routes every
                              backlight write through it (IncBl/DecBl) so the daemon's next
                              recalculation does not revert the change; night-light ownership stays
                              with Hyprsunset.qml. See docs/proposals/clight-integration.md
  PhoneConnect.qml             Paired-phone state from KDE Connect or Valent, driven over
                              `busctl --json=short` Process calls (the shell has no D-Bus
                              binding) - backend detection from the bus name list, one
                              normalized device/battery model for both daemons, ring/ping/
                              clipboard actions. KDE Connect's changes arrive as SIGNALS
                              (`busctl monitor`, see the streaming note below); Valent's
                              still arrive on the poll, which stays on for both as the
                              reconcile. Its parser logic is kept byte-for-byte in
                              sync with a logic-only test double
                              (tests/test_phone_connect_contract.py enforces it)
  SchemePreview.qml            Per-scheme swatches for the scheme pickers: one venv run of
                              scripts/colors/scheme_preview.py quantizes the wallpaper once and
                              builds every Material variant from it. Cached against the wallpaper
                              and the dark/light mode, so refresh() is free while those hold and
                              nothing recomputes while no picker is on screen
  ClockDepth.qml               What the subject-mask cache holds for the wallpaper on screen, for
                              the desktop clock's depth mode. Asks
                              scripts/background/subject_mask.py - the shell never computes a cache
                              key of its own - and queries nothing at all until either
                              background.clockDepth.enable, the picker, or the desktop selector is
                              open. `run` is reached ONLY from the wallpaper selector's picker and
                              `select` ONLY from the desktop selector; nothing reactive can start
                              segmentation. It also holds the prompted model's clicks for the
                              wallpaper on screen, restored from the cache once per wallpaper
                              rather than on every status, and `selectable` - whether the desktop
                              is currently showing the still image it is asking about, which is
                              the precondition both of those surfaces gate the gesture on
  MprisController.qml         The one answer to "which player is the media UI showing". It filters
                              the bus list (proxies always, duplicates by setting) through
                              MprisSelection.js - a .pragma library kept pure so the rules are
                              reachable from tests - resolves bar.media.preferredPlayer, and
                              publishes activePlayer / meaningfulPlayers / playerOptions. The bar,
                              the media popup, the right sidebar and the lock screen read those
                              rather than each resolving the setting again
                              (25329ade9 ("feat(mpris): resolve the preferred player once, against a stable bus id"))
  Brightness.qml, Battery.qml, Hyprsunset.qml, Network.qml, BluetoothStatus.qml, TrayService.qml,
  Weather.qml, Docker.qml, ... (one per integration)

panelFamilies/              PanelLoader.qml (thin LazyLoader) + ImmaterialImpulseFamily.qml (the
                            actual list of panels for the "imi" family)

scripts/                   Standalone helper scripts (Python/bash) invoked via Process/Quickshell.execDetached
  background/subject_mask.py  Segments a wallpaper's subject through ONNX Runtime and owns the mask
                              cache in ${Directories.cache}/clock-depth. Two kinds of model: the
                              salient detectors (isnet-anime, isnet-general-use) answer the PICTURE
                              and are asked with `run` (~1.3-4.5s, ~1GB RSS); mobile-sam answers a
                              POINT and is asked with `select --point x,y[,label]` (~1.6s for the
                              first click, ~0.3s for every one after, because the image embedding
                              is cached at the key). It owns the CACHE KEY too - path/mtime/size -
                              and the shell never computes one, so an in-place wallpaper edit
                              invalidates its mask, its opt-out, its candidates and its embedding
                              together. It also reports the model list, so the picker holds no copy
                              of it. `status` and `sweep` are stdlib-only and load no model - a
                              prompted mask's clicks live in a PNG text chunk it parses by hand for
                              exactly that reason; `run` and `select` need the uv venv
                              (subject-mask-venv.sh)
translations/              i18n string tables (Translation.tr(...) singleton)
assets/                    Static images/fonts bundled with the shell
```

## The Config system (settings page ↔ persisted JSON)

`Config.qml` defines the **entire** settings schema as nested `JsonObject` properties (e.g.
`Config.options.bar.resources.alwaysShowCpu`). This is not just an in-memory tree — Quickshell's
`JsonAdapter`/`JsonObject` machinery automatically:

1. Loads `~/.config/immaterial-impulse/config.json` into `Config.options` on startup.
2. Persists any property write back to that file (debounced by `Config.readWriteDelay`, 50ms).

Consequences for making changes:

- Adding a new setting = add a `property <type> name: <default>` inside the right nested
  `JsonObject` in `Config.qml`. No migration code needed; missing keys just fall back to the QML
  default until the user's `config.json` gets the key written the first time it changes.
- The settings UI (`modules/imi/settings/pages/*.qml`) is hand-written QML, not generated from the
  schema — every setting needs a corresponding `ConfigSwitch`/`ConfigSpinBox`/`ConfigSelectionArray`/
  etc. row added manually in the relevant page, bound with `checked: Config.options.x.y` /
  `onToggleRequested: Config.options.x.y = !Config.options.x.y` — see the next two points for why
  the write-back is not hung on the control's own `changed` signal.
- **A control writes back by changing the config, never by assigning to its own bound property.**
  Assigning to a property that carries a binding *destroys the binding*, and in this codebase that
  is how a settings toggle silently detaches from the config it is showing. `ConfigSwitch` answered
  its own click with `onClicked: checked = !checked` while all 159 call sites bound
  `checked: Config.options.x.y`. From the first click onward the switch showed local state: nothing
  external could move it again — not a preset, not a hand-edited `config.json`, not a migration —
  while the page's own `onCheckedChanged` kept writing through, so the *setting* changed and the
  *switch* lied about it, and the next click on a switch that looked on wrote `!off` = on.
  Restarting rebuilt the component and with it the binding, which is exactly why it read as a
  refresh bug rather than a broken control
  ([#158](https://github.com/XephyLon/immaterial-impulse/issues/158)). The click is now an intent —
  `toggleRequested()` — and the call site flips the value at its source. A rewritten call site must
  not read the widget's own state: reading `checked` to decide what to write puts the coupling
  straight back. Three things fell out of it, all of them evidence of the same bug being routed
  around locally: the `if (checked === Config.options.x.y) return` echo guards a dozen handlers
  carried existed only because the write came back through the binding and re-fired the handler, and
  an intent fires once per click, so they are gone; the four
  `Binding { property: "checked"; restoreMode: RestoreBinding }` blocks were four call sites
  restoring the binding the click had destroyed, so they are gone too; and the inner `StyledSwitch`
  is now `checkable: false`, because a QQC2 `Switch` moves its own `checked` on a click or a thumb
  drag and would show a flip the call site declined. `tests/lint_config_switch_intent.py` fails the
  suite on an assignment to `checked` in the widget or at any call site (and on an
  `onCheckedChanged` write-back, which is now a dead switch), and
  `tests/tst_config_switch_binding.qml` delivers a real click to a model of the shape and writes the
  source externally afterwards. 69c15279a ("fix(widgets): make a ConfigSwitch click an intent, not a
  write to `checked`").
- **A ranged control writes back from `onValueModified`, never `onValueChanged`.** `ConfigSpinBox`
  and `ConfigSlider` are the two controls with a `from`/`to`, and their `value` changes for reasons
  that are not edits: QQC2 bounds `SpinBox.value` to `[from, to]` when the component completes,
  `Slider` does the same, and `StyledSlider`'s `Behavior on value` animates through intermediate
  values. `Config.qml` declares no ranges at all, so a control's range is always narrower than what
  the schema accepts — and a write-back on `onValueChanged` meant *instantiating a settings page*
  clamped whatever the config held to the control's range and wrote it out, destroying hand-edited,
  restored and preset-supplied values with no user action. Both controls now expose
  `signal valueModified(newValue)`, raised only for a real interaction, and the write-back handler
  reads the signal's `newValue`. The same reasoning applies to any lossy display expression
  (`value: Config.options.x / 60000`): a write-back that fires on load round-trips the value through
  an `int` and loses it. `tests/test_config_control_write_back.py` guards both halves — a source
  contract over every call site, plus a real settings page opened against a real out-of-range config.
- The inner control's own range widens to admit an out-of-range stored value
  (`from: Math.min(root.from, root.value)`), so a spin box shows the number the config really holds
  rather than a plausible-looking lie, and the user can only move it back toward the sanctioned
  range. Don't "fix" that back to a plain `root.from`/`root.to`.
- Consumers read `Config.options.x.y` directly and reactively - no separate "load config" step.
- **The config `FileView` does not start until `Directories.configDirReady` is true**, which happens
  when `scripts/migrate-config-dir.sh` exits. `~/.config/illogical-impulse` -> `immaterial-impulse`
  is a runtime migration that refuses to migrate into a directory that already holds a `config.json`,
  so a Config load reaching the directory first wrote its defaults in and permanently disabled the
  move - the user silently kept none of their settings. The script used to be fired with
  `execDetached` (returns immediately), so the ordering was a timing accident. Anything else that
  writes into `Directories.shellConfig` on startup should think about the same gate; the three
  `mkdir`s in `Directories.qml` that live inside it are behind it, and the script defends itself with
  `mv -T` for the rest. If the migration hangs, `Config` gives up after 10s and comes up **read-only**
  (`configDirTimedOut`) rather than writing into a half-migrated directory. See
  `docs/UPSTREAM_MIGRATION.md` and `tests/test_config_dir_migration_runtime.py`, which forces the
  losing interleaving with `IMI_MIGRATE_DELAY` instead of hoping to observe it.
- **A key with no declared property is destroyed by the first write, not just hidden.** The
  `JsonAdapter` serializes exactly its declared properties, and `writeAdapter()` runs on essentially
  every launch, so an undeclared key present in `config.json` survives only until then - verified
  end to end against an isolated `XDG_CONFIG_HOME`, including on a launch that changed nothing.
  This is what makes a key rename lossy, and it is why `Config.qml`'s upstream migration reads
  `configFileView.text()` (the raw file) inside `onLoaded` rather than `Config.options`: by the time
  anything else could look, the old key is already gone. Any future migration that needs to read a
  removed key must run in that same `onLoaded`, before `ready`, on the raw text - and it gets exactly
  one launch to do it. See `docs/UPSTREAM_MIGRATION.md`.
  (The desktop-widget migration's "old keys are deliberately left on disk" note is not a
  counterexample: `background.widgets.*` are still *declared* in `Config.qml`, which is precisely why
  they persist.)
- **Presets are the exception to the rule above, and that makes re-declaring a removed key
  dangerous.** `writeAdapter()` strips undeclared keys from `config.json`, but preset files under
  `~/.config/immaterial-impulse/presets/` are separate JSON the adapter never rewrites — whatever was
  in a preset when it was saved is still in it. So a key removed from the schema is gone from the live
  config but **preserved in every preset**, lying dormant. Re-declaring that key re-arms all of them on
  the next preset apply. This is exactly how `activeStill` came back — re-armed by 5d4bfa773
  ("feat(wallpaperEngine): reinstate activeStill, this time with a writer"), disarmed by 03b8b0298
  ("fix(wallpaperEngine): derive the greeter's still path, do not store it"); see
  [Before you restore something that was removed](#before-you-restore-something-that-was-removed).
  Three of the six presets on the author's machine still name the wrong project. Removing a key is
  therefore not reversible by simply putting it back — either migrate the presets or, better, do not
  store derivable state in the first place.
- **Do not store a path that can be derived from state the config already holds.** Two fields that
  must agree will eventually disagree, and nothing reports it. The greeter's full-resolution Wallpaper
  Engine still is the canonical case (aa0772773 ("feat(background): grab the greeter's still off the
  live surface")): the background grabs it off the live surface into
  `~/.cache/quickshell/wallpaperengine-stills/<activeProject>.png` (`Background.captureGreeterStill`),
  and every consumer — including `imi-sddm-theme`, a separate process that cannot ask the shell
  anything — rebuilds that path from `activeProject`. A derived path cannot name a different project
  than `activeProject` does, needs no clearing in `WallpaperEngine.stop()`, and cannot be carried
  stale inside a preset.
- **`Config.readWriteDelay`'s 50ms debounce only covers the disk write - it does nothing to stop
  every keystroke from firing whatever else reactively reads that option.** A `ConfigTextArea`
  bound as `onValueChanged: Config.options.x.y = value` re-triggers every consumer of
  `Config.options.x.y` (e.g. the media widget's player-matching, or a quote re-render) once per
  keystroke, not once per edit. Where the option feeds something more than a simple display value,
  add a local `Timer` (600ms is the convention already used, see `BarConfig.qml`'s
  `mediaDebounceTimer` and `BackgroundConfig.qml`'s `quoteDebounceTimer`) that assigns to
  `Config.options.x.y` only after typing pauses, instead of assigning directly in `onValueChanged`.

`GlobalStates.qml` is the sibling singleton for state that should **not** persist (is this sidebar
currently open, is the bar in autoHide-triggered-show state, etc.) - don't add ephemeral UI state to
`Config`, and don't add persisted settings to `GlobalStates`.

**Nothing addresses a settings page by its name, because every name in the catalogue is a
`Translation.tr(...)` call.** `SettingsContent.qml`'s `pages` list gives each page a `name` (what the
sidebar draws) *and* a stable untranslated `id` (what a link carries).
`GlobalStates.settingsPage` — written by the desktop menu's two rows and by every settings hit in the
launcher, in the form `"<id>"` or `"<id>:<search term>"` — is resolved against `id` alone. Resolving
it against the display name, which is how it shipped, meant every deep link in the shell stopped
working the moment the user changed language, and stopped **silently**: `findIndex` returns -1, the
handler clears the request regardless, and the window opens on whichever page was last shown. The
same trap is why an *index* is not the alternative — a hardcoded one went stale the day a page was
inserted. Search is pinned the other way on purpose: `pageMatches()`, `navigateFirstMatch()` and the
launcher's own filter all compare the query against the translated `name`, because that is the text
the user is reading when they type it. `tests/test_settings_page_ids.py` fails the suite on a page
declared without an id, on an id that goes through `Translation.tr`, on either half of the resolver
reading `name`, and on any `GlobalStates.settingsPage` write in the tree whose value is not a
declared id — the realistic regression is a fifteenth page or a third deep link copied from whatever
sits beside it, not someone rewriting the resolver.
1c674c8f5 ("fix(settings): address a settings deep link by page id, not by its label").

## Hyprland integration

**Hyprland only.** `README.md`'s "Compositor support" section is policy, not aspiration: there are no
plans to support Niri or any other compositor, upstream's compositor-abstraction layer is kept *only*
as a thin Hyprland facade so merges stay tractable, and compositor-specific code for anything else is
**removed when it lands**. `services/HyprlandBackend.qml` is what "thin facade" means. The Niri
counterparts that arrived with the `78c58b84` merge - `NiriBackend`, `NiriXkb`, `NiriConfig`,
`NiriBackdrop`, `CompositorGlobalShortcut` - were all removed on landing, as the policy requires.

Do not read a leftover `niri` string as evidence that support exists, is wanted, or needs cleaning
up. Everything that still matches is Hyprland code *imitating* Niri: the `overview.style = "niri"`
look (`modules/imi/overview/NiriOverview.qml`, which imports `Quickshell.Hyprland` and reads
`HyprlandData`), the `"niri"` animation preset in `scripts/hyprland/hyprconfigurator.py` built from
`hl.curve`/`hl.animation`, their `"Niri Like"` labels, and a generic `pkill sway || pkill niri`
logout fallback. None of it is compositor support.

Two separate mechanisms are in play, for different reasons:

1. **Quickshell's native `Quickshell.Hyprland` IPC bindings** (`Hyprland`, `HyprlandMonitor`,
   `HyprlandWorkspace`, `HyprlandToplevel`, `Hyprland.workspaces`, `Hyprland.monitorFor(screen)`,
   `Connections { target: Hyprland; function onRawEvent(event) {...} }`) - reactive, bindable,
   preferred when the data you need is exposed through it.
2. **`services/HyprlandData.qml`**, which shells out to `hyprctl clients/monitors/layers/workspaces
   -j` on a `Process` every time a (non-excluded) Hyprland IPC event fires. This exists because some
   state genuinely isn't exposed via (1) - e.g. whether a monitor's special workspace is currently
   *shown* (`monitor.specialWorkspace.name`), which only `hyprctl monitors -j` surfaces. Expect
   ~0.5-1s latency on this path (event → spawn `hyprctl` → parse JSON → property update) since it's
   process-based, not a live subscription.

**This user's Hyprland config uses a Lua-based config layer** (`hl.bind(...)`, `hl.dsp....(...)` in
`~/.config/hypr/hyprland/*.lua`). This changes how `hyprctl dispatch` needs to be invoked manually
(e.g. from a terminal while debugging) - plain vanilla syntax like
`hyprctl dispatch togglespecialworkspace special` fails with a Lua parse error on this system.
The working form mirrors the Lua binding calls directly, e.g.:
```bash
hyprctl dispatch 'hl.dsp.workspace.toggle_special("special")'
```
This is purely a manual-testing/CLI concern - IPC events, layer-shell behavior, and everything the
QML code touches are unaffected by this; only raw `hyprctl dispatch <dispatcher> <args>` calls typed
by a human/agent need the Lua-call form on this particular machine.

**`hyprctl` picks its target instance from `HYPRLAND_INSTANCE_SIGNATURE` and from nothing else — so
a `hyprctl` inside a nested-compositor harness talks to the *user's* session.** `WAYLAND_DISPLAY` is
irrelevant to it: measured, `WAYLAND_DISPLAY=wayland-99 hyprctl monitors` answers correctly for the
real output, a bogus signature fails with `Couldn't connect to
/run/user/1000/hypr/<sig>/.socket.sock`, and an unset one refuses outright with
`HYPRLAND_INSTANCE_SIGNATURE not set!`. The signature is exported into every process in the session,
and redirecting `XDG_*` or `WAYLAND_DISPLAY` does not shadow it.
`tests/run_notification_blur_probe.sh` is the case that matters: it starts a nested Hyprland,
exports four `XDG_*` vars and the new `WAYLAND_DISPLAY`, then ends with a bare
`hyprctl dispatch exit` — which is aimed at the outer session. Nothing under `tests/` sets
`HYPRLAND_INSTANCE_SIGNATURE` today. Anything driving a nested compositor must export the nested
signature (or pass `hyprctl -i <sig>`) before its first `hyprctl`, and preferably give the nested
instance its own `XDG_RUNTIME_DIR` as `tests/run_weather_probe.sh` already does for weston. This is
the same family as the `pgrep -f` trap above — a process-targeting command that silently resolves to
the caller's own session. See
`docs/superpowers/specs/2026-08-14-integration-testing-design.md` §2.1.
23b1e581f ("docs(specs): what an integration layer adds over the harnesses we have").

**Rules registered at runtime through `hyprctl eval` do not survive, so don't build on them.**
`hyprctl reload` resets the Lua state - every global and every rule registered from it is gone.
The shell reapplies the Hyprland theme during its own startup, which reloads, so anything a QML
`Component.onCompleted` registers via `execDetached(["hyprctl", "eval", ...])` is destroyed seconds
after it is created. This fails silently and in a way that is easy to misread: registering the rule
by hand from a terminal to "verify" it works leaves a rule that *does* persist until the next
reload, so the feature looks correct while the shell's own registration has never once been live.
Verify by clearing the global, restarting the shell, and re-reading it - not by running the chunk
yourself.

`Settings.qml` used to float/size/center its window this way. It doesn't need to: a `FloatingWindow`
whose `minimumSize` equals its `maximumSize` is floated, sized and centred by Hyprland on its own,
purely from the fixed size hints. Prefer that over a runtime rule. It also keeps the window title
free to stay translated, since nothing is matching on it.

**A Hyprland option the shell sets is reported back as set whether or not it did anything, and the
complaint is on the screen rather than in the log.** `decoration:screen_shader` is the measured
case, against 0.56.2 in a nested instance. `CHyprOpenGLImpl::applyScreenShader` calls
`m_finalScreenShader->destroy()` **before** it checks the path, so a path naming nothing turns the
previous shader off; it then queues `Screen shader parser: Failed to check screen shader path: No
such file or directory` into `errorOverlay/Overlay.cpp`, which paints a red-bordered banner across
the focused monitor with no timeout, clearing only when a later reload supplies a shader that
loads. Nothing reaches Hyprland's log, so the `tail | grep -iE 'error|WARN scene'` loop in
CONTRIBUTING.md sees a clean run. The compositor does not crash.

Two consequences generalise past shaders. **`hyprctl getoption` answers with the value Hyprland was
handed, not with the value that took effect** - the bogus path came back with `set: true` - so a
service deriving its own state from `getoption` (`HyprlandConfigOption`, and every quick toggle
built on it) will report a feature as on while it is doing nothing. And **an option written into
`shellOverrides/main.lua` is applied on Hyprland's own reload**, i.e. after the shell has stopped
watching, so there is no return path for a failure even in principle. Where a value the shell writes
names a file, the file's existence is checkable statically and should be checked there:
`tests/lint_shader_paths.py` resolves every static shader path declared in QML against disk, which
is what would have caught the anti-flashbang weak shader that was named for the whole life of its
service and never existed. dea752d04 ("fix(antiFlashbang): give the weak rung the shader it has
always named"), b50018e4a ("test(lint): fail on a QML file naming a shader that is not on disk").

**hyprsunset has no state query at all, so the shell owns night light's on/off state.** Checked
against 0.4.0, not assumed: `hyprctl hyprsunset --help` lists exactly three requests -
`temperature <temp>`, `identity`, `gamma <gamma>` - bare `hyprctl hyprsunset` answers
`invalid command`, and the daemon's own socket
(`$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.hyprsunset.sock`) answers `invalid command`
to `state`, `status`, `info`, `enabled`, `active` and `matrix` too. Nothing reports the applied
matrix.

The bare `temperature` request looks like a getter and is not one: it echoes back the last
temperature the daemon was *told*, which `identity` (the "off" dispatch) never resets. Measured on
this machine - a daemon running as `hyprsunset --identity`, screen perfectly neutral, reports
`6000`; a daemon put into identity after `temperature 5000` still reports `5000`. "Off" and "on"
are indistinguishable through it.

`services/Hyprsunset.qml` used to infer active state by comparing that query against a hardcoded
`"6500"`. That number is not hyprsunset's - it is the `from:` end of the Intensity slider in
`modules/imi/sidebarRight/nightLight/NightLightDialog.qml` (6500K, the UI's idea of "neutral
daylight"), reused as if it were a daemon sentinel. The daemon's actual default is 6000 and its
actual neutral is `--identity`, not a temperature at all, so the check read "on" whenever the last
set temperature was not literally 6500 - including with the identity matrix applied and the screen
neutral. Don't query `hyprsunset` for state; track on/off intent yourself. `Hyprsunset.qml`
persists it in `Persistent.qml` (`night.temperatureActive`, alongside `idle.inhibit` and
`record.enable`) and **re-applies** it on startup - applied, not merely displayed, because after a
reboot the daemon is gone and within a session it may have been left in any state. The restore is
gated on `Persistent.ready && Config.ready` together: `Persistent` holds the state, `Config` holds
the temperature to restore it *at*, and restoring without the latter launches the daemon at the
fallback temperature. `tests/test_nightlight_state_runtime.py` pins all of this against a real
shell and fake `hyprsunset`/`hyprctl`/`pidof` binaries.

This exact fix was made once before and lost: it landed in `0168b1d1`, and the upstream Niri merge
`78c58b84` silently restored the query, the `6500` sentinel and the "sync with whatever is running"
doc comment on top of it. Anything reintroducing `fetchState()` is a regression, not a refinement.

**That same bare `--temperature 6000` default also bit the daemon's cold start, not just state
queries.** `Hyprsunset.qml` used to spawn `hyprsunset` with no flags (`pidof hyprsunset ||
hyprsunset`) and immediately fire a separate, fire-and-forget `hyprctl hyprsunset identity`/
`temperature` correction right after via `execDetached`. On a warm system that correction reaches
the already-running daemon fine, but on a cold start (nothing running yet) it races the daemon's
IPC socket coming up and can silently fail, leaving `hyprsunset` stuck at its own 6000K default
indefinitely - toggling night light off after a restart looked like it did nothing, and toggling it
on read as the tint "intensifying" (6000K → the configured, warmer temperature) rather than turning
on from neutral. Fixed by launching `hyprsunset` with the target state already as CLI flags
(`--temperature N` / `--identity`) instead of spawning bare and correcting after the fact - a
freshly-spawned daemon now starts in the right state with no window where it's wrong.

**A Hyprland setting migrated in `config.json` is not migrated.** `Config.options.hyprland.*` is a
*record* of what the settings page last chose; the compositor never reads it. The value reaches
Hyprland through `~/.config/hypr/hyprland/shellOverrides/main.lua`, generated by
`scripts/hyprland/hyprconfigurator.py` (via `services/HyprlandConfig.qml`), and the only thing that
regenerates that file is the Hyprland settings page's `Component.onCompleted` - an on-demand
`Loader` (`SettingsContent.qml`, `active: Config.ready && (currentPage === index || item !== null)`).
A user who never opens that page keeps the old value indefinitely, so the two files drift apart, and
the lua one is the one that matters.

Issue #69 is the worked example, and it shipped broken twice for this reason: a migration cleared a
stale `input.kbOptions = grp:win_space_toggle` from `config.json` and the compositor went on
toggling layouts regardless. When migrating a `hyprland.*` key, migrate `main.lua` too - and do not
gate the lua half on the config value, because once a config-only fix has shipped, the population
still broken is exactly the one whose config is already clean. `--reset-if KEY VALUE` exists for
this: it drops the managed line only while it still holds the stale value, so it is safe to run on
every load and cannot clobber a value the user has since chosen. Hyprland watches these files and
reloads on change, so no explicit `hyprctl reload` is needed - which is also why the writer must not
rewrite a file whose content did not change.

**Keybind overrides are another generated shellOverrides file, with one extra rule: a chord-level
unbind exists but a bind-level one does not.** The keyboard-shortcuts editor renders its JSON sidecar
into `~/.config/hypr/hyprland/shellOverrides/keybinds.lua` (sourced last by `hyprland.lua`, guarded
by `is_file_exists`), following the same discipline as `main.lua` — atomic writes, no rewrite when
content is unchanged — plus a content hash in the header: a shim that does not hash-match was
hand-edited and the generator refuses to write *or delete* it, surfacing `shimStatus: "foreign"`
instead of clobbering. Overriding a default works because `hl.bind()` returns a keybind object whose
`:unbind()` removes **every** bind matching that chord's modmask+key (`CKeybindManager::
removeKeybind`), so binding a throwaway function and unbinding it clears a chord *including its
hidden sibling binds* — there is no way to remove just one of several binds on a chord from the shim,
which is why a rebind re-emits the parsed primary action and the `qsIsAlive`-style fallbacks on that
chord are gone with it. Re-emission is gated by a literal-only params grammar; `function` binds and
params referencing `keybinds.lua` locals are remove-only. An updated shim is picked up by Hyprland's
own config watch, but a *created* one was not sourced at the last load (nothing watches it), so the
service issues `hyprctl reload` only for created/deleted results.
(cd6296659 ("feat(hypr): source the shell's keybind override shim last"), 08d11dd83
("feat(keybinds): sidecar-to-Lua override generator with hand-edit protection").)

**Markers on such migrations are a trap of their own.** A persisted "already migrated" flag records
that the check *ran*, not that the value was ever *seen*, and the two come apart whenever the config
it ran against was not the user's - most reliably when the config-directory migration declines and
`Config` loads the installer's default first. Prefer an unconditional, idempotent clear whenever the
stale value is one the shell cannot legitimately hold, and reserve markers for migrations that would
otherwise undo a choice the user has since made. `tests/test_kboptions_migration_runtime.py` pins
both halves against real files; neither failure mode is reachable from a unit test, which is why the
original fix passed review with no test at all.

## Layer-shell (wlr-layer-shell) gotchas

Widgets that are `PanelWindow`s pick a `WlrLayershell.layer` (`Background < Bottom < Top < Overlay`).
Two non-obvious behaviors have bitten this codebase before and are worth knowing:

- Hyprland renders **fullscreen windows above the `Top` layer** (this is why a bar on `Top` disappears
  under a fullscreen app by default), but **below `Overlay`**. A special workspace opened on top of a
  fullscreen window compounds this. Fixing "X becomes unclickable/invisible under fullscreen +
  special workspace" generally means conditionally promoting that surface to `Overlay` only in that
  specific combination (see `modules/imi/bar/Bar.qml`'s `WlrLayershell.layer` binding and
  `modules/imi/screenCorners/ScreenCorners.qml`'s `fullscreen` property for the reference
  implementation).
- **`visible: false` on a layer-shell `PanelWindow` does not hide it, it destroys it.** Window reuse
  is forbidden under `WlrLayershell`, so the surface is torn down and a new one (with a new
  scene-graph GL context) is built on the way back. `hideWhenFullscreen` was implemented this way
  once and every fullscreen transition rebuilt the embedded Wallpaper Engine renderer against a
  fresh context, leaving the desktop strobing at 30Hz - a photosensitive-seizure hazard, not a
  cosmetic bug. Keep the window mapped and switch off an `Item` inside it instead
  (`Background.qml`'s `suppressContents`). This applies to any route to that property, not just a
  declarative binding: `bgRoot.visible = false` from a handler, or a `Binding` object aimed at it,
  destroys exactly the same surface. `tests/test_background_fullscreen_suppression.py` fails on all
  three.
- **Same-layer surfaces resolve overlap by stacking order, not layer priority.** If two `PanelWindow`s
  end up on the same layer and physically overlap, whichever the compositor considers "on top" wins
  *all* input in the overlapping region - the other surface's mask in that area is simply unreachable.
  When this happens, don't fight the ambiguous stacking order; instead carve the contested rectangle
  out of the losing surface's own `mask` using a `Region { intersection: Intersection.Subtract; ... }`
  child region, sized/positioned to exactly exclude the other surface's hit-zone. See `Bar.qml`'s
  `mask:` property for the pattern (it excludes `ScreenCorners.qml`'s corner-open hit rects when both
  are forced to `Overlay`).
- **Compositor blur behind a surface depends on that surface's actual alpha clearing a per-namespace
  threshold**, not just on "blur" being enabled somewhere. The companion Hyprland config
  (`~/.config/hypr/hyprland/rules.lua`) sets `hl.layer_rule({ match = { namespace = "quickshell:.*" },
  ignore_alpha = 0.79 })` (plus a `blur = true` rule) - pixels with alpha below that threshold are
  *not* blurred, they just show plain unblurred transparency. This is why picking the right
  `Appearance.colors.colLayer*` token matters for a floating popup, not just picking "a" transparent
  one - see the Design language section below.
- **Blur is scoped per-panel now, and scoping it takes an edit in two different files.** The panels
  ported so far - bar, vertical bar, dock, both sidebars, the OSDs and the overview - each turn the
  catch-all whole-surface `blur` *off* for their namespace in
  `~/.config/hypr/hyprland/rules.lua` and publish a `WindowBlurRegion`
  (`modules/common/widgets/WindowBlurRegion.qml`) over just its painted body instead, so the
  compositor never blurs the shadow (#82, #89). A blur region is a plain rounded rect and knows
  nothing about `visible`, `opacity`, or a parent's `clip`, so each sub-region has to be gated on
  exactly the condition that *paints* its shape - covering an unpainted one frosts bare wallpaper -
  and `Appearance.rounding.full` (9999) is a "round me completely" sentinel that must be resolved to
  `Math.round(item.height / 2)` before it goes into a region. A body reached through a `Loader` is
  exposed to the window as a `backgroundItem`/`backgroundPainted` pair on the content component
  rather than reached into. Both halves are silent when only one lands: a region without the layer
  rule changes nothing at all, and the layer rule without a region leaves that panel with no blur
  whatsoever. `tests/lint_blur_region_pairing.py` pins the two together.
- **That whole mechanism applies to layer surfaces only, and a `PopupWindow` is not one.** An
  `ext-background-effect` region is attached to a layer surface; the tray menu, the dock context
  menu, the drag-apps popup and the tooltips are xdg-popups, so a `WindowBlurRegion` published from
  one is accepted and silently does nothing. Popups also carry no namespace of their own - they
  inherit the rules of the surface they belong to, so the only knob addressed at them is
  `blur_popups` on the parent's namespace, and turning that off costs the body its blur along with
  the shadow. Threshold by `ignore_alpha` instead: `colShadow` tops out at 0.3 and fades outward
  while a panel body sits at `1 - appearance.transparency.backgroundTransparency`, so a value
  between them blurs one and not the other. Note the failure direction - too high a threshold
  unblurs the *body*, which looks flat but harmless; too low re-frosts the shadow. Motivated by
  4a1b4f850 ("fix(blur): stop the compositor frosting drop shadows"), where a region
  was written, deployed and only shown to be inert by looking at it on screen; a region on a
  `PopupWindow` now fails `tests/lint_blur_region_pairing.py`. The threshold itself is *generated*,
  because where it falls moves with the user's transparency setting and a layerrule cannot read
  one: `services/PopupBlurThreshold.qml` writes
  `hypr/hyprland/shellOverrides/popupBlur.lua` and `rules.lua` `dofile`s it behind a `pcall` with a
  fallback for the first run. That rule is applied only to namespaces whose own `blur` is already
  off, so it reaches their popups and nothing else. Watch which way it fails: too high a threshold
  unblurs the *body*, which is flat but harmless; too low re-frosts the shadow.
- **`ignore_alpha` is one value per namespace, shared between a panel and its popups.** It is
  tempting to raise it on a namespace whose own `blur` is off, on the reasoning that only its popups
  can be affected. That is wrong: the panel's body is blurred *through the region*, and the region
  is subject to `ignore_alpha` too, so raising it above the body's alpha unblurs the panel itself.
  Doing exactly that took the blur off the bar, the dock and both sidebars at once. The threshold
  has to clear the faintest *panel* body as well as sit above the shadow, and the bar is usually the
  faintest because it thins `colLayer0` again by `bar.backgroundOpacity`. Motivated by 4a1b4f850
  ("fix(blur): stop the compositor frosting drop shadows").
- **`quickshell:popup` is already handled, and adding `blur = false` to it breaks it.** Its two
  surfaces (`StyledPopupMenu`, and `BarPopupOverlay`'s card since b22a923a5 ("refactor(bar): delete
  the per-popup layer surface") retired `StyledPopup`'s own window) paint opaque bodies,
  and the namespace carries `ignore_alpha = 1` from an older tooltip fix. That blurs the opaque body
  and skips the translucent shadow, which is the whole split the region mechanism exists to produce.
  Set `blur = false` there and the region becomes the only source of blur, which nothing reaches at
  alpha 1, so those surfaces go flat.
- **A blur region is published on the *timer* for panels built by a `LazyLoader`.**
  `Component.onCompleted` publishes, but there is no layer surface yet at that moment, so the first
  publish that takes effect is the settle timer's - which is a guaranteed ~96ms of surface-up-and-
  unblurred on every open. Publish immediately *and* keep the timer. Motivated by 4a1b4f850
  ("fix(blur): stop the compositor frosting drop shadows").
- **A blur region built from a *list* of items must observe those items, and a model count is not
  observing them.** `WindowBlurRegion.regionItems` takes the rects a panel paints when the set is
  not known in advance, and the notification stack is its only caller. A `Region` whose item has
  been destroyed reports itself `empty()`, so a stale list is not a slightly-wrong blur - it is *no*
  blur, with the region still published, nothing in any log, and QML that reads correctly.
  `NotificationListView` refreshed its card set from `onCountChanged`, and the popup's ordinary life
  defeats that twice over: a notification times out, the window hides, another arrives from the same
  app, and the app-name list ends the cycle exactly where it started - so `count` reads 1 throughout
  while the delegate is torn down and rebuilt. `count`'s signal is raised from the view's layout
  pass as well, which does not run while the surface is down (`visible: false` destroys a layer
  surface), so even the 1 -> 0 -> 1 in between is never announced. Measured against a real popup:
  `countChanged` fired exactly *once* per shell session, so every notification after the first had
  been unblurred for the whole life of the feature. Observe `contentItem`'s children, which is the
  thing that actually changes; see
  [State propagation is reactive](#state-propagation-is-reactive-or-it-is-a-bug-waiting) for the
  general rule. Both halves of seeing it are worth reusing: `tests/run_notification_blur_probe.sh`
  photographs the frost under a *nested Hyprland on its own bus* - `qmltestrunner` cannot construct
  a `Region` and weston implements no ext-background-effect, so nothing else can - and it shoots
  three popups because the first one is the one that works.
  `tests/test_notification_cards_runtime.py` pins the card set itself, which headless weston can
  reach.
  bd69d191f ("fix(notifications): publish the cards that are on screen, not the first popup's").
- **A window's `color` is not just a colour: an alpha of 255 permanently costs that surface its
  blur.** `QQuickWindow::setColor()` rewrites the window's *requested surface format* whenever the
  new colour's alpha crosses the 255 boundary - `fmt.setAlphaBufferSize(alpha < 255 ? 8 : -1)` then
  `QWindow::setFormat(fmt)`, which still mutates `requestedFormat()` long after `create()`.
  `QWaylandWindow::isOpaque()` is literally `window()->requestedFormat().alphaBufferSize() <= 0`,
  and the next `setGeometry()`/`setMask()` on an opaque window publishes
  `wl_surface.set_opaque_region` over the whole surface. **Nothing retracts it** - `setOpaqueArea()`
  has no caller outside those two `isOpaque()` branches - and Hyprland skips blur behind a
  client-declared opaque region. So a window colour bound to a transparency-derived token
  (`colLayer0`) goes opaque once when `appearance.transparency.enable` is switched off and is still
  declared opaque after it is switched back on: translucent, unblurred, until the shell is reloaded
  and the window is rebuilt on a fresh surface. That is
  [#143](https://github.com/XephyLon/immaterial-impulse/issues/143), and note where the fault is not
  - the QML is fully reactive, the colour really does come back, and no log line mentions any of it.
  Keep a window's clear colour a **literal** and paint the backdrop with a child `Rectangle`, which
  is what every other window here already did; `tests/lint_window_clear_color.py` fails the suite on
  a bound one. The trigger for the latching configure is easy to under-estimate: the transparency
  toggle makes `PopupBlurThreshold` rewrite `popupBlur.lua` and `hyprctl reload` 400ms later, which
  reconfigures every window. deba3e3f6 ("fix(settings): keep the window's clear colour constant so
  the frost survives"), 4a99f2a8b ("test(lint): pin every window's clear colour to a literal").
- **One static surface can host many widgets' content, and that is now a pattern here — but only
  four properties make it safe.** `modules/imi/bar/BarPopupOverlay.qml` is one always-mapped
  full-screen `Overlay` surface per screen carrying a single `Rectangle` that every bar popup
  morphs; `modules/common/widgets/StyledPopup.qml` no longer owns a window at all and is a
  declaration plus a hover state machine that claims `GlobalStates.activeBarPopup`. Ten surfaces,
  ten shadows and ten compositor map animations became one of each. What holds it up:
  1. **The surface's geometry is a constant of the screen.** All four edges anchored, no `margins`,
     no `implicitWidth`/`implicitHeight`. On a layer surface position *is* `margins`, so a card
     animating along the bar would reconfigure the surface every frame — the create-map-destroy
     loop `StyledPopup`'s imperative positioning already existed to avoid, reached from the other
     side. `tests/lint_bar_popup_overlay_static.py` fails on any of those.
  2. **The mask follows an animating item on its own, but tracks only x/y/width/height.**
     `PendingRegion::setItem` connects exactly those four signals (`src/core/region.cpp:39-46`) and
     the region is rebuilt once per polish (`src/window/proxywindow.cpp:660-667`), so no
     republishing is needed — and none of this is the `WindowBlurRegion` publish-now-and-settle
     situation above, which is a protocol commit on a surface that reconfigures. Neither `scale`
     nor `rotation` nor `opacity` is connected: express the motion as geometry only.
  3. **An `opacity: 0` card still publishes a full-size input region.** Collapse to 0x0 when idle —
     `build()` on a 0x0 item yields an empty region and `onPolished` then sets
     `Qt::WindowTransparentForInput` (`src/window/proxywindow.cpp:666`), which is the only thing
     making a permanently-mapped full-screen `Overlay` surface harmless. Shrink to a floor, fade,
     *then* zero, so the two do not fight over the same frames.
  4. **Reuse `quickshell:popup`, do not mint a namespace.** The card's body is `colLayer1Base`, so
     the `ignore_alpha = 1` note above already describes it exactly. A new namespace falls through
     to the catch-all `0.05`, under which a full-screen surface's *transparent* pixels clear the
     threshold and the compositor is asked to blur the entire screen.

  A `HyprlandFocusGrab` over such a surface **does** still clear on an outside click — the mask
  lets the click through to the compositor, which still classifies it as outside. Measured with an
  isolated `qs -p` probe before the design was committed to, because Hyprland's grab bookkeeping is
  per-surface rather than per-region and nothing in-tree had done it before.
  (d29cd6e45 ("feat(bar): add the static overlay surface the popup card will live on"),
  b22a923a5 ("refactor(bar): delete the per-popup layer surface").)
- **That card runs on ONE scalar, and the properties that used to be assigned are derived from
  it — including the coordinate the assignment existed to protect.** `card.openProgress` is a
  `real` 0 → 1 with a single `Behavior` on it; the fade *is* that number, and the height is a plain
  binding on it through `modules/imi/bar/bar_popup_unroll.js`. Four things about the arrangement
  are not obvious.
  1. **The hero-height unroll is why it is worth doing.** The card opens at the height of the
     content's **first drawn section** and unfurls to the full height along the same progress the
     fade rides, so the top edge never moves and the primary content is legible on frame one. The
     section is measured at its **drawn** height: a `Layout` child states its size through
     `Layout.preferredHeight` and carries no implicit height, so `implicitHeight` answers 0 for
     exactly the popups whose first section is a card. Measured on the real compositor with a
     125/100/75 stack at `contentPadding` 8 — hero 141, open 316, height tracking progress exactly.
  2. **A derived height is what finally lets the bar-adjacent coordinate be a binding.** On the
     bottom and right edges that coordinate is a function of the animating size, which is why
     `card.x`/`card.y` were *assigned* — two `Behavior`s easing a position and a size apart put the
     card's edge where its content is not. Deriving the coordinate from the size the driver already
     produces cannot drift from it, and neither side carries a `Behavior`, so it is not
     b710ef731's moving target. Measured: a bottom bar holds its card's bottom edge at 1390.0 on
     every frame of the open, the overshoot and the exit; a right bar holds 5064.0. Only the
     coordinate *along* the bar still travels.
  3. **The window's own `visible` predicate must read the card's INPUTS, never its derived
     height or opacity.** Reading the derived ones closes a circle through `visible` itself — the
     card's across-the-bar coordinate is derived from the window's size — and logs
     `Binding loop detected for property "visible"` twice per window on a live compositor, where
     the same probe against the old assigned geometry logged nothing. `openProgress`, `width` and
     `openHeight` are the safe three, and they are also what "collapse to 0x0 when idle" means
     now: a zero open height answers 0 at every progress, which is what empties the input region.
  4. **The content sits in a slot held at the settled height, not centred in the host.** A host
     that is shrinking centres what it holds, so the band on screen while the card is short would
     be the *middle* of the content — the first section, the one the card opens at the height of,
     would be the one thing not visible. Pinning it to the top of the host also keeps a leaving
     block still instead of reflowing it through every intermediate size.

  One tier serves both directions deliberately. Qt refuses a second write to a `Behavior`'s
  `animation`, so a directional pair would have to be a duration and a curve written onto a bare
  `NumberAnimation` — half a tier, and silently `Easing.Linear` the day someone drops the curve.
  The created animations are named properties so `morphing` can still ask whether the card is
  travelling, which the focus grab needs in order not to arm on a parked square.
  `tests/lint_bar_popup_overlay_static.py` refuses a second `Behavior` on the driver, any
  `Behavior` on `height`/`opacity`/`x`/`y`, an inline animation inside a `Behavior`, and a hero
  height that is a literal rather than a measurement.
  cd607d416 ("feat(bar): the popup card runs on one driver, and unrolls from its first section"),
  d01879f4c ("test(lint): hold the popup card to one driver, and its unroll to a measured hero").
- **A section added to a popup's content changes what the card opens at, and the hero is decided
  by the BUILT tree rather than by source order.** `heroSectionHeight` walks the content root's
  children and takes the first one that is drawn and taller than zero, so a row declared above the
  hero card becomes the hero — the weather popup would open as a 99px strip with the temperature,
  the city and the condition below the fold, which renders and looks deliberate. It also means a
  section that comes and goes cannot be first: `Weather.hourly` is empty until a forecast parses,
  and a hero that is a different section before and after the first fetch is a popup that opens two
  different ways. The hourly row therefore sits between the hero card and the metrics grid, and the
  measurement is checked on the built tree rather than in the source: hero 141 (the 125px hero card
  at `contentPadding` 8) against an open height of 431, unchanged by the row's 99.
  `tests/test_weather_popup_hero_runtime.py` parents the real popup's content into a window the way
  the overlay parents it into the card and measures both;
  `tests/test_weather_forecast_contract.py` holds the source order, which is the half a reviewer
  can see. feat(bar): draw the weather popup's hourly row, growing from the axis,
  test(weather): drive the popup's hero and the bars' growth in a real window.
- **Moving content between windows is already how popups work here, and it has two traps.**
  `StyledPopup` reparented its content into its window at completion long before the overlay
  existed; the overlay does the same thing, one popup at a time, and never has more than two
  content trees in a window at once. What that costs:
  - **An unparented tree does not polish, so its implicit size is stale.** `QQuickLayout` and
    `QQuickPositioner` size on the polish pass and polish only runs for items in a
    `QQuickWindow` — which is nine of the ten popup content roots. **You cannot measure the
    incoming content before you parent it**, so the card's target is computed one frame later on a
    zero-interval `Timer`. Do not "optimise" that deferral away; it is the difference between a
    correct first target and a two-stage snap from a stale size.
  - **Destroying the declaring component destroys the content even while it is on display.**
    `QQuickItem::setParentItem` changes the *visual* parent; the `QObject` parent stays the
    declaring object. `BarContent.filterLayout` drops `sysTray` when the tray empties and `plugin:*`
    when a plugin is disabled, so this is reachable by disabling the Docker plugin while its card
    is up. The declaring object has to vacate the shared slot from `Component.onDestruction`, or
    the card strands at its last size with a live input mask.
  Also: the outgoing tree is `enabled: false` for the whole cross-fade. It fades as a picture, not
  as a control — a click landing on the card mid-morph is aimed at the content the pointer moved
  toward, not at the 40%-opacity buttons still under it.
  (31493a21a ("feat(bar): teach StyledPopup and the overlay to hand the card over").)
- **A shared surface turns "which popup is open" into a claim, and a claim has to be made by
  everything that can be shown.** `GlobalStates.activeBarPopup` used to mean "the popup that just
  claimed the slot, so everyone else should close" and now means "the popup the card is showing".
  The claim was written only from `onTargetHoveredChanged`, which was invisible while each popup
  had its own window whose `visible` followed `popupVisible` directly — but the three click-toggled
  popups (tray overflow, Docker, Discord voice) never report hover at all: a `RippleButton` has no
  `containsMouse` and both plugin adapters set `hoverEnabled: false` deliberately. Under a shared
  card that is the difference between appearing and not appearing. `popupVisible` becoming true
  claims the slot too. The mirror-image rule is that a *pinned* popup holds the card and refuses a
  hover claim, and that refusal belongs on the claim rather than on honouring it — refusing to
  honour would leave `GlobalStates.activeBarPopup` pointing at a popup the card is not showing,
  which is a second silent notion of "current" for every later reader to get wrong.
  (70934c7e8 ("feat(bar): morph the three click-toggled popups, and let pinned hold the card").)
- **This whole area is invisible to the test suite.** Quickshell's plugin does not load in
  `qmltestrunner`, so `Region` cannot be constructed there and no test can see whether a region is
  empty, published, or ignored. Every bug in this section was found by looking at the screen, and
  two of them were misattributed first. Deploy, look, and prefer a frame-by-frame capture
  (`ffmpeg -fps_mode passthrough`) over an impression for anything that lasts under ~200ms.
- **A stored config value beats the QML default, so changing a default is invisible without a
  migration.** `Config.qml` defaults only apply to keys that are absent from the user's
  `config.json`, and every key the shell has ever written is present. Flipping a default therefore
  changes nothing for anyone who has run the shell - which is a silent no-op, not an error. Pair it
  with a one-shot migration guarded by its own `migrated*` flag, as `migrateDeadParallaxSwitches`
  and `migrateSplitCheatsheetButtons` do. Motivated by 65bd7696a ("feat(cheatsheet): draw a chord as
  one keycap per key").
- **The region selector intentionally takes exclusive focus.** Dismissable panels normally close
  when `GlobalFocusGrab` is cleared, but the selector first sets
  `GlobalStates.settingsHeldForRegionSelector` so Settings can remain visible in screenshots without
  racing surface creation. Because clearing the grab also empties its dismissable list, Settings
  must re-register itself when selection ends even though its own `visible` property never changed.
- **`WlrKeyboardFocus.Exclusive` is a session-wide grab, so a per-monitor surface must not take
  it.** A fullscreen overlay covering every screen can hold the keyboard — that is what makes the
  idle screensaver wake on any key without leaking the keystroke into whatever was focused. The
  same surface on *one* monitor cannot: the grab is not scoped to that output, so it swallows what
  the user types on the screen they moved to, and a saver that dismisses on a keypress therefore
  dismisses itself on their first letter. `modules/imi/screensaver/Screensaver.qml` picks
  `Exclusive` for the all-screens idle path and `None` for a deliberately blanked monitor. The
  pointer half of the same rule: getting back to work means moving the pointer *off* that monitor,
  which is motion across the surface being escaped, so a deliberate blank ignores motion and takes
  a click. afb1c7ea5 ("feat(screensaver): blank one named monitor, not every screen").
- **An idle inhibitor belongs to the *deliberate* half of a feature, never to the idle half.** The
  screensaver has two ways in — hypridle's 240s listener (`ipc call screensaver show`) and a
  keybind — and only the second holds `services/Idle.qml`'s inhibitor. Holding it on the idle path
  would mean a user who walks away is blanked at 240s and then never reaches lock (300s), DPMS off
  (600s) or suspend (900s): the ladder hypridle exists for, disabled by the thing that fires first
  in it. That is why the two paths are separate state (`GlobalStates.screensaverActive` vs
  `screensaverScreens`) rather than one flag with a mode. Two things generalise. The hold is a
  third bit ORed into the one existing `IdleInhibitor` rather than a second one — that window's own
  comment records a 0x0 surface mapping unreliably enough that Hyprland's ext-idle-notify ignored
  the inhibitor, and a second copy would re-learn it while giving "is the system awake" two answers
  to disagree about. And it is **derived** from the blanked-screen list rather than stored as a
  flag someone sets and clears, so it has no release path to forget: every way the saver comes down
  empties the list, and emptying the list *is* the release. If the shell dies while a screen is
  blanked, nothing leaks — a `zwp_idle_inhibitor` is destroyed with the `wl_surface` it was created
  on, and a client's surfaces die with its Wayland connection. 83544dedb ("feat(idle): a
  deliberately blanked monitor holds the keep-awake").
- **An exclusive zone that has to animate belongs on a surface of its own, and
  `exclusionMode: ExclusionMode.Ignore` is not in force while an `exclusiveZone`
  sits beside it.** A zone is a protocol value on the surface, so every write is
  a `set_exclusive_zone` plus a commit plus a compositor-wide re-arrange —
  animating one in place reconfigures the surface its own contents are being
  drawn on, once per frame. The bar therefore slid on a margin `Behavior` while
  its zone snapped between two integers, and the windows behind it jumped at the
  two ends of a gesture the bar spends 200ms on.
  `modules/imi/bar/BarExclusiveZoneReserver.qml` is where that animation lives
  instead: one `PanelWindow` per bar, one pixel thick, `color: "transparent"`,
  `mask: Region {}`, painting nothing, so a per-frame reconfigure costs a
  re-arrange and no repaint. **Both bars use the one component** — the zone is
  exactly the kind of decision the two have drifted on before. Five things about
  it are worth not re-deriving. Writing `exclusiveZone` at *any* value calls
  `WlrLayershell::setExclusiveZone`, which forces `exclusionMode` to `Normal`,
  and a `Normal` surface is placed inside what other surfaces reserve — so both
  bars had been in `Normal` all along despite declaring `Ignore`, and a bar
  keeping `exclusiveZone: 0` after this split would be pushed off the screen
  edge by its own reserver. Hyprland adds the anchored-edge **margin** to a live
  zone (measured: the bar's 40px zone under its 5px top margin reserves 45), and
  that margin is folded into the animated value rather than onto the reserver's
  own `margins`, or the last frame of a hide is a jump from the margin to zero.
  The namespace is the visible bar's, **passed in rather than minted**, for the
  reason `BarPopupOverlay` reuses `quickshell:popup`: a new one falls through
  the catch-all `ignore_alpha = 0.05` and asks the compositor to blur behind a
  surface that paints nothing — and since both bars' namespaces already carry
  `blur = false`, borrowing needs no `rules.lua` entry at all, which matters
  because that file ships separately and the two halves would otherwise come
  apart on any machine that updated one and not the other. The layer is `Top`
  and does **not** follow the bar's fullscreen+special promotion: an `Overlay`
  surface holds the fullscreen fast path shut whatever its size, the promotion
  exists to stop the bar's *pixels* being buried, and the reserved area is the
  same on every layer. And the zone must take the **same motion tier** as the
  bar's own slide — a different one disagrees with the bar for the whole gesture
  rather than only at its ends. None of this is reachable from the suite:
  `qmltestrunner` cannot construct the window and weston implements no
  wlr-layer-shell, so `tests/test_bar_exclusive_zone_reserver.py` pins the
  source shape and `tests/run_bar_exclusive_zone_probe.sh` reads the reserved
  area back out of a **nested Hyprland** while the zone animates (45 27 4 1 0
  through a hide, against 45 0 before). Design taken from
  `docs/p3drovfx-animation-research-2026-08-16.md` §3.4.
  97689e338 ("feat(bar): give the bar's exclusive zone a surface of its own"),
  7b703fc42 ("feat(bar): both bars hand their exclusive zone to the one reserver").

## State propagation is reactive, or it is a bug waiting

**"When X changes, refresh Y" must observe X — a property binding, a `Connections` handler, or an
explicit completion poke — never piggyback on an unrelated trigger that happens to fire often
enough.** The shell is an observer system end to end; a consumer wired as a callback of something
else's event inherits two defect classes at once: it goes stale for every X-change that does not
happen to fire the borrowed trigger, and it races every asynchronously-produced input it cannot
wait for.

The worked case is the SDDM greeter sync. Its inputs were refreshed only as a side effect of
matugen's color generation, so WE scaling changes never reached the login screen, and the
full-resolution still — grabbed a second *after* the config change that announced it — could be
produced after the copy and miss the greeter until the next unrelated color event. The fix
(a605450fd ("feat(greeterSync): observe the greeter's inputs instead of borrowing matugen's
trigger"); `services/GreeterSync.qml`, spec in
`docs/superpowers/specs/2026-08-05-reactive-greeter-sync-design.md`)
observes the greeter-relevant leaves and is poked by the grab's completion, with the expensive side
gated by an output diff so over-observation costs a hash, not a root copy. That gate is the general
enabler: make firing cheap, then observe generously — under-observation is the staleness bug,
over-observation is free.

If you find yourself adding a second caller to an existing hook "because it also needs to run
then", stop: name the input that actually changed, and observe it.

**A transient consumer observes by poking a cache, not by owning the producer.** The scheme
swatch preview was a `Process` plus a debounce living inside the settings page, which is fine
for a surface that exists for as long as the user keeps it open. Its second consumer is the
desktop menu's Wallpaper & style submenu — created and destroyed on every hover — so neither
option was available: copying the producer in re-quantizes a wallpaper per hover, and making
the producer a freely-running singleton burns a venv quantize on every wallpaper change for the
rest of the session whether or not anything is showing. `services/SchemePreview.qml` caches
against the inputs that produced the result (`sourcePath + mode`) and exposes a `refresh()` that
returns immediately while that key is unchanged, so a consumer coming on screen calls it
unconditionally and pays only when it would have been wrong. That is the same "make firing cheap,
then observe generously" gate as above, applied to a producer rather than a consumer.
(2b5ea4ce5 ("refactor(settings): make the scheme preview reusable outside the settings page").)

- **A `Connections` on a per-instance property fires on that instance's *first* binding
  evaluation, and you cannot tell that apart from a real change.** The bar popup overlay watched
  `barEdge` on whichever `StyledPopup` currently held the card, to idle the card when the bar flips
  orientation. Every popup derives `barEdge` from the same global `Config.options.bar.*`, so the
  per-popup signal carried nothing the overlay could not compute itself - but a popup that a
  `Loader` rebuilds on every open evaluates its own `barEdge` binding *after* the `Connections`
  targeting it attaches, and the handler ran `finishExit()` in the middle of the takeover that was
  building the card. The popup opened as a 20x20 dot, and only rendered when the race fell the
  other way: it took several clicks. The long-lived hover popups never showed it, because they are
  constructed once at startup and settled `barEdge` long before any `Connections` attached - so the
  bug looked like "the Docker popup is broken" rather than "the orientation guard is wrong". When
  the value comes from global config, derive it where you consume it;
  `tests/lint_bar_popup_overlay_static.py` fails on a per-popup watcher. 867dd811a ("fix(bar):
  watch the bar edge on the config, not on the popup holding the card").
- **A `HyprlandFocusGrab` is scoped by the surface's *input region*, not its extent, so a grab on a
  shared masked surface is not the grab a per-popup window used to give you.** Three bar widgets
  armed their own grab on the window holding their popup, which was correct while each popup owned
  a window sized to itself. Pointed at the one masked overlay, whose region is the card, a grab
  armed on the usual 16ms timer catches the card while it is still parked at
  `2 * elevationMargin` - so the next click anywhere reads as outside, closes the popup and
  destroys it. Outside-click dismissal belongs to whatever owns the surface and knows when the card
  settled; consumers get a `dismissRequested()` signal. A signal, not a write to `pinnedOpen`:
  SysTray *binds* that property, and assigning would break the binding rather than close the popup.
  0cec47e6f ("fix(bar): give the outside-click grab to the surface that owns the card").

**A service with a `refCount` and no producer reads as the live API and is a hole. Before writing
against any service, find the line that assigns the property you are about to read.** A reference
count is a strong claim - it says this resource is expensive, shared, and started and stopped for
you - and it is the part of a service a reviewer checks least, because counting looks like
plumbing rather than behaviour. `CavaService` declared `refCount`, `barCount: 32` and `values: []`,
and nothing in the tree ever assigned `values` or ran cava. Three widgets read it, three
incremented the count, and all three rendered nothing: no error, no warning, no log line, and a
green suite, because the QML tests never build them. The bands the shell actually drew came from a
`Process` inside `MediaControls` publishing to `GlobalStates.visualizerPoints` at 50 bands where
the service said 32 - so a fourth consumer written against the service, correctly, per its own
spec, was inert for the same reason
([#155](https://github.com/XephyLon/immaterial-impulse/issues/155)).

The failure is not "someone forgot the producer". It is that **two names for one thing let one of
them rot silently**, and the one that rots is whichever is not on screen. There is one band source
now: `modules/common/plugins/designsystem/services/CavaService.qml` owns the process, states the
contract (`barCount` = the `bars` in `scripts/cava/raw_output_config.txt`, `maxValue` = its ascii
range) and `GlobalStates.visualizerPoints` is gone rather than kept as a mirror. Consumers reshape
through `modules/common/functions/cavaBands.js` instead of each carrying a copy of both numbers,
and claim the process with a `CavaRef` - a declared claim rather than a hand-written
`refCount++`/`--` pair, because three hand-written copies existed and did not agree. Note the
import direction this creates: mainline modules (the bar, the right sidebar, media controls) now
`import qs.modules.common.plugins.designsystem.services`, which is core reaching into the vendored
design system. That is deliberate - the service is where the issue decided the process belongs -
but do not read it as licence for mainline code to reach into the design system generally.
`tests/test_cava_contract.py` fails the suite on a `refCount` declared in a file that starts no
`Process`, on a band count that disagrees with the cava config, on a consumer carrying its own copy
of the range, and on `visualizerPoints` coming back.
ce41c4f9c ("feat(cava): give CavaService the producer it always implied"),
bcf5f9ca1 ("refactor(cava): move every band consumer onto the one service"),
004a17745 ("test(cava): pin the producer, the gate and the band contract").

**Resampling a spectrum by picking one index per bar drops most of it.**
`Math.floor(i * source.length / barCount)` reads like the obvious way to fit 50 bands into 20 dots
and reaches exactly 20 of them; the other 30 are unreachable on screen no matter how loud they are,
and a peak landing between two picked indices simply does not appear. It was written that way in
two places. `cavaBands.js` averages the source bands falling in each output band when downsampling
and interpolates when upsampling, and returns zeros at the requested length for an absent spectrum
so a consumer's bar model keeps its shape while cava is not running.
bcf5f9ca1 ("refactor(cava): move every band consumer onto the one service").

**A side effect inside a binding runs once per re-evaluation, and a binding that reads what the
side effect produces re-evaluates because of it.** `services/LauncherSearch.qml` spawned `qalc`
from inside the `results` binding, which re-evaluates on every keystroke — and again when
`mathResult` lands, because the same binding reads the property the spawned process writes. So
every non-prefixed query started a calculator, repeatedly, to be told that an application name is
not a number: measured with a counting stub first on `PATH`, typing "firefox" started **8**
processes and "2+2\*10" started **7**, the extra one in each being the feedback re-fire. The file
search next to it already knew better and says so in a comment — the scan is kicked from
`onQueryChanged` precisely because calling it from the binding would loop. The general rule is
that anything a results binding *starts* belongs in the handler for the input that justifies
starting it, and the decision has to be answerable from that input alone (`services/math_query.js`,
which inspects characters and deliberately does not `eval()` the query to find out whether it is
arithmetic). ("feat(search): decide whether a query is arithmetic before spawning qalc").

**A property that a change handler reads must not be a binding on the same source the handler
hangs off.** Nothing orders a `onXChanged` handler against the re-evaluation of a
`readonly property bool` derived from `x`, so the handler sees the *previous* value. A gate
written as `readonly property bool queryIsMath: isMathQuery(query, ...)` and read from
`onQueryChanged` was one keystroke stale: the first character of every expression was dropped and
"2+2\*10" reached qalc as "2+", "2+2", … It reads as a debounce, not as a bug. Call the predicate
where it is needed instead of binding it. ("feat(search): decide whether a query is arithmetic
before spawning qalc").

**Turning a binding into a `Qt.callLater` rebuild buys coalescing and costs the dependency
tracking, so the tracking has to be written out and checked.** `LauncherSearch.results` is a plain
property now — every row is a `createObject`, and as a binding the whole list was rebuilt once per
input change rather than once per user action (a keystroke, the desktop-entry registry populating,
fourteen asynchronous settings-keyword greps, an fd scan and a qalc answer were five rebuilds
around one edit). What replaces QML's own tracking is `resultInputs`, a binding that touches every
value the builder reads and schedules the rebuild when any of them moves; be generous with it,
because firing is one array of references. Under-observation here is silent — the list simply
stops refreshing when that source answers, which for the asynchronous ones is the entire reason to
observe them — so `tests/test_launcher_result_inputs.py` fails the suite on a singleton the builder
reads that the tracker does not name, or forces it into a reviewed exemption. Only values read
while *building* belong there; what a row's `execute` closure reads is read when the user picks the
row. ("perf(search): rebuild the launcher results once per turn, not per input change").

## Dynamic/data-driven QML gotchas

Relevant to anything that instantiates QML components from external data (JSON manifests, config
arrays, etc.) rather than static declarations - e.g. the plugin system in
`modules/common/plugins/`:

- **`item[propName] = value` (JS bracket assignment) only resolves real top-level property names.**
  It does not walk a dotted path into a grouped property - `item["anchors.centerIn"] = parent` or
  `item["font.pixelSize"] = 20` will not do what it looks like it should; the real properties are
  `item.anchors.centerIn` and `item.font.pixelSize`, which bracket-notation string keys don't
  resolve into. If a data-driven schema needs to set grouped properties, either give the renderer
  explicit dot-path-splitting logic, or keep the schema flat and avoid grouped-property keys
  entirely.
- **A component-type/binding-target whitelist and the renderer that's supposed to honor it are two
  separate lists that can drift apart.** `PluginValidator.js`'s `componentWhitelist` and
  `PluginNode.qml`'s renderer `switch` need to name exactly the same set of component types - a type
  present in one but not the other means either "validates fine but silently renders nothing" or (if
  the renderer's list is the wider one) an unvalidated type reaching the renderer. Treat this the
  same as the Config-schema/settings-page two-sidedness described above: a change to one side isn't
  done until the other side matches.
- Bundled plugins that need behavior the data-only node tree cannot express may use a narrowly
  scoped renderer type, as `bundled/atAGlance/AtAGlance.qml` does for date formatting, timed quote
  rotation, and quote-file loading. Add that type to both the validator and renderer, and keep
  arbitrary processes or script evaluation out of manifests.
- **`Text` inherits `Text.AutoText`, which sniffs HTML-ish content and renders it as markup — so
  any widget displaying an attacker-controlled string is a rich-text injection site unless
  something pins its `textFormat`.** Installed plugin manifests are exactly that:
  `PluginValidator.js` type-checks `manifest.name` and nothing else, and manifest strings (name,
  description, author, option labels, icons, placeholders) reach the screen through `StyledText`,
  so `<img src=...>` in a manifest field rendered as an image. The per-site
  `textFormat: Text.PlainText` fix had been applied five separate times and still kept missing
  sites, so both `StyledText` definitions (mainline and the plugin design system's copy) now
  default to `Text.PlainText`, and rich text is a per-site opt-in reviewed into
  `tests/lint_rich_text_optin.py`'s allowlist — a new opt-in fails the suite until someone confirms
  no untrusted string reaches it unescaped (d782c2170 ("fix(widgets): default StyledText to
  PlainText, make rich text opt-in"), f224ec6b7 ("test(lint): pin the PlainText default and
  reviewed rich-text opt-ins")). Two corners that default cannot reach: the Basic Controls style
  (pinned by `pragma Env QT_QUICK_CONTROLS_STYLE=Basic`) draws `placeholderText` through its own
  `PlaceholderText` child *inside Qt* — still `AutoText`, fed `optionData.placeholder` straight
  from the manifest — so `ConfigTextArea` walks the field's children at completion and pins every
  `Text` to `PlainText` (dce31aa98 ("fix(widgets): force ConfigTextArea's style placeholder to
  plain text")); and the vendored `scripts/plugins/registry_validate.py` is a separate copy of the
  QML surface vocabulary that had drifted, letting an overlay-widget-only registry entry skip the
  screenshot requirement — `test_registry_validate.py` now pins its `VISUAL_CAPABILITIES` to
  `PluginManager.surfaceCapabilities` (6a359273a ("fix(plugins): require a screenshot for
  overlay-widget registry entries")). Do not "sanitise" manifest strings at parse time instead:
  stripping markup on the way in corrupts legitimate text containing `<`; the render site is the
  defence.
- **A type that redeclares its default property as `Item` cannot take a non-`Item` child at all.**
  `default property Item contentItem` on a `QtObject` root makes `Connections { ... }` declared
  beside it fail with `Cannot assign to non-existent default property` — the whole type goes
  unavailable, and every file using it reports `Type X unavailable` rather than anything naming the
  real cause. There is no `data` fallback to catch it, because a `QtObject` has no `data`. Wrap the
  non-visual object in an explicit property instead (`property Connections watcher: Connections
  {...}`, `property Timer t: Timer {...}`), which is what `StyledPopup` already did for its close
  timer and now does for its slot watcher. This surfaced when `StyledPopup` stopped being a
  `LazyLoader`; probed with `qml6` rather than reasoned about.
  (b22a923a5 ("refactor(bar): delete the per-popup layer surface").)
- **QtQml replaces `Date`'s locale methods with its own overloads, so ECMAScript's
  options-object form is not an error here - it is a different, plausible answer.**
  `toLocaleDateString`, `toLocaleTimeString` and `toLocaleString` take **(locale, format)** in
  QML, where `locale` is a `Qt.locale()` and `format` is a `Locale.*Format` enum or a Qt format
  string. Handed a browser's `date.toLocaleDateString(undefined, { weekday: "short" })` the
  engine does not recognise the object, falls through to the locale's short **date** format, and
  returns `"8/14/26"` where the call plainly asks for `"Fri"` - no warning, no exception, no log
  line. Use `date.toLocaleDateString(Qt.locale(), "ddd")`. Two things generalise past the one
  call. The test that should have caught it compared the function against **the same expression
  the function ran**, so it asserted only that the function agreed with itself and passed on the
  bug - the sibling of the UTC-runner problem pinned three functions up the same file, with the
  tautology in the assertion rather than in the environment. Check the *shape* of a localized
  answer (a weekday name carries no digits, three consecutive days are three different names,
  seven days on is the same name again) rather than an expected string no locale is obliged to
  produce. And a `.pragma library` is held free of `Qt` by
  `tests/test_weather_forecast_contract.py`, so the locale is passed in by the caller, which has
  an engine context. Found by rendering the widget and reading the labels; the whole of it is
  invisible from the source. fix(weather): a forecast card is named for its weekday, not for its
  date.
- **Both weather providers already return an hourly forecast in a response the shell has fetched,
  and OpenWeatherMap's `dt_txt` is UTC while its `dt` is the instant.** The bar popup's hourly row
  cost no new request: `/data/2.5/forecast`, fetched since the day cards landed, IS a three-hourly
  list, and wttr.in's `weather[].hourly[]` arrives inside the one response the current conditions
  come from. Before adding an endpoint for weather data, read what the existing responses carry —
  `tests/test_weather_forecast_contract.py` pins the endpoint list and the fetcher count so a third
  request has to be argued for rather than typed. The trap inside that data is the timestamp:
  `dailyFromOwm` groups by the `dt_txt` DATE, which is fine a day at a time, but an hour label read
  off the same field is the user's own clock wrong by their whole UTC offset — and right on a UTC
  runner, which is CI and was also every fixture anyone would write. `weatherHourly.js` reads `dt`
  and takes the local hour and the local date off it, and the contract test re-runs
  `tst_weather_hourly.qml` at UTC+14 and UTC-11 for the same reason it already re-runs the daily
  one. Planted: `getHours()` → `getUTCHours()` passes at UTC and fails at UTC+14.
  A third thing about that module generalises past weather: `Number(null)` is 0 and `isFinite(0)`
  is true, so the obvious "convert and test" guard reads an absent reading as a confident zero
  degrees — a bar at the floor and a window range dragged down to it, with nothing in any log.
  feat(weather): the hourly row's decisions, as arithmetic beside the daily ones,
  feat(weather): publish the three-hourly slots both providers already return.
- **`FileView` (`Quickshell.Io`) loads asynchronously - `.text()` right after calling `.reload()`
  is not guaranteed to return the new content.** The correct pattern (used throughout this codebase
  - `MaterialSymbolsSearch.qml`, `Notifications.qml`, `Emojis.qml`, `Profile.qml`) is to read
  `.text()` from inside the `onLoaded` handler, not immediately after `reload()`. A `PluginManager`
  rewrite that called `fileView.reload(); const text = fileView.text();` back-to-back silently got
  an empty string every time, with no error - only a `console.log` inside the failure branch (which
  never fired, since nothing *failed*, it just wasn't ready yet) would have revealed it.
- **`FileView.blockWrites` makes writes synchronous; it does not suppress them.** The whole
  `block*` family (`blockLoading`, `blockAllReads`, `blockWrites`) is about blocking the calling
  thread, not about blocking the operation - the names read like a permission switch and are not
  one. Setting `Config.blockWrites = true` to stop the shell touching `config.json` looks right,
  passes review, and writes the file anyway (`Config.qml`'s watchdog was written that way first;
  only `tests/test_config_dir_migration_runtime.py` reading the file back caught it). To actually
  not write, gate the call sites - `writeAdapter()` in `onLoadFailed` and the debounced write timer.
- **An unset `FileView.path` is a real "no file" state, and a useful one.** With `path: ""` the view
  emits neither `loaded` nor `loadFailed`, and `writeAdapter()` on it writes nothing - so
  `path: someGate ? realPath : ""` holds an entire `JsonAdapter` off the disk until the gate opens,
  rather than merely delaying a read. That is how `Config.qml` waits for the config-directory
  migration. Verified against a real `qs` instance; do not assume an empty path errors or creates
  a file somewhere.
- **`Repeater` only auto-binds a model item to a `required property` declared on the delegate's
  *root* object, not on a descendant.** `required property var modelData` on a widget nested a level
  or two inside the actual delegate root throws `Required property modelData was not initialized`
  for every instance. Put the `required property` on the outermost delegate item and forward it down
  as an ordinary (non-required) property if a nested child needs it.
- **`qs` is not a usable JS object from inside a `Qt.binding(function() {...})` closure.** It's a
  module-namespace prefix the QML engine resolves at compile time for declarative bindings, not a
  runtime global - `qs.modules.common.Appearance.colors[colorName]` inside an imperative closure
  throws `ReferenceError: qs is not defined`, silently leaving that binding's target property
  undefined (no crash, so it's easy to miss unless you actually watch the log with a plugin
  enabled). Import the singleton directly (`import qs.modules.common`) and reference it by its bare
  name (`Appearance.colors[colorName]`) instead. This one went unnoticed through two prior plugin
  merges (clock, battery) because `plugins.enabled` in the shared config was empty the whole time -
  the manifests were validated and rendered structurally, but never with `Appearance.colors.*`/
  `Appearance.rounding.*` bindings actually resolving against a real running instance.
- **A `RowLayout` rounds every item's width UP, so a fractional implicit width is drift rather
  than a fraction — and the repair is arithmetic that lands on whole pixels, not a `Math.round` at
  the call site.** The on-screen keyboard's rows are a grid of keys measured in keycap units, and
  a key spanning `u` of them has to cover the `u - 1` gaps it swallows or the rows come out
  different widths for the same span. At the old 45px key the pitch was 53, so a quarter-unit
  spacer was 18.5px wide and drawn at 19: the function row, which pads itself out with fourteen of
  them, came out **seven pixels** wider than the row below it, and every cluster to the right of
  the main block sat somewhere different on every row. Nothing errors, every row is still a
  perfectly good row, and the only way to see it is to print the drawn widths
  (`tests/run_osk_layout_probe.sh` does). Rounding at the call site would have kept the drift and
  merely made it consistent; a 44px key makes the pitch 52, and every quarter unit is then a whole
  number of pixels with nothing left to round. The sibling rule from the same file: a
  `Layout.fillWidth` item decides where every item *after* it goes, because what it absorbs is that
  row's own leftover — which is invisible while the fill item is last in the row and is why the
  keyboard's rows agreed before there was anything to the right of the spacebar.
  afd3bf661 ("fix(osk): make the key pitch a multiple of four, so a quarter unit is whole pixels"),
  e119c7b1d ("refactor(osk): no key fills the row any more").
- **A keyboard is a LATTICE, not a stack of rows, and a `GridLayout` does not
  hand out equal columns on its own.** The numpad's `+` and its Enter are one
  key two rows tall, which a `RowLayout` cannot say — so each of them shipped
  as two keys carrying one keycode, and the pad drew two Enters. The tool for
  it is `Layout.rowSpan`, and reaching it needs a column: every width in
  `modules/imi/onScreenKeyboard/key_shapes.js` is a multiple of 0.25u, so the
  quarter unit is the column, 1u is four of them and a row is 92.
  `osk_lattice.js` is the walk that turns the row-major layout data into cells
  — a key takes the next free columns in its row, a key taller than one unit
  claims the cells beneath it, and the row below steps over the claim — kept
  pure because nothing about a drawn key is reachable from `qmltestrunner`.
  The **layouts carry no coordinates**, which is what keeps a new key a line of
  data rather than a re-numbering.
  Three things about the grid are not obvious and all three were measured
  rather than reasoned about. **The engine spreads a multi-column item's width
  over the columns it spans and arrives at columns of different widths**: on
  the real component with nothing pinning them, the keyboard comes out 1197px
  wide against the 1188 its units buy, with a 13px gap before Backspace where
  every other gap is 8 — which is afd3bf661's drift arriving from the other
  side, and it is visible in a screenshot and in nothing else. A **declared
  lattice** fixes it: one zero-height item per column asking for exactly one
  column's width (`Lattice.columnWidth`, the pitch's quarter minus the spacing
  that follows it) puts every key back on a multiple of 13. It needs a **row of
  its own** — `QGridLayoutEngine::addItem` refuses a second item in a cell that
  is taken, so a ruler spanning the key rows is dropped with a console warning
  — and that row costs one `rowSpacing` which `OskContent` reports off its
  implicit height rather than resizing the grid to hide (a grid given less
  height than it asked for takes the difference out of a row of keys; a
  negative `Layout.bottomMargin` to cancel the spacing is clamped away).
  The ISO Enter is the one key that stays two: 1.5u on the top row against
  1.25u on the bottom, offset by the wider Caps, so it is an L and no cell of a
  rectangular lattice has that shape. `tst_osk_layouts.qml` allows a repeated
  keycode for that one alone, and counts a row's width off the lattice rather
  than by summing the row's own keys — the row under a double-height key does
  not declare the columns that key already took, so the old arithmetic reports
  the home row four units short.
  fix(osk): the numpad's + and its Enter become one key two rows tall,
  feat(osk): draw the keyboard on one grid, with the lattice declared.
- **Never `anchors.fill: parent` a `Loader` whose *own* size is meant to be derived from the loaded
  item's implicit size.** `Loader` forces the loaded item to match the Loader's size whenever the
  Loader itself has an explicit size (anchors count as explicit sizing) - but if the wrapping
  `Item`'s `implicitWidth`/`implicitHeight` are themselves bound to `loader.item.implicitWidth`,
  that's a direct cycle (item forced to match wrapper, wrapper's size derived from item) and Qt logs
  `Binding loop detected for property "implicitWidth"` and gives up re-evaluating it. Leave the
  Loader unanchored so it mirrors the item's natural size instead; set explicit width/height via the
  item's own properties (e.g. manifest `props`) when a fixed size is actually wanted.
- **Do not put dynamic object maps in a `JsonAdapter`, including through a `property var`.** Plugin
  ids and monitor names are not known when QML compiles, while `JsonObject` only supports declared
  properties. Writing undeclared children caused `JsonAdapter::deserializeRec` to segfault on the
  following config reload; declaring a `property var` map also segfaulted while loading it. Keep
  dynamic plugin layout in `PluginState.qml`, which parses and writes `plugin-state.json` with a raw
  `FileView`. Fixed-schema user settings still belong in `Config.qml`.
- Plugin manifests may declare a constrained top-level `options` array (`boolean`, `choice`, or
  `number`). `PluginOptions.qml` renders those controls and `PluginState.qml` persists their dynamic
  values. Desktop backdrop blur is also per-plugin state: a manifest opts into its default with
  `desktopWidget.blur: true`, while the generated **Blur background** option always lets the user
  override it. Do not make `PluginWidget` blur every plugin unconditionally.
- **A manifest's option keys and the host's own per-plugin state are one namespace, so `__` is
  reserved.** Both land in `pluginOptions[pluginId][key]` in `plugin-state.json`: the manifest's
  declared options *and* the host's `blurEnabled`/`positionLocked`/`clickThrough`/
  `keepTranslucent`/`followParallax` seeds, plus `__gridSize` (the span a user resized a grid
  widget to) and a `migrations` map beside them for one-shot store migrations. Note the five
  behaviour seeds are deliberately *unprefixed*: the prefix earns its place on `__gridSize`
  because that key is not a row a plugin could plausibly declare, while the toggles are, and
  renaming five live keys would need its own migration for no user-visible gain. A manifest declaring a
  `__`-prefixed key would therefore ship a settings control in Settings > Widgets that writes
  straight over host state. `PluginValidator.js` rejects it - which is the only defence against an
  installed third-party plugin, and silent for a bundled one, since a rejected manifest simply does
  not appear - so `tests/lint_plugin_option_keys.py` is the half that names the file. Anything the
  host stores per plugin from now on goes under that prefix; anything a manifest may set does not.
  66c022fbe ("feat(plugins): reserve the `__` option-key prefix for host state").
- **A widget's grid span is resolved, not read.** `manifest.grid` may offer several spans
  (`grid.sizes`) with `cols`/`rows` as the default, and the resolution - stored choice, then
  manifest default, then content-sized - lives in `modules/common/plugins/gridSizes.js` precisely
  because it is the one testable part (`tests/tst_grid_sizes.qml`; `qmltestrunner` reaches no
  further into this area). Two of its rules are refusals to repair a manifest, and both exist
  because the failure is silent and lands on a widget the user already placed: a `sizes` list whose
  entries disagree with the default, or that holds an unusable entry, is rejected whole, and a
  stored span the manifest no longer offers falls back to the default. Read the span through
  `PluginWidget.gridSize`, never `manifest.grid.cols` - the latter is the default, not the size on
  screen. See `docs/widget-grid.md`. 9c4adcc5f ("feat(plugins): resolve a widget's grid span
  through a testable module"), 494580b65 ("feat(plugins): resolve a placed widget's span from its
  stored choice").
- **`Array.isArray` is false for an array that has crossed a QML `model`, and the length is
  still right.** A JS array reaching a delegate through a `Repeater`'s `model` goes into
  QVariant and comes back as a list wrapper: indices and `length` survive, the `Array.isArray`
  brand does not. `gridSizes.js` gated a manifest's whole `grid.sizes` list on that check, and
  `Background.qml` builds *every* desktop widget from such a model — so a manifest declaring
  three spans reached the host offering one, with no grip, no size row and nothing in the log.
  The runtime harness passed throughout because it declares its synthetic manifests inline on
  the harness root, which never crosses a model; it now builds one widget through a `Repeater`
  as well. When validating data that arrives through a delegate, test for array-*likeness*
  (`typeof value.length === "number"`), and get one test onto the path that actually ships.
  109e6d897 ("fix(plugins): a manifest's grid.sizes survives the model boundary").
- **A widget's settings page shows the plugin's own options first and the host's in a
  "Widget behaviour" `ContentSubsection` below.** `PluginOptions.qml` used to concatenate its
  synthesized host rows in *front* of `manifest.options`, so every widget's page opened with
  four identical switches and the settings the user came for sat below them, reading as if the
  plugin had declared the switches too. The two groups share one delegate and must not be
  rejoined into one model (`tests/test_plugin_options_sections.py`). A host row that cannot
  apply is **omitted, not disabled** — `hasBlurSurface` for a bar-only plugin, and the Size row
  for a manifest offering a single span; the greying-out in that file is for a row that is
  *temporarily* inert (`enabledWhen`), which is a different thing.
  a03f1b266 ("feat(plugins): show a widget's own options above the host's"),
  008e51dc9 ("feat(plugins): offer a resizable widget's span as a settings row").
  **The host's booleans in that section are a toggle bar, not rows — a new one is a
  `behaviourRows` entry and nothing else.** Six `ConfigSwitch`es spent 212px of the card on six
  bits; a `FlowButtonGroup` of `IconToolbarButton`s spends 72px, so adding a seventh host boolean
  as a row would be both inconsistent and the expensive spelling. Two things about the bar do not
  generalise from a row and are checked: a glyph cannot label itself, so every toggle carries a
  `label` and the caption under the bar shows the hovered one — and, off-hover, which of them are
  on, which is the half of a switch row's label that selected-state colour does not replace; and
  the hovered label is cleared only by the toggle that wrote it, because a pointer crossing
  between two toggles delivers the leave and the enter in an order nothing here controls. The
  toggle is composed from `IconToolbarButton` precisely so the cursor, the toggled container
  states and the *single* application of the interaction motion come from the control rather than
  being re-earned (see the composites rules under
  [Dynamic/data-driven QML gotchas](#dynamicdata-driven-qml-gotchas)).
  b89908fef ("feat(plugins): draw the widget behaviour section as a toggle bar").
- **A desktop widget opts out of the parallax pan by cancelling it, not by being offset less.**
  The widget canvas is one item whose `x`/`y` *are* the widget parallax (`Background.qml`), so
  every widget on it travels because its parent does. `followParallax: false` therefore adds
  `-canvas.x` to the widget's placement — `ParallaxMath.parallaxCancel`, beside `widgetOffset`
  so it is testable — and the two summing to zero is what holds the widget still. The half that
  is not on screen: the drag runs in canvas coordinates while `PluginState` holds *placement*
  coordinates, and the gap between them is exactly the cancellation, so `commitPosition`
  subtracts it back out. Storing the drawn coordinate walks an opted-out widget by a whole pan
  on every drag, silently, because it looks right until the pan next changes. Anything else
  that reads a widget's `x` and means "where the user put it" has the same subtraction to do.
  95f851c28 ("feat(plugins): let a widget opt out of the desktop's parallax pan").
- **`PluginState` stores a widget's placement in the canvas's *rest* frame, and that is one
  meaning for every widget — do not let it become two.** A follower's canvas coordinate is
  already pan-invariant; an opted-out widget's screen coordinate is the same number, because
  `widgetOffsets` subtracts CENTRE and the canvas therefore covers the screen exactly at rest.
  So there is one clamp range (`[0, screenSize - widgetSize]`) for both, toggling the flag never
  rewrites a stored position, and `followParallax` is a *rendering* fact rather than a storage
  one. What differs is where the widget is **drawn**, which is the placement plus the
  cancellation — `ParallaxMath.drawnFromPlacement` / `placementFromDrawn`, a pair rather than the
  same arithmetic spelled out at each call site, which is how the render and the save came to
  disagree in the first place. 6acb5b0e8 ("feat(parallax): name both directions of a widget's
  placement conversion").
- **A `Behavior` whose target moves every frame restarts every frame and never ticks — the
  property freezes.** This is what made the parallax opt-out inert on a real desktop for its
  whole life: `x: placedX + parallaxCancelX` re-evaluates on every frame of `Background.qml`'s
  600ms pan, so `x` sat at exactly its pre-pan value for the entire transition and the widget
  travelled the *full* pan on screen before sliding back — the opposite of what the setting
  promises, and indistinguishable from "the toggle does nothing". Two consequences worth
  separating. On screen it is a wobble; **in the store it is corruption**, because `onReleased`
  runs `commitPosition` for *any* release (a click that never dragged included) and that
  conversion read a frozen `x` against a live cancellation, writing `placement + canvasOffset`.
  Every click or drag during a pan walked the saved position by one pan. The rule: a property
  carrying both a value that should animate and one that must not cannot animate at all — set
  `AbstractWidget.animatePosition: false` and say why. The corollary for tests is sharper than
  the fix: the runtime harness for this feature set `animateXPos: false` on both probes and
  panned by assignment, i.e. it switched off both halves of the interaction it existed to score,
  and stayed green for the entire life of the bug. b710ef731 ("fix(plugins): stop the position
  Behavior swallowing the parallax cancellation").
- **The mirror image of that rule: a binding that re-evaluates every frame is not a target
  that moves every frame, and a `Behavior` is fine on the second.** A desktop widget's span
  resize animates its `width`/`height` even though the grip re-previews on every mouse move
  and hands `previewGridSize` a fresh object each time — because the *value* the binding
  produces changes only at a span boundary, and Qt does not restart a running Behavior for a
  write of the value it is already animating to (`QQuickBehavior::write` returns early when
  the target value is unchanged). So the test is what the property is written *with*, not how
  often the binding runs, and the way to find out is to sample the property mid-change rather
  than to reason about it. Two things follow for anything animating a size here. Nothing may
  clamp, measure or persist against the *animating* value: the position clamp runs when the
  span commits, while the widget is still the size it is leaving, and nothing runs again once
  the animation lands — so `AbstractBackgroundWidget.clampWidth`/`clampHeight` exist for a
  subclass to point at the size it is heading for (a property rather than an argument on
  `clampX`, because a call site that forgets to pass one is silent). And a settled-size test
  passes identically on an animation and on the snap it replaced, which is why
  `WidgetResizeMotionRuntimeTest.qml` samples the width 80ms in and fails if it is already at
  the destination — the sibling grip harness scores only settled sizes and stayed green under
  every mutation of the motion. fa1e2a8b5 ("feat(plugins): animate a resizable widget's size
  between its offered spans"), 4e33a332a ("test(widgets): score a span change as in flight, not
  as a snap").
- **The third member of that family: where the layout writes the target, the motion is INVERTED
  from a measurement rather than eased onto the value.** A bar widget sits in a `Repeater` of
  `BarGroup`s inside a `RowLayout`, so its `x` is the layout's to write - a `Behavior` on it is
  handed a target that moves on every reflow, which is b710ef731 again. `modules/imi/bar/
  BarGroup.qml` therefore animates a `Translate` toward zero, set from the offset back to where
  the slot was drawn, which is FLIP (First, Last, Invert, Play); the arithmetic is
  `modules/imi/bar/bar_flip.js` because nothing about the rendered bar is reachable from
  `qmltestrunner`. Four things about it are worth not re-deriving.
  **The "First" cannot live on the slot.** Measured with a `qml6` probe: a `Repeater` whose model
  is a JS array answers a reassignment by destroying EVERY delegate and building the replacements,
  in one turn of the event loop - so the widget about to slide is not the object that was standing
  there, and a naive `onXChanged` inverse would start it from `x: 0`.
  `modules/imi/bar/BarFlipRegistry.qml` is one deposit-and-recall per bar, keyed on the widget id
  and expiring at the end of that turn: one per content tree rather than a singleton, because the
  ids are identical on every screen and the positions are not, and expiring because a widget
  switched back on ten minutes later has no honest position to fly in from.
  **What is measured is not what moves.** The survey's source watches the widget's own `x`. That is
  right in a near-edge bucket and wrong in a far-edge one: the section is sized by its row and
  anchored to the screen's edge, so removing a widget moves the SECTION and leaves the first slot
  at row-local zero - it travels the whole width of what left while its own `x` never changes, and
  the last slot's `x` changes while it does not move at all. Each slot sums its ancestors' x/y up
  to the registry's frame and watches every one of them. Deliberately a sum and never `mapToItem`,
  which composes transforms: measured through that, a slot part-way through its own reposition
  reports where it is DRAWN and the next invert comes off a number that is still moving.
  **It is inert outside a reflow**, because a bar widget's content changes width constantly - the
  clock every minute - and a running animation is a repaint of the whole output.
  **And it stands down for a reorder drag**, whose `layout_ops.dropTarget` centres are read through
  a `mapToItem` that composes exactly this transform; the drop's own reflow still animates, because
  `BarEditController` clears `editBarDragActive` before the layout pass that follows it. The popup
  overlay's card is unaffected for a different reason - its target is read only by its own
  `retarget()`, which a reposition never calls.
  Checked from both sides, because a settled position passes identically on the teleport this
  replaced: `tests/test_bar_flip_contract.py` holds the source shape (one registry per tree on the
  tree's own root, six delegate wirings each, no `Behavior` on a layout-written coordinate, no
  `mapToItem`) and `BarFlipRuntimeTest.qml` samples where each slot is DRAWN 40ms in. That sample
  is early on purpose - the spatial tier is front-loaded, so by 80ms a correct reposition and one
  started on the mirror side of its destination are both ~90% of the way there. Design taken from
  `docs/p3drovfx-animation-research-2026-08-16.md` §3.5.
  b155851422 ("feat(bar): a bar widget slides to its new slot instead of teleporting"),
  2bc474d53a ("feat(bar): bar_flip.js, a slot's reposition as arithmetic"),
  bd60b78a31 ("test(bar): the harness stops rescuing the idiom it exists to fail").
- **A sweep over ordered PAIRS is not a walk, and a trail's floor is in the trail's own units.**
  Two ways a span-motion harness reports confidently about a transition it never ran.
  `WeatherTreeMotionProbe` drives a list of `[from, to]` pairs but only ever committed `to` — so
  `3x2 -> 2x1`, which follows `3x2 -> 3x1` in the list, started from 3x1: the sweep measured
  `3x1 -> 2x1`, printed a green trail for every element under the `3x2->2x1` label, filed its
  settled shot as `3x2_settled.png`, and the one pair whose card shrinks in **both** axes was
  never exercised at all. A pair the sweep names has to be a pair the sweep runs — reposition to
  `from` first, on its own settle. Separately, the "did this move" floor was `0.5` for every
  trail, which is right for a position, a size or a font and nonsense for an opacity: the weather
  card's sun arc leaves 1x1 by fading `0.32 -> 0`, a complete disappearance and a change of
  `0.32`, so the pixel floor filed the one trail that had to move as `static`. Note the failure
  direction on both — neither reddens, both go *quiet*, and a probe that says nothing about an
  element reads exactly like a probe with nothing to say about it.
  test(weather): the probe runs the pairs it names,
  test(weather): the probe scores the arc's fade, its travel and an unknown day.
- **A change handler that writes the state its own binding reads is a binding loop, and Qt
  drops the re-evaluation rather than erroring where you are looking.** `PluginWidget` repairs a
  resized widget's stored position from `onStoredGridSpanChanged`, and that repair calls
  `PluginState.setPosition` — which is the state `storedGridSize` is derived from, so the write
  lands inside that binding's own evaluation and the log says `Binding loop detected for
  property "storedGridSize"` at the *call site's* file. A zero-interval `Timer` moves the write
  one turn of the event loop out of the evaluation and costs nothing, since what the widget is
  drawn at was already clamped by a different path. fa1e2a8b5 ("feat(plugins): animate a
  resizable widget's size between its offered spans").
- **A third failure in the same family: a `Behavior` *retriggered* every frame does tick,
  forever, and nothing on screen shows you.** Where the parallax bug was a frozen property, this one is a
  property that never rests. `CavaService` gated cava on `MprisController.activePlayer !== null`
  — but a *paused* player is still an active player, and cava visualises whatever is **audible**
  rather than the tracked player's stream. So three paused players left cava decoding a
  fullscreen game's sound, each spectrum retriggered the bar visualiser's twenty `Behavior on
  height` animations, and those tick at the display's refresh rate. Measured on a 240 Hz output:
  the bar's render thread ran at **237 fps behind a fullscreen game**, and `SIGSTOP`ping cava
  took it to 33. The generalisation is about gates, not about cava: **"a thing exists" and "the
  thing is doing something" are different predicates, and animation cost follows the second.**
  a57cd00b2 ("fix(cava): gate the spectrum on playback, not on a player existing").
- **A surface the compositor *covers* is not a surface QML considers hidden — `visible` stays
  true and no guard written against it will fire.** `Bar.qml` picks `WlrLayer.Top` precisely so
  fullscreen windows bury the bar (Overlay only while a special workspace sits on top). That is
  occlusion, and it happens entirely below Qt: the surface stays mapped, the item tree is
  untouched, and the bar happily animates for nobody. Contrast the desktop widgets, which *are*
  hidden properly — everything they draw hangs off `parallaxViewport`, and `Background.qml` sets
  `visible: false` on it, so `visible` (the effective value) is the correct guard there. Before
  gating work on visibility, establish which of the two you have; the wrong one reads identically
  in the source and does nothing at runtime. Diagnosing this took stack-sampling the render
  thread, because every cheaper signal said the widget was fine.
  53d1ff893 ("fix(bar): drop the cava claim while a fullscreen window covers the bar").
- **A widget's card surface comes from `WidgetCard`, not a hand-rolled tint pair.** The
  `useBlurBackground ? applyAlpha(tint, opacity) : tint` conditional was written seven times across
  the desktop widgets — the spec's own survey counted four, and the lint that now reserves the
  pattern to the component (`lint_widget_card_tint.py`) found the other three on its first run.
  `WidgetCard` owns the tint, the rounding, an optional content clip, a `blurRegion` record, and a
  `shapeName` parameter that turns the card into a stretched `MaterialShape` (which morphs on any
  shape change, because `ShapeCanvas` does). b362d8c80 ("feat(widgets): one card component for the
  surface every widget redrew").
  calendar was the exempted copy and is not any more, and two things about adopting the card are
  worth carrying to the next one. **The tint the card takes over is the card's own, not every
  surface a widget paints**: calendar still thins its 1x1 banner, its month pill, its day grid and
  today's highlight so the frost reads through the whole widget, and it does that with
  `transparentize` rather than the card's `applyAlpha` because `colLayer1` already carries an alpha
  the widget must *scale* rather than overwrite — `lint_widget_card_tint.py` leaves a content tint
  alone, and the next entry is how it now tells one from the card's own. And **the card routes children into its own
  content item**, so anything that anchored to the old `Rectangle` by id (calendar's two corner
  handles did) has to anchor to `parent` instead: an anchor may only name a parent or a sibling, and
  the card is now the grandparent. Neither of those is caught by the tint lint;
  `test_expressive_design_system.py` pins the composition and `test_calendar_card.py` renders it,
  because a content-sized widget whose card failed to resolve is a zero-size widget rather than an
  error. 486272dbe ("feat(calendar): draw the widget's surface on the shared card").
- **A widget that paints its own root surface hides the card, so it has no shadow at all — and a
  carve-out written as a spelling stops being a rule the moment someone spells it differently.**
  `notes` and `image-converter` were both a root `Rectangle` painting
  `blurEnabled ? transparentize(colSecondaryContainer, ...)`: the card's own surface, written in the
  *content* tint's dialect. `lint_widget_card_tint.py` matched only
  `useBlurBackground ? applyAlpha(` and waved both through, so they shipped as the two widgets on a
  twelve-widget desktop casting no shadow — and neither could have lifted on hover or drag if one
  had been added, since neither declared `hostDragging`. Note the cost is not the redundancy the
  card was extracted to remove: a root surface is painted *over* the card, which is why the symptom
  is absence rather than a second slightly-different tuning. The lint now decides by **position**
  rather than by helper name — it reads the root object of every desktop widget's entry point,
  found from the manifests' `desktop-widget` capability (so `discordVoice`, a bar/overlay panel and
  not a desktop card, is out of scope by the data rather than by an allowlist), follows one level of
  `color: root.someProperty` indirection, and flags a blur-gated tint there whichever helper it
  calls. Content tints, which are surfaces *inside* the card, stay free.
  test(lint): the card-tint carve-out is scoped to content, not to a spelling,
  fix(notes): draw the widget's surface on the shared card.
- **The resize grip accumulates tension; it does not pick the nearest span.** A widget holds its
  span while pull builds, gives one offered span per 60px breakaway with the remainder carried, and
  rubber-bands at a wall. `resize-tension.js` owns every constant and all of the arithmetic; the
  host exposes the live bow as `resizeBow`, injected into wrappers as `hostResizeBow` by the same
  duck-typed pattern as `hostGridSize`, and a `WidgetCard` renders it via `tensionX`/`tensionY`.
  Two things to know before touching it: spent pull must move the gesture's origin (the grip
  re-bases its press point by exactly what a give consumed, or the next mouse event re-delivers the
  pull and the resize sprints to the largest span), and a sub-breakaway regression probe is only
  meaningful at a span with somewhere to step - probed at a wall, both semantics hold the span and
  the check is vacuous. ccde619bf ("feat(plugins): the grip accumulates tension instead of picking
  the nearest span").
- **One painter owns a widget's body surface at every span - other painters ride it, never
  replace it.** Handing the media play button's face to a second canvas at a settle blanked it
  twice in one branch: a visualizer crossfade (the static twin masked every inward ripple, and the
  "fixed" version left an empty face when the second canvas's first paint did not composite), then
  a seeker-fill handoff that shipped and died within one probe run. The body canvas draws every
  span and every transition; the visualizer's pipeline lives INSIDE it, and the seek ring strokes
  over it. Related: hover STATE and the pointer CURSOR are different channels - two cooperative
  HoverHandlers on stacked items both report hovered while arguing over the cursor (Arrow won),
  which passed every hover assertion while the cursor never changed. Input areas own their
  cursors; z order guarantees the interactive thing is topmost.
  05bf3013f ("feat(media): the play button's body IS the visualizer").
- **A layer clips at its item's bounds, so anything drawn outside needs the item grown first.** The
  widget card's shadow (`Appearance.elevation`, one `MultiEffect` over a frame wrapping all three
  body renderers) is taken from the BODY, never the card: over the card it would put a shadow under
  every label and glyph inside it. That frame is inset NEGATIVELY by the bow's reach, because the
  elastic-resize canvas deliberately draws up to `2*BOW_PX` outside the card and a layer would cut
  it. The shadow is dropped while the card is moving and restored on settle, for the same reason the
  frost is: re-rendering a blurred copy of the body every frame of a morph is the expensive path.
  **That last sentence shipped half-true, and the correction is the lesson.** `motionActive` had
  exactly one producer - `WidgetCard` passing its own `underTension`, the grip's elastic bow - which
  is the one motion that does NOT resize the layer. The span animation, which reallocates the FBO
  and re-runs the gaussian every frame, and which every Size row in Settings takes with no grip
  involved, ran with the shadow live throughout: `resizeBow` is already zero when the settle begins.
  Neither probe could see it, because both ASSIGN `motionActive` rather than driving motion - the
  parallax-opt-out shape, a harness that switches off the interaction it exists to score. The host
  publishes `boxInMotion` (drawn box vs settled box) now, forwarded by the same duck-typed path as
  `hostGridSize`, and `test_the_shadow_is_dropped_for_the_motion_that_actually_costs` pins the chain
  end to end. e5d243c5e ("fix(widgets): the shadow drops for the motion that actually costs").
  Verification is pixels, not source text (`test_card_shadow.py`), and two traps live there:
  `ItemGrabResult.image` is not scriptable from QML, so analysis belongs outside; and `grabToImage`
  captures the ITEM, so a field relying on its WINDOW's colour grabs a transparent PNG whose "white"
  reads as black to any analyser - a measurement that looks like a catastrophic failure when nothing
  is wrong, and would equally hide a real one.
  4046f1854 ("feat(widgets): the card casts a shadow, and lifts when handled").
- **The elevation is a component of its own, and it is what a widget that is not a card reaches
  for.** `WidgetElevation` owns the numbers, the hover/drag lift and the layer; `WidgetCard` hands
  it the states and adds a surface. That split exists because five bundled widgets cannot be cards
  — a cookie dial, a punched glyph grid, a shape-masked image, and a card with an avatar bubble
  off its top edge — and each had carried its own `StyledDropShadow` at its own radius and colour
  since long before the card. The elevation shadows **painted alpha**, so a cookie casts a cookie
  and a `Heart`-masked photograph casts a heart; the corollary is that it goes around the BODY, and
  a widget wrapping its whole self in one gets a shadow under every label it draws. The bleed is
  added on the frame carrying the layer and taken straight back off the body, so children see the
  item's own box and no call site compensates for the inset. Do not spell a second `MultiEffect`
  shadow from `Appearance.elevation` — `test_expressive_design_system.py` fails the suite on a file
  other than `WidgetElevation.qml` reading those numbers, and on `StyledDropShadow.qml` coming
  back, because what this replaced was five hand-rolled shadows behind **two** components of that
  one name in two directories, none agreeing with any other.
  ("feat(designsystem): move the card's elevation into a component of its own").
- **A gate on a `Config.options` key that was never declared reads as `undefined` and takes the
  `??` fallback for ever.** The pixel clock's drop shadow was `visible:
  Config.options.background.widgets.enableShadows ?? false`, and no `Config.qml` has ever declared
  `enableShadows` — so that widget alone had no elevation at all, silently, for the whole life of
  the feature, and the QML reads perfectly. Nothing warns: an undeclared key on a `JsonObject` is a
  plain `undefined` property read, not an error. When a feature is gated on config, grep `Config.qml`
  for the key rather than trusting the expression, and prefer a gate whose absence is loud.
  ("feat(clock): the cookie and the pixel grid take the shared elevation").
- **The same hole is open on `Appearance`, and there arithmetic on the missing token is *quieter*
  than reading it.** `Appearance.rounding.button`, `.card` and `.extraLarge` were read by six
  design-system call sites from the day that library was ported and were never declared. Measured
  side by side against the real singleton, the two spellings fail differently and the difference is
  the whole lesson: `radius: Appearance.rounding.card` is rejected at the assignment boundary, so it
  costs one `Unable to assign [undefined] to double` and stores **0** — a square corner that reads as
  a design choice — while `Appearance.rounding.extraLarge - 10` is **NaN**, which is a legal double
  that no boundary rejects, nothing logs at all, and that survives every arithmetic downstream.
  `Math.max(0, NaN)` is NaN, so the clamp anyone reaches for does not repair it either; the guard has
  to be a comparison (`x > 0 ? x : 0`). Neither the QML suite nor `DesignSystemCompile.qml` can see
  any of it — the first never builds these widgets and the second only *compiles* components, and a
  binding is evaluated by neither. `tests/lint_appearance_tokens.py` resolves every `Appearance.`
  chain in the tree against a parsed `Appearance.qml`; its first run found twelve more names the same
  port left behind, which sit in that file's `QUARANTINE` register until each gets a value decision
  rather than a plausible number. Note the general shape: a token, a config key and a service
  property that were never declared all read as `undefined`, and `undefined` is a value.
  ("fix(appearance): declare the three shape tokens the design system reads"),
  ("test(lint): fail on a QML file reading an Appearance token that is not declared").
- **A number chosen to silence that check is worse than the bug, because it renders.** The three
  tokens above are declared as *aliases* onto tiers `Appearance.rounding` already had (`button:
  small`, `card: normal`, `extraLarge: verylarge`), each picked against
  [`docs/M3_GUIDELINES.md`](docs/M3_GUIDELINES.md)'s ladder and against what the in-house siblings
  already do — the mainline `RippleButton` defaults to `small`, `ResourceCard` and
  `GroupedList.bigRadius` are `normal`, and every in-house host of the carousel block is `verylarge`.
  Aliases rather than fresh numbers on purpose: a tier with two values is the drift the one-source
  rule exists to stop, while a tier with two names cannot disagree with itself, and
  `screenRounding: large` was already the precedent. `tst_spacing_scale.qml` pins both the ladder's
  numbers and the aliases, so giving `card` a fourth independent number reddens rather than shipping
  two subtly different card radii.
  ("test(appearance): pin the rounding ladder and the three tokens it aliases").
- **Scoring a shadow on a widget that is not a rectangle wants the widget's own twin, not a band.**
  `test_card_shadow.py` reads a strip below a card, which works because a card's bottom edge is
  where the box says it is. It measures a different thing for a cookie (whose bottom is a valley),
  for a glyph grid that overhangs its own box by 8%, and for a card inset 20px from the bottom of
  its tile. `test_widget_elevation.py` renders each widget three times — at rest, handled, and with
  `motionActive` forced on — and scores each cell against its own suppressed twin, so the shadow is
  exactly what the cells differ BY and no per-widget geometry is involved. The probe drives all
  three columns duck-typed (`hostDragging`, and `motionActive` on anything exposing
  `shadowVisible`), which is why no widget carries a property that exists only for a test.
  ("test(widgets): score the five folded widgets in pixels, not in spelling").
- **A morphing container brings its polygons; the mechanics are shared.** `shape_morph.js` owns the
  bounds, the endpoint short-circuit and the Morph cache for every container that morphs between
  named shapes (media's body, weather's glyph, currency's badge); a widget passes a
  `name -> RoundedPolygon` resolver and gets `at(from, to, t)`. Each container keeps its OWN caches,
  because two widgets can both call a shape "panel" and mean different polygons. Bounds are MEASURED
  mid-flight and PINNED at the endpoints - the interpolated cubics' measured extent wobbles by a
  hair at a settle threshold, and a hair of scale reads as a flicker. Likewise `SpanTravel`/
  `SpanFade` are the one spelling of how a shared element travels and how one with no home at the
  next span leaves; there were twenty-three copies of that NumberAnimation before, and a tree that
  spells its own can drift from the others by a curve without anything warning. Both extractions are
  enforced (`test_the_trees_share_one_spelling_of_the_span_animations`,
  `test_the_morphing_containers_share_their_mechanics`) - the point of extracting was to stop the
  fourth copy, so the check is the deliverable, not the module.
  e62584f17 ("refactor(designsystem): the morph mechanics become one module").
- **A state property that says "hovered" is not evidence a pixel moved.** The media badge's hover
  lift shipped through `transform: Scale { origin.x: width / 2 }`, whose `width` resolved against a
  scope that has none - the model reported `hovered`, `scale` read 1.02, and the badge measured
  60px before and 60px after on the desktop. `Item.scale` is centred by default and cannot miss it.
  A probe that asserts only the model's value passes this happily, so the sweep now also reads the
  scale of the item that is DRAWN (`appliedBadgeScale`), which is the check that fails. Related: at
  2x2 and 2x1 the seek ring sits ABOVE the play button, so after a press grab ends the pointer's
  leave goes to the ring and a `MouseArea.containsMouse` under it never clears - the button sat
  permanently hovered, and at 2x2 that means the play glyph never leaves the artwork again. Hover
  STATE belongs to a `HoverHandler` there; the cursor and the clicks stay with the MouseArea, which
  is the same channels rule as 05bf3013f, applied the other way round.
  0b9a5df1e ("feat(media): the transport controls adopt the interaction model").
- **A Behavior whose animation reads its tier from a binding carries the PREVIOUS transition.** The
  shared interaction model (`Appearance.interaction`, decided in `modules/common/interaction_motion.js`)
  gives every control the same five states, and each pair of states has its own duration and curve -
  a press is acknowledged faster than it is released, and a release animates even when the pointer
  has already left, because press → drag off → let go is `pressed -> rest` with no hover in between
  and treating that as a hover-out leaves the control visibly stuck. Selecting the tier through a
  binding on the animation's `duration` hands the Behavior whichever tier was current *before* the
  state changed; `InteractionMotion.qml` therefore writes the tier onto the animation and only then
  writes the target, in the same handler. Interruptibility comes free from the Behavior itself - a
  press landing mid-hover retargets from where the value actually is, which a `SequentialAnimation`
  fired on a signal cannot do. Related: `lint_disabled_opacity.py` recognises a self-dimming control
  by its dim EXPRESSION, so adopting the model made `RippleButton` invisible to it and would have
  vacated the nested-dim rule for every component rooted on one - a detector that knows only one
  idiom stops detecting the moment the idiom changes.
  af09ed3b9 ("feat(widgets): one driver wires a control to the model").
- **The model's motion is applied by the CONTROL, and a caller that adds its own composites with it
  rather than replacing it.** `Item.scale` and a `Scale` transform multiply down the scene graph
  exactly the way `opacity` does, so the mirror image of the doubled-dim rule above holds for the
  transform: a `scale: down ? 0.88 : (hovered ? 1.08 : 1)` written on the contentItem of a
  `RippleButton` does not override `interactionMotion.scale`, it stacks on it. discordVoice's overlay
  shipped that on its mute and deafen glyphs — 1.02 × 1.08 on hover, 0.97 × 0.88 on press, roughly
  five times the intended excursion, on `OutBack` instead of the model's curve, and with one duration
  standing in for the five tiers. The same two buttons in that package's *popup* were written without
  it, so two copies of one control disagreed about how hard it squishes. Take the control's motion;
  where feedback is not a multiple of anything, read `hoverProgress`/`pressProgress` rather than the
  raw flags. `tests/lint_interaction_motion_double.py` fails the suite on a scale-family property
  written from a raw hover/press flag anywhere inside a control that applies the model — a *separate*
  file from `lint_disabled_opacity.py` on purpose, since that one keys on a dim expression and was
  blind to this for the whole life of the widget. It resolves which types apply the model rather than
  naming them, reads a declaration whole (block-bodied values included), and self-checks against an
  in-memory fixture so the machinery is proven independently of what the tree contains.
  f62673b7f ("fix(discordVoice): let the button own the hover and press motion"),
  1d5d196fd ("test(lint): fail on a hover/press scale inside a control that already scales").
- **A radius composites too — through the control rather than through the scene graph — and the
  lint above knew only the transform, so it wrote the next case up as a note instead of failing on
  it.** That first version named `modules/imi/sessionScreen/SessionActionButton.qml` in its own
  sweep, right here in this file and in `docs/widget-standards-audit-2026-08-16.md`, as a neighbour
  it was not fixing: the button keyed `buttonRadius` on `button.down` while `RippleButton` was
  already tightening. It reasoned that a `pressProgress`-driven radius "composites with nothing",
  which is true of the scene graph and false of the control —
  `RippleButton.buttonEffectiveRadius` is *computed from* `buttonRadius`, so a caller keying that
  on `down` has its own value multiplied by `pressRadiusScale` on the way to the corner. The two
  sources pulled opposite ways, so this did not read as too much squish: measured on the real
  component, a press took the corner **30 → 51** — the button's own jump to `size / 2`, then the
  model's 0.85 landing on the circle — where every other control tightens. It is 30 → 25.5 now.
  Three things generalise. The `focus` half stayed, because that is the session grid's keyboard
  cursor and the model has no state for it; a control may still own a shape the model does not
  name. `tests/lint_interaction_motion_double.py` is per **channel** now — a file is a control in
  the channels it actually applies the model in, so `MediaTransportButton` (which scales and does
  not tighten) is not held to the radius rule — and the radius detector reads a *whole*
  declaration, because both `RippleButton`s spell `buttonEffectiveRadius` across two lines with
  `pressProgress` on the continuation, and a line-scoped version finds no radius control at all and
  reports a clean tree. And the rule reaches only controls that apply the model:
  `common/widgets/GroupButton.qml` drives its own `down`-keyed radius and bounce and has never
  adopted it, so it is a non-adoption rather than a doubling and the lint leaves it alone.
  fix(sessionScreen): let RippleButton own the session button's press,
  test(lint): fail on a hover/press radius inside a control that already tightens.
- **A one-tree widget's geometry reads the SETTLED span's box, never the animating one.** Three
  trees were written with `spanW: root.implicitWidth`, and `implicitWidth` carries a Behavior: every
  rect became a per-frame target, so the Behaviors that carry the travel never converged, and any
  rect measured from the right edge (the media play button, the weather glyph, the currency panel
  and its cells) crawled behind the card instead of travelling with it. The settled width is a
  function of the span name alone. A widget's SHAPE also morphs off a t that must be reset through a
  closed gate - writing `morphT = 0` through a live Behavior retargets it, which is a snap wearing
  the morph's clothes. Both are checked:
  `test_geometry_rects_come_from_the_settled_span_not_the_animating_box`.
  189caa6ff ("fix(weather): geometry reads the settled span, not the animating box").
  That check sweeps for the declaration rather than naming the trees, and reads the **whole**
  declaration rather than the line carrying it - because two of the three spans are written as a
  block (`readonly property real spanW: { if (sizeMode === "1x1") ... }`), and a line-scoped check
  sees only the opening brace. It read `readonly property real spanW: {` for weather, the largest
  of the three files it named, and would have passed on `return root.implicitWidth;` one line
  below. Any source-text check over a QML property has the same question to answer: is the value a
  line or a block?
  test(widgets): sweep for the settled-span rule instead of naming three files.
- **A widget the host does not size gets neither of the host's two resize services, and the
  absence of both is silent.** `PluginWidget`'s `Behavior on width`/`height` is
  `enabled: gridResizeAnimated`, which is `gridSized && PluginState.ready`, and `boxInMotion`
  compares the drawn box against `settledWidth`/`settledHeight` — which for a content-sized
  widget *are* `rootWidget.width`/`height`, so it is false forever. A widget that declares no
  manifest `grid` because its own handles own its size (calendar, world-clock) therefore snaps
  between sizes **and** keeps its card's shadow re-blurring a copy of the body into a
  reallocating layer for every frame of whatever motion it does perform — the exact cost
  e5d243c5e removed for span widgets. Both halves belong to the widget: it animates its own
  implicit size towards the settled span, and publishes its own `boxInMotion` for the card
  (`hostMotionActive: root.hostBoxInMotion || root.boxInMotion`, so a host that ever does report
  it still wins).
  feat(calendar): morph the calendar in one tree instead of rebuilding it.
- **A one-tree widget needs `WidgetCard.clipContent`, and a per-span Loader did not.** A
  destroyed subtree stops existing when the card shrinks; a faded one does not. Calendar's day
  grid and five of its six rows, and the world clock's local time and date, all sit below a short
  card's bottom edge while they fade, and unclipped they paint onto the wallpaper for the whole
  morph. The corollary is the reason a fading block must also **stand still**: pin it to its own
  span's box rather than anchoring it to the card, or it reflows through every intermediate size
  on the way out, which reads as the content being squeezed rather than as it leaving.
  feat(world-clock): morph the world clock in one tree instead of rebuilding it.
- **A desktop widget's frost drops out for the length of any box animation, and it is not the
  morph's fault.** Measured frame by frame on the desktop: through a span change the card body
  goes to its bare tint over a *sharp* wallpaper and the blur comes back only once the box
  settles. This predates the one-tree work — the same burst on `nandoroid-weather`, which has
  animated its box since fa1e2a8b5, shows it identically — it was simply invisible while calendar
  and world-clock snapped. The likely mechanism is that `PluginWidget`'s frost `Repeater` takes
  `pluginNode.blurRegions` as its model, and a card's `blurRegion` is a fresh object on every
  frame of a resize, so the `WallpaperBlurSurface` delegates are destroyed and rebuilt per frame;
  that is a reading of the source, not something anyone has proved, and the way to settle it is a
  `Component.onCompleted`/`onDestruction` count on the delegate during a resize.
  feat(calendar): morph the calendar in one tree instead of rebuilding it.
- **An element that changes its TEXT across spans is two elements, not one.** The currency base
  code read "to USD" at 1x1 and "USD" at 2x1 from a single `StyledText`, so the content swapped in
  one frame in the middle of an otherwise continuous morph. "to" is its own element that fades,
  and the code slides left into the space it vacates as it goes. The same rule retires the
  screenshot that hid it: `grabToImage` renders a LATER frame, so a probe that shoots and then
  commits the span in one call files the transition's first frame as "settled".
  38ad4d94b ("fix(currency): the word \"to\" becomes its own element, and rates stop colliding").
- **A bundled package component loaded by URL has no implicit siblings - the package needs a
  qmldir naming every component, and the qmldir then governs DIRECTORY imports of the package
  too.** MediaTransportButton shipped bare and every media widget vanished with "is not a type";
  the fix's first version listed only the bare-referenced files and would have broken the discord
  popup, whose directory import had been auto-listing the whole package - the registration lint
  caught the half-listing before deploy. lint_qmldir_registration.py holds both halves.
  d3145342e ("fix(plugins): a URL-loaded package component has no implicit siblings").
- **A subclass cannot read `AbstractWidget.gridSize`: `PluginWidget` shadows it.** The base's
  `gridSize` is the 12px drag lattice; `PluginWidget` declares its own `gridSize`, the
  component-grid span (`{"cols": 2, "rows": 1}`). Code *inside* the base still resolves to the
  base property — measured, `snap(100)` is 96 there — while anything reading `rootWidget.gridSize`
  from the subclass gets the object, and a snap written against it silently applies no lattice at
  all. Nothing warns. That is why the drag lattice never leaves the file that owns it and a
  subclass declares `snapOffsetX`/`snapOffsetY` instead: the seam hands in the frame, not the
  lattice. 8a534a7da ("fix(plugins): snap a widget's drag to the lattice it is stored on").
- **Clamp a position where it is written, not only where it is read.** The widget drag is
  deliberately unclamped (the release decides), but only `applyPersistedPosition` clamped, so a
  drag that ended past a screen edge stored the overshoot and the widget was drawn somewhere
  else — permanently, silently, and read by the user as the widget moving on its own. A real
  store held `visualizer` at `x: -852` on a 5120px screen. When two sides of a store apply
  different rules to the same number, the disagreement is invisible by construction. For entries
  already on disk: an unreachable value **cannot be repaired** (the offset it absorbed depends on
  which workspace was showing and whether a sidebar was open, and it accrued over an unknown
  number of releases) and **must not be reset to a default** (that moves the widget somewhere the
  user never chose) — it is pinned to what is already on screen, once, on a settle timer, only
  where the clamp actually bites, and only after `width` has arrived. A clamp written back on
  every load is the `ConfigSpinBox` trap in [The Config system](#the-config-system-settings-page--persisted-json).
  705e9006d ("fix(plugins): stop a widget's stored position disagreeing with where it is drawn").
- **A per-plugin key can be a retired manifest option for one widget and a live setting for
  another, so migrate on what the manifest says, not on the key name.** `sizeMode` was a
  manifest *option* on weather and currency, which `__gridSize` took over; `world-clock` and
  `calendar` declare no `grid` and drive a `sizeMode` of their own from their own toggles. A
  pass keyed on the name emptied those two widgets' options and reset them - the migration's
  own failure mode aimed at the wrong widgets, found by running it against a seeded
  `plugin-state.json` rather than by reading it. It now acts only where the manifest offers
  more than one span. The marker (`migrations.migratedSizeMode`) is subject to AGENT.md's usual
  warning - it records that the pass *ran*, not that it saw the user's data - so `PluginManager`
  drives it on a settle timer rather than on the first non-empty manifest list, and the pass
  returns without marking on an empty one. See `docs/widget-grid.md`.
  db3a7d009 ("refactor(plugins): retire sizeMode in favour of the host's __gridSize").
- **What claims a press from a desktop widget's drag-to-move is the nesting, not
  `preventStealing`.** The resize grip is a `MouseArea` inside `PluginWidget`, which *is* a
  `MouseArea` (`AbstractWidget`), and a nested area takes the press - the root only ever sees what
  no child accepted. The flag reads like the load-bearing part and is not: a `MouseArea` steals a
  child's grab through its `drag` target, and `AbstractWidget` has had none since d2ebb5aeb
  ("fix(widgetCanvas): compute the drag by hand - MouseArea.drag cannot track it") computed the
  drag by hand. Measured by planting the removal and re-running the harness, not reasoned about;
  it stays because it is one `drag.target` binding away from mattering. The corollary for a *new*
  gesture on a widget: put it in a child area, and score the widget's position as well as its
  effect, because "it resized" and "it resized without walking" are different results.
  9c70ac62e ("docs(plugins): say what actually claims the grip's press").
- **The desktop-widget host is now reachable from a test.** `WidgetResizeGripRuntimeTest.qml`
  (driven by `tests/test_widget_resize_grip_runtime.py`, headless weston, in `run_tests.sh`) builds
  real `PluginWidget`s on a real `WidgetCanvas` from synthetic manifests over an inert
  `{ "type": "Item" }` node and drives them with real mouse events - the same shape as
  `WidgetInteractionRuntimeTest.qml`. A key event, unlike a mouse event, has no explicit target:
  `TestCase` sends it to the focused item of *its own* window, so a driver parented outside any
  window cannot deliver one. What no such harness can answer is the background *layer surface's*
  keyboard focus, since weston gives it no wlr-layer-shell. 2c8ccae70 ("test(widgets): drive the
  resize grip with real mouse events"). `EditModeRuntimeTest.qml` is the same shape with the
  canvas under Edit Mode's transform, and it drives every gesture in **canvas** coordinates,
  which `TestCase` maps through that transform on the way to the window: the same drive numbers
  at two scales must store the same position and cover a *different* amount of screen, and both
  halves are asserted because "the widget moved" is satisfied by a drag that reads raw scene
  deltas and lands the scale's worth short. (test(editMode): drive the desktop at the mode's own
  scale.)
- **A gesture has three ends now, not two: released, cancelled, and the release that follows a
  cancel.** `AbstractWidget.cancelDrag()` exists because Edit Mode can end mid-drag, and a
  release *commits* — clamped and written to the store — while the drag itself is deliberately
  unclamped until then, so committing an unfinished gesture stores an overshoot (705e9006d's
  defect). Three things about it do not generalise from the release path: the pre-press position
  comes back by restoring the x/y **binding** rather than by assignment, since only a commit
  writes `targetX`/`targetY`; a group drag needs its own cancel (`WidgetCanvas.widgetDragCancelled`)
  because `widgetDragEnded` commits every follower, a follower never getting a release of its
  own being the whole reason it does; and the pointer is still **grabbed**, so a release is still
  coming and `dragCancelled` has to swallow exactly that one — measured, what it would otherwise
  write is wherever the restore animation had reached. (feat(editMode): leaving mid-drag cancels
  the gesture instead of committing it.)
- **"The frost is gated on the toggle" is not "the surface is gated on the toggle."**
  `appearance.transparency.enable` removed every desktop widget's blur — `PluginWidget`'s blur
  `Repeater` reads the flag — while the widgets' panel alpha kept coming from
  `plugins.blurOpacity` and four hardcoded `0.1` literals, which do not. Turning transparency
  **off** therefore left fourteen widgets ~10% opaque over a now-**sharp** wallpaper: a worse
  result than leaving it on, while the dock and the settings window correctly went opaque. Opacity
  and blur were two settings and only one knew about the switch. The derivation now lives in
  `PluginState.effectiveBackgroundOpacity(pluginId, base)` — the only place that can see both the
  toggle and the per-plugin opt-out (`keepTranslucent`), since the generic
  `designsystem/widgets/Desktop*Widget.qml` have no `PluginWidget` root in scope and a host-side
  property could never have reached them. When adding anything that paints its own alpha, ask what
  it looks like with the toggle off, and route it through the derivation rather than repeating the
  conditional; `tests/test_widget_transparency_opacity.py` reddens on a call site that reads
  `plugins.blurOpacity` directly. The exemption gates the frost too — a widget excused from the
  opaque default but still denied its blur is exactly the hole this removed.
  **The plugins were not the only ones**, and the audit that found the other two is the point:
  `Appearance.colors.colBarBackground` thinned the (already gated) `colLayer0` by an ungated
  `bar.backgroundOpacity`, and `DropShelfPanel` painted an ungated `dropShelf.backgroundOpacity`
  — the shelf shipped 50% see-through with transparency off, in the default config. Both defaults
  (`1`, and a panel most people never open) are why nobody reported them. Neither routes through
  `PluginState`: that function resolves a *per-plugin* opt-out from a manifest seed, so a panel
  would pass an empty id forever and drag the plugin state store into an unrelated module for a
  one-line conditional. The generalising abstraction for a non-plugin surface is the one
  `Appearance.qml` already had — a transparency *amount* declared beside `backgroundTransparency`
  / `contentTransparency` that collapses to `0` when the switch is off. Keep new amounts there,
  where "is every one of them gated?" is answerable by looking.
  b259288b2 ("feat(plugins): derive desktop-widget opacity from the transparency toggle"),
  3088bbaed ("fix(plugins): route every widget panel opacity through the derivation"),
  e4f3a095e ("fix(appearance): gate the bar's own opacity on the transparency switch"),
  b47935a65 ("fix(dropShelf): gate the shelf's frost on the transparency switch").
- **N widgets each asking the image reader for the same wallpaper is N serialized decodes, not
  one.** Qt runs a single pixmap-reader thread, so per-widget image loads queue behind each other —
  which is why the desktop widgets' frost came back one widget at a time, ~0.6s apart, after
  anything that rebuilt the blur surfaces
  ([#147](https://github.com/XephyLon/immaterial-impulse/issues/147)). Note the asymmetry that
  names the cause: losing the frost was atomic because it is a property change, getting it back was
  serial because it waits on a decode. What decides whether two `Image`s share one decode is the
  whole **request**, and more of it than is obvious: url, `sourceSize`, `sourceClipRect`, *and* the
  aspect flags a `PreserveAspectCrop`/`Fit` fill mode puts in the request — an otherwise identical
  `Stretch` image of the same file is a different request and decodes again (measured; it is what
  made a correct fix look broken from a test). `cache: false` opts out of sharing entirely. So a
  per-widget `sourceClipRect`, which is the natural way to write "the slice of wallpaper behind
  this widget", is exactly what makes every widget pay for its own full-resolution decode — and it
  re-pays on every pixel of a drag, since the rect tracks the widget's position. Take the slice
  with a `ShaderEffectSource`'s `sourceRect` over a shared, unclipped, cached `Image` instead: the
  rect is free to move, and matching the request Background's own wallpaper `Image` makes means a
  surface built while that wallpaper is on screen needs no decode at all.
  33139b688 ("fix(widgets): give every desktop widget's frost one shared wallpaper decode"),
  e15b9f166 ("test(widgets): pin the desktop frost to one shared wallpaper request").
- Desktop plugin delegates are retained for every available manifest and gated through an animated
  `FadeLoader`, rather than repeating only the enabled ids. Removing a model delegate destroys it
  immediately and makes an M3 exit transition impossible; keep disabled loaders dormant until their
  fade-and-scale exit reaches zero opacity.
- **A comparison that is correct on one axis is INERT on the other, not merely wrong — and a
  layout that turns is where you meet that.** The dock now lives on any of the four edges
  (`modules/imi/dock/dock_geometry.js` derives anchors, thickness, exclusive zone, margins by
  INWARD/OUTWARD direction, reveal offsets and popup gravity from one `OPPOSITE` table; one tree
  with a `vertical` flag rather than the bar's two modules, so an orientation change reflows the
  icons instead of destroying and rebuilding them). Three things about that turn are worth not
  re-deriving:
  - **The drag reorder was `Math.abs(dragX - centre.x)` throughout.** In a column every slot
    centre has the *same* x, so the distance is zero for all of them, the "nearest" slot is
    whichever the loop reached first, and the swap test compares a number with itself: it fires
    on the press and unfires on the next event, for as long as the pointer moves at all. Nothing
    errors, the column lays out and spaces perfectly, and a screenshot is no help — the icons
    simply refuse to move past each other. `DragApps` chooses the axis once (`alongAxis`), and
    the check that can see it is `DockEdgeRuntimeTest.qml` (driven by
    `tests/test_dock_edge_runtime.py`, headless weston, in `run_tests.sh`): it drags ALONG the
    strip and requires a reorder, then ACROSS it and requires none, with the horizontal edge
    first as the control — "nothing happened" is also what a harness that stopped delivering
    events reports. It reaches the dock's *content* tree only; weston implements no
    wlr-layer-shell, so anchors, the exclusive zone, the reveal push and the compositor's
    inferred slide are all invisible to it. Its last gesture is the one that jumps two slots in
    a single event, because every other drag in the file steps one slot at a time and a run of
    adjacent swaps is indistinguishable from a move — see the reorder entry below.
    40c64996b ("test(dock): drive the drag that a move and a swap answer differently").
  - **A control sized "width from height" cannot be turned.** `DockButton` derived its width from
    its height minus the *vertical* insets, which in a column is the axis the layout owns. Both
    axes are now written out against a span, so there is no direction to get backwards, and the
    insets are named `insetInward`/`insetOutward` rather than top/bottom — a widget that decides
    which side the elevation margin lands on is correct at one edge in four, and
    `tests/test_dock_position_contract.py` fails on a margin or inset bound to a named side while
    naming `elevationMargin` or `hyprlandGapsOut`.
  - **`DockSeparator` and `DockAppButton` still reach `dockRow.padding` and
    `dockVisualBackground.margin` by dynamic scope through the dock's tree.** The ids are
    deliberately unchanged: a failed lookup there is `undefined`, then NaN geometry, then a
    relayout that never converges and a pegged core — see the Design-language note on the missing
    `import qs.modules.common`. Restructure above them and nothing warns.
  - **An item that turns must express the turn as a SIZE, never as a different set of anchors —
    Qt punishes an axis holding two anchors in two different ways and neither is loud.** Writing
    `left`/`right` for one orientation and `horizontalCenter` for the other reads as mutually
    exclusive and is not: during the turn all three are live for a moment. `QQuickAnchors` then
    **refuses the whole horizontal update and reverts the anchor it was setting**, so the item
    keeps the anchors of *both* orientations and fills its parent in both axes — measured at
    5120x1440 inside a 75x1440 layer surface, i.e. a full-height dark band with the icons spread
    over a screen's width of which a side edge shows 75px. The only log line is `Cannot specify
    left, right, and horizontalCenter anchors at the same time`, which names an item, not a
    consequence. The *pair* is worse than the triple, because Qt honours it: `right` +
    `horizontalCenter` is a legal way to state a width, so the anchor **writes** the item's width
    as `2 * (right - hcenter)` — evaluated while the surface is still the size it had before the
    compositor reconfigured it — and that write latches, because the size binding it clobbered has
    finished changing by then and never re-evaluates to overwrite it. Nothing at all is logged for
    that one: no binding loop, no warning, and QML that reads correctly. Which axis is ruined
    depends on which one the turn landed on, so it presents as intermittent and as two unrelated
    bugs. Everything in the dock now centres at every edge and takes its box from
    `DockGeometry.contentBox()`, with the reveal push as a `horizontalCenterOffset`/
    `verticalCenterOffset` times `DockGeometry.hideDirection()`; a centre offset is a number and
    cannot occupy an axis. `tests/test_dock_position_contract.py` fails on any item in the dock's
    tree binding a centre anchor together with either edge anchor of the same axis — its first run
    found four more copies of the idiom (both sets of running dots, the window-preview card, the
    context menu's card) that nobody had looked at. Note what this cost before it was found: the
    dark band is also exactly what an empty layer surface looks like under the compositor's blur,
    and two attempts went after `rules.lua` instead.
    ("Dock: the body and the icon strip stop re-anchoring on the turn"),
    ("Dock: the reveal becomes an offset, not an anchor that moves"),
    ("Dock: one axis, one anchor - checked, because it was silent").
  - **A `PopupAnchor` given a `window` and no `rect` anchors to a POINT, so all four of its
    `edges` mean the same place.** The window-preview popup names the corner it wants
    (`popupAnchorSides()` — the inward side plus the start of the long axis) and got the window's
    origin every time. That is correct at exactly two edges out of four, which is what made it
    read as a vertical-dock bug: a bottom dock asks for top-LEFT and a right dock for left-TOP,
    and both of those *are* (0, 0), while a left dock wants `(width, 0)` and a top dock
    `(0, height)` — so on those two the popup opened **on top of the dock**, covering the icons it
    belongs to (measured: a 247x1440 surface placed at x=0 against a 75x1440 dock). Every other
    popup here passes an `item` as well, which is why none of them showed it. Pass an explicit
    `rect` whenever the anchor is a window and the edges are meant to differ. Note the second,
    separate fault stacked on top of it: the card *inside* that popup wrote one coordinate as a
    binding and let an anchor write the other, and which axis is which swaps with the edge — see
    the anchor-writes-a-property note above. ("Dock: the preview popup anchors to the dock's rect,
    not to a point"), ("Dock: the preview card's own coordinates stop being half anchor").

  The same contract test carries the "one derivation" lint (the analogue of
  `lint_bar_popup_overlay_static.py`'s rule for `barEdge`): a file may read
  `Config.options.dock.edge`, but only straight into `normalizedEdge()`, and nothing may compare
  the stored value to a side. `modules/imi/bar/DocktoPanel.qml` renders the same `pinnedApps`
  inside the bar and must keep following the *bar*; that is pinned too.
  6b082ea16 ("feat(dock): the geometry module answers for the two side edges"),
  8e608cb61 ("feat(dock): the dock strip lays out along whichever edge it is on"),
  c7efc6db4 ("test(dock): the vertical edges get a contract and a real drag").
- **A drag reorders a list by MOVING the dragged item, and a swap is the same answer only for a
  step of one.** Four surfaces reorder by dragging — the bar's chip editor
  (`modules/common/widgets/LayoutSection.qml`), the dock strip (`DragApps.qml`), the bar's copy of
  that strip (`modules/imi/bar/DocktoPanel.qml`) and the Android quick toggles
  (`AndroidQuickToggleButton.qml`) — and all four had the arithmetic written out locally. The
  duplication was not the defect; the disagreement was. Two took the item out and put it back at
  the drop index, so everything between shifted one place along. Two exchanged the two entries, so
  a drag past three neighbours displaced exactly one of them and sent it back to where the drag
  began, several slots from anything the pointer touched, while the three the user had just dragged
  past did not move. Nobody saw it because an adjacent move and an adjacent swap produce the same
  list, and a drag that keeps up with the pointer steps one slot at a time — the difference only
  appears when the pointer outruns the events or crosses a wider icon.
  `modules/common/functions/layout_ops.js` is the one answer now: `move`/`moveInPlace`, `insert`,
  `remove`, and `indexAt` for the nearest-slot scan, which takes the axis from the caller because
  only the caller knows which way its slots run (a column compared on x is the inert-comparison
  case one entry up) and takes a **hole** for the dragged slot, which is still laid out where the
  drag began and would otherwise be its own nearest neighbour. Two spellings of the move, not two
  reorders: the quick toggles mutate the live `Config` array on purpose, and re-measured against a
  real `property list<var>`, a splice-out and a splice-in on the live property both take effect and
  notify — 26b625905 ("Revert \"fix(sidebar): make quick toggle edits actually notify\" and
  follow-ups"). The store stays with the call site, because where a list lives and when it is
  written back genuinely differ between the four and only the arithmetic is shared.
  `tests/lint_reorder_arithmetic.py` scopes itself by gesture rather than by name — a QML file
  declaring a `DragHandler` — which is what lets `DesktopContextMenu.qml`'s Fisher-Yates wallpaper
  shuffle keep the element-exchange idiom without an allowlist, and it fails if one of the four
  stops reaching the module rather than sweeping an empty set.
  a8d6aa4fc ("feat(layout): one module for the reorder four surfaces each worked out"),
  0bc44f475 ("fix(dock): a dragged icon moves to where it was dropped, it does not swap"),
  52da8b43e ("fix(quickToggles): a dropped toggle moves into place instead of swapping"),
  893bfc31a ("test(lint): fail on a reorder spelled out beside a DragHandler").
- **A drag can only be ANIMATED by a model that moves a delegate, and a row of delegates is not
  something a model can move one between.** The Android quick toggles are the case: the panel drew a
  `Column` of row containers, each with a plain array model, deliberately — 81379796b
  ("fix(sidebar): choose a delegate for the toggle each row entry now holds") reset the row because
  `DelegateChooser` picks a component when a delegate is *created* and never re-picks for one that
  survives, so an entry that changed identity in place kept the previous toggle's icon, name and
  action. That fix is correct and its cost is the delegate: a reorder that rebuilds every tile
  cannot animate, because there is nothing left to move. Rows repack on nearly every edit (they are
  packed by toggle size), so an entry crossing a row boundary left one row's model and landed in
  another's at an index some other toggle held, which is not a move in either.
  `modules/common/functions/quick_toggle_layout.js` answers both at once: `pack` gives every entry a
  stable id, its toggle TYPE, a row and a slot, and `syncPlan` diffs one packed list against another
  into the ops a `ListModel` applies. A reorder comes out as a `move`, so the delegate survives; an
  id is derived from the type, so the role the chooser reads can never change under a surviving row;
  and the ops the plan may emit against a live row are the PAYLOAD roles only, so no spelling in
  `StableQuickToggleModel.qml` can retype one. A row is a coordinate now, not a container — one flat
  `Item` per section, each tile placed at its own slot from the SETTLED pack (a placement keyed on
  anything the press bounce moves is b710ef731's frozen `Behavior` again, so the press growth is
  centred with a `transform` instead). The list edits the plan is simulated against are
  `layout_ops.js`'s, for the reason the entry above gives.
  **The half that had to be measured: a live `list<var>` notifies per ELEMENT written.** One
  `layout_ops.moveInPlace` on the stored toggle list — the splice-out and splice-in a drop commits —
  was observed in *nine* intermediate states, each a list with a toggle duplicated or missing, and
  each one a plan that rebuilds rows rather than moving them. So a model synced straight from the
  observer destroys most of the grid in the middle of the one gesture the delegates exist to
  survive, and the panel is correct only because the sync is deferred to the end of the turn with
  `Qt.callLater`. This was invisible until the delegates mattered: the old panel rebuilt the row on
  every notification anyway, so it paid ten rebuilds per drop and looked right. Anything else here
  that observes a `Config` array someone mutates in place has the same question to answer.
  The panel is also why the observation is a SIGNATURE rather than the array: the toggles mutate
  the live array on purpose (26b625905), so its identity never changes.
  `tests/tst_quick_toggle_layout.qml` scores the plan's ops rather than the list they produce (a
  rebuild produces exactly the right list), `tests/test_quick_toggle_model_contract.py` is the half
  CI can see, and `QuickTogglesLayoutRuntimeTest.qml` compares the delegate by identity across a
  reorder and samples its position 80ms in — a settled position is the same number whether the tile
  animated or teleported. 8930baa3c ("feat(quickToggles): the grid's packing and its keyed diff as
  arithmetic"), b1074b3c1 ("refactor(quickToggles): one flat keyed grid per section, placed by
  arithmetic"), cb24f9046 ("test(quickToggles): drive the reorder the way a drop spells it").
- **`MouseArea.drag` cannot accurately drag a target the MouseArea itself follows.** QQuickDrag
  rebases its press origin when the grab is established, silently swallowing the arming move's
  delta — a few threshold pixels under a real pointer, invisible behind the widget lattice's 12px
  snap, but measured as half the gesture under a sparse synthetic drag — and a live binding on the
  drag target (the old `Item { x: root.x }` drag proxy) re-yanks the target after every internal
  write, measured as +168 applied for a +96 eight-step gesture. Where a drag must be pixel-exact
  (the desktop widgets' group drag preserves follower offsets), compute it by hand instead: map the
  press point and each move through the (moving) item into its static parent frame — the current
  transform, press scale included, cancels out — and set the target to pressStart + delta, as
  `widgetCanvas/AbstractWidget.qml` now does. d2ebb5aeb ("fix(widgetCanvas): compute the drag by
  hand - MouseArea.drag cannot track it").
- **The two bars load the same widget files out of `modules/imi/bar/`, and each used to decide
  which file for itself.** `Config.options.bar.layouts.*` is shared and Settings > Bar offers a
  plugin's bar widget whatever the orientation, but only `BarContent.qml` ever learned the
  `plugin:` branch 2a3801a62 ("feat(plugins): support installable QML packages") added.
  `VerticalBarContent.qml`'s fallback capitalises a widget name into a file name, so
  `plugin:docker_plugin` resolved to `Plugin:docker_plugin.qml` - measured with a `qml6` probe, the
  `Loader` reaches `Loader.Error` with a null `item`, and the only evidence is one
  `No such file or directory` line per widget. That is neither a `WARN scene:` nor an `ERROR:`, so
  the configuration still loads and the bar simply draws the empty `BarGroup` stub around nothing.
  `modules/imi/bar/bar_widget_source.js` is the one mapping now; it answers with a **file name**
  and the caller prepends its own directory, because the two bars reach that directory by different
  relative paths and a `.pragma library` has no engine context to assume for `Qt.resolvedUrl`.
  `tests/test_bar_widget_parity.py` fails on either bar deciding for itself and on the two
  `getWidgetUrl` bodies differing by anything except that directory literal;
  `tests/tst_bar_widget_source.qml` pins the mapping. The orientation API a plugin gets is one
  duck-typed `property bool vertical` on the entry point's root, which the host writes - and a
  widget that declares none is rendered anyway rather than omitted, since omitting it is the same
  silent disappearance this fixed. a47462fcc ("fix(verticalBar): render plugin bar widgets instead
  of an empty stub"), 06d31aabc ("test(bar): pin the two bars to one widget-url resolution").
- **A `Process`'s `onExited` handler that ignores its `exitCode` argument will happily act on stale
  data.** `TempScreenshotProcess` writes to a deterministic path (`image-${screen.name}`), so a failed
  `grim` run used to leave the *previous* successful capture sitting there untouched - the region
  selector/screen translator would silently proceed against stale image data with no error, since
  nothing actually "failed" from QML's perspective. Always check `exitCode` in `onExited` before
  trusting the process's output exists or is fresh; `rm -f`-ing the target path before launching the
  process (see `TempScreenshotProcess.qml`) turns a silent stale-reuse into an honest empty-file
  failure instead.
- **An overlay `Item` placed on top of an interactive control (e.g. a decorative `Flickable`-based
  mask drawn over a `TextField`/`TextArea`) will silently eat the clicks meant to focus that
  control**, unless the overlay is `enabled: false`. `ConfigTextArea`'s `password: true` mode draws
  `PasswordChars` (a `Flickable`) directly over the real field to render Material-shape dots in
  place of the native glyphs; without `enabled: false` on that overlay's `Loader`, clicking the
  field just fed the click to the Flickable instead, so the field never focused and typing appeared
  to do nothing. This only surfaces where focus is obtained by clicking - `LockSurface.qml`'s
  password box used the identical overlay structure and never hit this, since it
  `forceActiveFocus()`s itself programmatically instead of depending on a click.
  That asymmetry is why the overlay is not a call site's business any more:
  `modules/common/widgets/PasswordField.qml` owns it, carries the `enabled: false`, and is what
  both of the shell's password prompts are - see the entry on it under
  [Design language](#design-language). `ConfigTextArea` keeps its own copy, because a `TextArea`
  has no `echoMode` and masks by a different mechanism entirely.
- **`Item.visible` reads back EFFECTIVE visibility, so a container that hides
  itself from its child's `visible` latches.** The sibling of the `enabled`
  trap below, and it bites the other way round: `visible` is the item's own flag
  AND its parents', so an item whose parent is hidden reports `false` no matter
  what its own binding says. A wrapper bound to `child.visible` therefore hides
  the child, then reads `false`, then can never let it back. Probed with `qml6`
  against a control row: the control followed a gate true/false/true/false while
  the mirrored one read `false` on every sample after the first hide, with no
  warning and no binding-loop message. `GroupedList` is where this landed —
  it builds one plate per declared row and sizes it from the row's
  `implicitHeight`, which never asked whether the row was drawn, so a row hidden
  with `visible: false` kept a full-height plate painting the group's background
  with nothing in it (the desktop menu grew one between Widgets and DropShelf
  for the whole life of Edit Mode; Settings > Services > Weather has the same
  hole on wttr.in). A row that comes and goes therefore declares **`rowVisible`**,
  a property of its own; a row that never disappears declares nothing and reads
  `undefined`, which takes the `?? true`. The group's outer corners follow the
  rows that are DRAWN, not the declared first and last, or a hidden plate holds
  the rounding while the row above it is square. `tst_grouped_list.qml` covers
  all of it, and the case that earns its place is "a hidden row that comes back
  is drawn again" — the one the plausible alternative fix fails.
  b949bf24a ("fix(widgets): a GroupedList row that is not drawn takes no room").
- **`enabled: false` on a `MouseArea` disables that area and nothing under it.**
  `QQuickMouseArea` declares its own `enabled` property, which shadows `Item.enabled` — so the
  usual "`enabled` cascades to the whole subtree" intuition, which is true of a plain `Item`, is
  false here. `AbstractBackgroundWidget` (a `MouseArea` via `AbstractWidget`) used `enabled:
  !clickThrough` as its entire click-through mechanism: it correctly stopped the host's own drag
  and right-click, and left every `MouseArea` a widget drew inside itself fully live, so a
  "click-through" widget still swallowed clicks aimed at the desktop behind it. The fix is a plain
  `Item` wrapper carrying the gate, with the children routed into it via a `default property alias`
  (`contentData: contentItem.data`) — anchored `fill: parent` so it takes no part in sizing and
  cannot reintroduce the `Loader` binding loop above. Both gates are needed; neither covers the
  other. Whenever the disabled thing is a `MouseArea`, `Control`, or anything else that redeclares
  `enabled`, check what you actually disabled with a probe rather than assuming the cascade.
- **The disabled dim is expressed at exactly one layer, because `opacity` composites.** The
  sibling trap to the one above: `enabled` cascading correctly is what makes it *easy* for two
  components in the same subtree to each write `opacity: enabled ? 1 : 0.4` and produce 0.16.
  `ConfigSwitch` is rooted on a `RippleButton`, which dims the whole control, and then repeated
  the binding on its icon, label, description and two of its three content slots — so every
  disabled settings row rendered at roughly a sixth opacity, and `trailingContent` (which never
  had the second binding) sat at 0.4 half a row away from `titleContent` at 0.16. Keep the dim on
  the layer that covers the whole control: it is the only one reaching a child with no dim of its
  own (`StyledSwitch`'s track), and on `RippleButton` it is the binding `ExpandablePanel`'s
  stagger is built around — the stagger animates `appear` rather than `opacity` precisely so it
  cannot destroy it. The other settings controls (`ConfigSpinBox`, `ConfigComboBox`,
  `ConfigTextArea`, `ConfigSelectionArray`) are rooted on a plain `RowLayout` and were already
  correct; `ConfigSwitch` was the only doubled one. `tests/lint_disabled_opacity.py` fails any
  `enabled`-conditioned opacity nested inside a component whose root type already dims.
  (8f83b2e16 ("fix(widgets): a disabled ConfigSwitch dims once, not twice").)
- **A QML property binding that calls a C++ invokable method (not a property read) will not
  re-evaluate when that method's underlying data changes.** `DesktopEntries.applications` takes a
  few seconds to populate after `qs` starts. `DragApps.qml`'s pinned-app launcher bound
  `deskEntry: appEntry ? DesktopEntries.heuristicLookup(appId) : null` once at delegate creation -
  since `heuristicLookup()` is a plain invokable, not a property, the binding engine can't see it
  depends on `applications`, so `deskEntry` came back `null` (evaluated before the scan finished)
  and then never updated. Any pinned app that wasn't already running at shell startup became
  permanently unlaunchable for that session - clicking it silently no-op'd via `deskEntry?.execute()`.
  `DockAppButton.qml` and `DocktoPanel.qml` had independently worked around this with their own
  `Connections { target: DesktopEntries; function onApplicationsChanged() { ... } }`, but
  `DragApps.qml` was missing the same fix - this was three copies of the same fragile pattern with
  one left unpatched. Consolidated into `modules/common/widgets/LiveDesktopEntry.qml`, a small
  non-visual `Item` that takes an `appId` and exposes a live-refreshing `entry`; all three call
  sites now use it (`deskEntry: liveDeskEntry.entry` instead of duplicating the `Connections`).
  Covered by `tests/tst_live_desktop_entry.qml` against a mock `DesktopEntries`
  (`tests/mocks/Quickshell/DesktopEntries.qml`) that can simulate `applications` populating late via
  `mockSetEntries()`. When a binding depends on the result of an invokable rather than a property,
  add an explicit `Connections` re-fetch on the relevant `*Changed` signal instead of trusting the
  binding to track it - and prefer extracting it into a reusable, testable component over
  re-inlining the same fix at each call site.
- **A cookie's lobes all share one radius, and the sibling that gives them their own takes the
  *inner* one.** `RoundedPolygon.star(sides, radius, innerRadius, rounding)` hands every lobe the
  same inner radius, so animating it makes the whole shape breathe and nothing else;
  `RoundedPolygon.starPerLobe()` takes one radius per lobe instead. `star()`'s signature is left
  alone deliberately - `MaterialCookie` and the whole Material shape catalogue in
  `material-shapes.js` are built on it. Two non-obvious things about the array. It is the **inner**
  radius that varies because the outer vertices are what set the shape's bounds: move those and
  `normalized()` (or any other refit) rescales the entire cookie every frame, so a lobe pushing out
  shrinks the other eleven instead of standing out. And the scalar fallback is chosen on
  `typeof === "number"`, **not** `Array.isArray`, because a QML `list<real>` arrives in JS as a
  sequence object for which `Array.isArray` is `false` - taking the scalar branch on one multiplies
  a radius by an object and feeds NaN vertices into geometry QtQuick's relayout never converges on.
  be9a07c84 ("feat(shapes): a star whose lobes can each have their own inner radius").
- **`ShapeCanvas` is for a shape that changes occasionally, not one regenerated per frame.** It
  builds a `Morph` and starts a 350ms transition on *every* `roundedPolygon` change - measured at
  ~1.3ms per `Morph` for a 12-lobe cookie, on top of ~0.6ms to build the polygon itself - so a
  per-frame shape pays feature-matching it never uses and never arrives at the shape it is morphing
  to. Walk the polygon's `cubics` onto a plain `Canvas` instead, as `VisualizerCookie` does.
  Regenerating the geometry itself is affordable and needs no fixed-rate-plus-interpolation
  fallback: 0.77ms per cookie per frame at 240px, and four animating at once still held 62fps
  offscreen. f6a7e251e ("feat(designsystem): VisualizerCookie, a cookie driven by one level per
  lobe").
- **`CavaService` has had a producer since ce41c4f9c, and `GlobalStates.visualizerPoints` is
  gone.** This entry used to say the opposite and to send a new consumer to `visualizerPoints`,
  which by then had been removed - so the advice named a property that does not exist. Claim the
  bands with a `CavaRef` and read `CavaService.values`; the reasoning behind the one-source rule,
  and the failure that produced it, are under
  [State propagation is reactive](#state-propagation-is-reactive-or-it-is-a-bug-waiting).
  ce41c4f9c ("feat(cava): give CavaService the producer it always implied").
- **A `Canvas`'s `setLineDash` is measured in line widths, not in path length.** HTML's is in
  path-length units; QML's hands the array to `QPen::setDashPattern`, which is specified in
  multiples of the pen width - so a pattern computed honestly from a path's arc length comes out
  wrong by a factor of the line width. Watch the shape of the failure, because it does not look
  like one: both the "on" and the "off" run shrink by the same factor, so the *period* shrinks
  with them and the pattern repeats. A 25% progress ring stroked around a cookie drew as thirteen
  evenly spaced dashes all the way round, growing together as progress rose - which reads as a
  deliberate dashed border. `shapes/path-length.js` measures the outline (sampled per cubic, paid
  once per geometry change) and `dashInPenWidths` does the conversion, named rather than left as a
  division at the call site. Found by rendering the ring offscreen with `qml6` and looking at the
  PNG: nothing about a `Canvas` is reachable from `qmltestrunner`, and the software scene graph
  the runtime harnesses use draws none of it either.
  08341739f ("fix(shapes): Qt measures a dash pattern in line widths, not in path length").
- **A shape that must carry two moving things on one edge should carry one.** The media widget's
  2x1 strokes playback progress around its play button's own cookie outline, and its cookie is
  deliberately the *static* `MaterialCookie` shape rather than the audio-reactive
  `VisualizerCookie` the 2x2 uses: an outline that ripples while also filling up is two motions on
  one edge and neither is readable. Draw the body and the ring as two concentric passes over the
  same outline (the body inside the ring) rather than as one stroked shape, or the stroke reads as
  a line laid over the button's edge instead of as its border. And rotate the path so its first
  vertex sits at twelve o'clock: the dash starts where the path starts, which is wherever that
  vertex happens to be, and a twelve-lobed cookie is symmetric every 30 degrees so nothing about
  the shape reads as rotated. 8c211b3d8 ("feat(media): draw the 2x1 as three controls whose centre
  carries the seek bar").
- **A square design copied into a non-square tile keeps its own square frame; anchoring its parts
  to the tile's corners quietly breaks the relationship being copied.** The media widget's 2x2 is
  the cookie clock's shape - `clock/CookieClock.qml` is a square `implicitSize: 230` and
  `dateIndicator/DateIndicator.qml` anchors two `dateSquareSize: 64` badges to opposite corners of
  it - with next and previous where the day and month are. What makes a badge read as *fastened*
  to the cookie is that it bites into the edge: its centre sits on the diagonal at 1.02 outer
  radii, so ~13% of the frame overlaps. The 2x2 span is 276x228, and anchoring the badges to the
  tile's corners instead moves them along a shallower bearing and cuts that bite from 26px to 8px
  - the badge grazes the cookie and the tile reads as three unrelated objects. Centre a square
  frame in the tile and hang everything off *that*; the leftover width becomes symmetric margin.
  The same arithmetic is why the title and artist left: a text block under the cookie is paid for
  out of the cookie's diameter, so keeping it shrinks the frame and pushes the badges off the edge
  anyway. `cookie_layout.js` is the whole of it, extracted because nothing else about that layout
  is reachable from a test - and `badgeOverlap` returns the bite in pixels rather than a boolean,
  so a changed ratio reads as a number instead of as "still positive".
  562cdf815 ("feat(media): rebuild the 2x2 as the cookie clock with next and previous").

**Wallpaper parallax is one oversized viewport, not a per-layer effect.**
`Background.qml` draws every wallpaper layer inside `parallaxViewport`, an item sized to
`screen * parallax.workspaceZoom` whose `x`/`y` are the effect; the maths lives in
`modules/common/functions/parallax.js` so it can be tested without a compositor. Keep new wallpaper
layers **inside** that viewport and `anchors.fill: parent` - that is the only reason Wallpaper
Engine parallaxes at all, since the WE surface, the frozen switch stills and the peel shaders are
all sized to the same item and therefore pan together. Anything that must stay screen-sized (the
widget canvas, the desktop right-click area) is a *sibling* of the viewport and needs its own copy
of the `suppressContents` fullscreen gate, which the viewport carries for its own children.
Sizing is deliberately screen-derived rather than wallpaper-derived: a live WE project reports no
intrinsic size, and `PreserveAspectCrop` already covers a still, so one rule serves both.
(feat(background): revive wallpaper parallax, for stills and Wallpaper Engine.)

**Edit Mode shrinks that viewport, and it does it with a TRANSFORM — never with
x/y/width/height.** `GlobalStates.editMode` scales and insets three of the
background surface's siblings at once (`parallaxViewport`, `widgetCanvas`, the
clock depth layer), all from one `bgRoot.editMatrix`, so the desktop becomes an
object on the screen over its own wallpaper blurred. The transform is what makes
the whole thing cost nothing: `scale` leaves `x`, `y`, `width` and `height`
alone, so every clamp range, every position in `plugin-state.json` and the
hand-computed drag are untouched — the drag maps the pointer through the moving
widget into the canvas frame and the transform cancels itself out, which
`EditModeRuntimeTest.qml` drives at two scales rather than assuming. Writing the
inset into the containers' `x`/`y` instead would fold a second meaning into the
four properties the parallax animates, the frost samples by and every clamp
measures against, which is b710ef731's defect in a new place. Three things the
mode is built out of are worth not re-deriving:
- **The SIZE is derived and the POSITION is dead centre, and keeping those two
  apart is the whole of it** (`modules/common/functions/edit_mode.js`). The
  desktop shrinks by at least the drawer's declared width plus a margin, so the
  drawer opens into space that already exists; it takes the drawer's WIDTH and
  has no input for whether the drawer is open — a viewport that changed size
  mid-edit would rescale every widget under the cursor and hand every `Behavior`
  carrying the box a moving target. But the reservation is spent when the drawer
  arrives, not held back from the start: a geometry that put it into the resting
  `x` made the entry a slide as well as a shrink, symmetric on no frame
  including the last, and no choice of pre-drawer inset repairs that because the
  asymmetry is in the shape of the animation. A centred geometry's offset is
  linear in `(1 - scale)`, so `atProgress` multiplying it by the same `t` as the
  scale is exactly the centring offset of the intermediate scale — the margins
  are equal in pairs on every frame, which `tst_edit_mode.qml` asserts as
  arithmetic and `test_edit_mode_chrome.py` measures off the drawn desktop at
  half progress. **And the scale has a ceiling** (`MAX_SCALE`): the derivation
  is right while the drawer is a meaningful fraction of the width and stops
  being one as the screen widens — 380px of drawer on 5120px left the desktop at
  92%, which is the mode's whole signal spent on a border. A ceiling cannot
  break the derivation, because shrinking further only makes the drawer's slot
  larger.
- **...and "dead centre" means dead centre of what the bar and the dock leave,
  because they stay where they are.** Editing them in place is spec §12 stage 8;
  until then they keep their edges at full size, and a mode that ignores them
  draws its chrome on top of them — which is what shipped. `viewportGeometry`
  takes four INSETS and a CHROME THICKNESS on top of the drawer's width, and the
  two answer different questions: the insets say which part of the screen the
  mode may use, and the chrome thickness makes the band above and below the card
  `margin + toolbarHeight + margin`, so the toolbar centred in that band has a
  whole margin at each end by construction rather than by whatever the ceiling
  left over. (It left 100.8px at 5120x1440 for a 56px toolbar, which starts
  22.4px into a screen whose bar occupies the first 68.) Passing neither term
  reproduces the old geometry property for property, which
  `tst_edit_mode.qml` pins.

  Three things about it are worth not re-deriving. **The insets have exactly one
  derivation** (`modules/imi/editMode/EditModeInsets.qml`): everything else in
  the mode is re-derived on both surfaces because every input is an `Appearance`
  token and the same screen, and these are not — they come from
  `Config.options.bar.*`, `Config.options.dock.*` and `dock_geometry.js`, so a
  second file working them out is a second answer to where the dock is, which is
  what `test_dock_position_contract.py` already exists to prevent for the dock's
  own tree. **What is reserved is each panel's LAYER SURFACE, not its painted
  body** — the bar's carries the screen-corner decorators below its body and the
  dock's carries its elevation margin, both take clicks there, and the surface
  extent is the number `hyprctl layers` reports, so the compositor is a check on
  it rather than an unrelated measurement (`quickshell:bar` at y=5 h=63 and
  `quickshell:dock` 75 tall, which is `Appearance.sizes.barSurfaceThickness` and
  `DockGeometry.thickness`). And **the reservation is a function of
  CONFIGURATION only** — never of auto-hide, a hover reveal, `GlobalStates.barOpen`,
  or a fullscreen window dropping the dock's exclusive zone. All four move while
  the mode is on, and a viewport that changes size mid-edit is b710ef731's moving
  target: it is the same decision the module already makes about the drawer.

  What this costs is the one symmetry an off-centre destination cannot keep: the
  four margins are no longer equal in pairs *mid-flight*. What replaced it in
  the checks is stronger and is what the eye follows — every corner still
  travels in a straight line, because both terms of each corner's position are
  linear in `t`. At rest the margins are equal in pairs against the USABLE AREA,
  and on the machine this was measured on that centre is 3.5px from the screen's
  own on a 1440-tall panel. b23c3f0f3 ("feat(editMode): shrink the desktop
  inside what the bar and the dock leave"), 07940391a ("feat(appearance): name
  what a bar's layer surface occupies").
- **The blurred backdrop cannot be the lock's `blurLoader` with a second gate**,
  which is what the spec asked for: that loader is a *child* of
  `parallaxViewport`, so it takes the edit transform and shrinks along with the
  desktop it is meant to sit behind. It is a sibling `Loader` sharing one
  `WallpaperBlurBackdrop` component with the lock's, and it works because a
  `ShaderEffectSource` renders its source item in that item's OWN coordinates —
  a transformed wallpaper still yields an untransformed texture.
- **That backdrop is drawn ABOVE the wallpaper and BELOW the widget canvas, cut
  out to a rounded rect, and that is the only cheap way to round the desktop's
  corner** (`modules/imi/background/EditModeCard.qml`, the `editChrome` Loader
  at `z: 1`). QML has no rounded clip and the desktop is three separately
  transformed siblings, so no property on any of them rounds a corner, and
  wrapping all three in one masked layer pushes the wallpaper through an effect
  for every frame of the shrink — the cost the transform was chosen to avoid.
  Covering the corner with what is behind it is identical to drawing the backdrop
  behind everywhere except the four corners, and it gives the drop shadow
  somewhere honest to live: inside the same cut, over the backdrop, so only the
  half outside the card survives and its interior never darkens the desktop it is
  lifting.

  **A cover over EVERYTHING covers everything, which is what the `z: 1` is for.**
  It shipped at `z: 4` and cut the widgets too: the desktop scales about its own
  centre, so the canvas's edge lands exactly on the card's edge and a widget
  parked against a screen edge is flush with the rounding — at a corner the arc
  comes in on both axes and takes a bite. Measured at 5120x1440, 20px along each
  edge and 10px on the diagonal of a block pinned there, and this machine's own
  `plugin-state.json` keeps `visualizer` at 0,1200 on a 1440-tall screen. The
  trade is deliberate and is the whole of the fix: a widget in the corner now
  OVERHANGS the rounding, drawn whole over the blurred backdrop. It says "this
  widget is at the edge of your desktop", where the alternative was moving
  widgets the user placed. `test_edit_mode_chrome.py` asks the question from both
  sides — a marker in the wallpaper viewport that has to be cut, a block on the
  canvas that has to survive — because a single check either way passes on both
  arrangements. Note the second copy of the arrangement: `EditModeLookProbe.qml`
  re-declares the four siblings, because weston implements no layer shell, and it
  scored one render of that fix against its own stale `z: 4`. The contract pins
  the two z values against each other now.

  **The card's edge is a bevel, not a line.** A 1px `colLayer0Border` outline is
  right for a panel on a surface these tokens were derived from and is a drawn
  line over a WALLPAPER: walked round the perimeter on this library's darkest
  picture, the worst point departed from the backdrop beside it by 2.8/255. Three
  tones fix it, and it is three because no single one survives every wallpaper —
  a shade band just outside (which carries a bright picture), a specular on the
  edge that is brightest along the top and fades to a weak bounce at the bottom
  (which carries a dark one), and a faint highlight just inside so the specular
  is the outer face of something. Re-measured: worst-on-perimeter 24.0/255 over
  the darkest wallpaper and 38.2/255 over the brightest.

  **It shipped as a bevel around a LINE, though, and that is what "the glassy
  border effect feels off" turned out to be.** The 1px outline stayed, drawn
  between the specular outside the card and the highlight inside it, so walking
  inward the profile went shade, crest, *dark line*, highlight, desktop — a
  NOTCH of up to 70/255 below the lower of the two bright bands either side of
  it, measured on the real desktop at 5120x1440. A bevel falls off its crest
  into the surface; this one fell, rose and fell, so the eye reads the dark line
  as the card's edge and the bright band as a piping outside it, which at the
  top-left corner looks exactly like chrome trim with a seam in it. The outline
  is gone, and `docs/M3_GUIDELINES.md` §1 is what licenses that rather than what
  it is traded against: "visible borders are not required for every surface",
  and the job the guideline gives an outline — defining edges against complex
  backgrounds — is the job this bevel exists to do, *because* the outline could
  not do it over a wallpaper. One edge treatment, not two stacked.

  **And "brightest along the top" was a stroke, because the gradient ran over
  the bounding box.** The run from the top's value to the flank's was half the
  card, so the whole 4403px top edge sat at one strength and both top corners
  with it — 113/255 median along the top against 42 down the left flank. The
  roll-off belongs to the CORNER ARC, which is precisely the run over which the
  outline's normal turns from facing up to facing sideways, and it is expressed
  as `cardRadius / card.height` rather than as a stop someone picked, so a
  change to the corner moves the light with it. Re-measured after both: the
  notch is 0.0 median / 5.3 worst (from 6.8 / 50.1) and the crest's spread
  narrows from 0-125 to 0-109 with the top down at 89 and the flanks and bottom
  up. The weakest point on the perimeter is 1.8/255 against 6.4 before — both
  are "no edge here", over the brightest part of the blurred backdrop, and the
  cause is structural: the shade band is drawn UNDER the specular, so the crest
  composites on a darkened base and cannot clear a bright backdrop by much at
  the bottom. Separating them costs a second mask, which is the cost this
  component is arranged to avoid. 1df616e62 ("fix(editMode): the card's edge
  stops having a seam drawn through it").

  **And then all three tones went, because the sum of three defensible tones is
  a border.** Every measurement above scores one tone at a time, and the
  complaint that followed was about the whole card: *"edit mode's layout having
  this thick border is what looked ugly for me. I want it to look glassy without
  it having this thick border."* Walked inward across the left flank on the real
  desktop — backdrop 28, shade 17, 17, specular 77, 77, highlight 128, desktop
  105. Five drawn pixels of dark-then-bright piping at one strength the whole way
  round a 3872px card, which is what a border *is*, and no per-tone number says
  so. It is now ONE tone, `borderWidth.standard` wide: 0.44 along the top, 0.07
  along the flank, 0.13 at the bottom.

  Three things about why each tone could go, and they are the reusable part:

  - **The shade band was a hard copy of the shadow.** It existed to carry the
    edge over a bright picture, and `StyledRectangularShadow` is already a
    darkening outside the card, from the same lamp, soft where the band was a
    hard 4px lip. Two darkenings on one edge.
  - **The inner highlight was 1df616e62's outline in the other colour.**
    Anything drawn INSIDE the card cannot ride `surround`'s mask — that mask
    removes exactly the card — so it is a uniform border by construction, at one
    strength round the whole perimeter, and it composites over the DESKTOP rather
    than over the backdrop. Measured, it was the brightest thing on the boundary
    on three edges out of four: +41 levels over a wallpaper at 105 on the flank,
    +35 over one at 36 along the top. A line brighter than the specular it is
    supposedly supporting is the edge.
  - **The catch and the shadow divide the perimeter rather than doubling up**,
    and that falls out of the shadow's own `offset: (0, 1)` — weakest directly
    above the card, strongest below, which is the opposite ordering to the catch.
    Measured over the brightest wallpaper, the backdrop falls 172 → 158 above the
    card and 237 → 146 below it. The boundary is a bright line where the shade is
    thin and a pool of shade where the line is not.

  What generalises past the card: **"is this glass or a border" is a question
  about the whole perimeter, and non-uniformity is a RATIO rather than a
  direction.** The edge that read as a border was already non-uniform — 0.46
  along the top against 0.26 down the flank — and 0.26 of white on a 2px band all
  the way round is a stroke a shade fainter, not a catch. `test_edit_mode_chrome.py`
  scores three things now: a catch along the top (median 56.5/255), flanks and a
  bottom that stay inside the range the backdrop and the desktop already span
  (worst 0.0, against 31.0 and 37.8 before), and a drawn band at most two pixels
  wide (1, against 5). The first of those is the one that had been missing:
  **every edge check in that file passed with the edge removed entirely**, because
  the notch check reads the profile from its crest inward and a bare ramp has no
  notch in it. `test_edit_mode_contract.py` holds the source half — no
  `border.width` anywhere in the file (the only way to draw a line the mask does
  not cut, and what both retired lines were written as), no `colGlassShade`, the
  width at `borderWidth.standard`, and the flank at most a quarter of the top.
  ("fix(editMode): the card's edge becomes a catch, not a rim").

  Two things generalise.
  The one outer tone is a plain `Rectangle` declared INSIDE `surround`, whose
  layer is already masked to the complement of the card — so the mask cuts it
  back to the band outside the card by itself and the shading is the Rectangle's
  own gradient, which is why the whole treatment adds no layer, no mask and no
  effect (measured under headless weston's software renderer, 14.91s ± 0.22 of
  user CPU against 14.68s ± 0.32, indistinguishable on a 3-4% spread).
  And its colour is `Appearance.colors.colGlassSpecular`, the one colour in that
  file deliberately NOT derived from the wallpaper: every other colour there is
  generated from the picture on screen, so an edge drawn in one of them is
  guaranteed to be a colour the picture already contains. Same reasoning as the
  depth picker's hardcoded contour. Its `colGlassShade` sibling went with the
  shade band — nothing else had ever read it, and `lint_appearance_tokens.py`
  fails on a token that is read and not declared, never on one declared and read
  by nobody, so a dead token there rots silently. ("refactor(appearance): a glass
  edge is one tone, so colGlassShade goes").

  Two things measured rather than argued while building the original. The shadow
  stays `StyledRectangularShadow` at the magnitude the component defines —
  raising `blur` from 9 to 40 on a 4403px card spreads the same darkness over
  four times the distance and the two renders are indistinguishable, because the
  edge contrast comes from `colShadow`'s alpha and most of a `RectangularShadow`
  sits under its target, which the cut removes. And the chrome stands down
  through **two** gates, the Loader's `active` and its `opacity`: either alone
  hides it, so a frame comparison passes on a tree with one of them deleted,
  which is why `test_edit_mode_contract.py` names both.
- **The per-widget frost is stood down for the mode, not aligned to it**
  (`PluginWidget.frostSuspended`, the generalisation of what used to be
  `lockCoversFrost`). Measured on a live desktop with a Wallpaper Engine scene:
  cards that are visibly frosted at rest render as flat tinted panels under the
  transform, because the frost's sample rect is computed from three frames the
  transform does not move together. Suspending it is the difference between a
  deliberate look and a broken one nothing logs — and it is why proxy
  rectangles, the spec's fallback, are not needed. It is also the one thing the
  mode changes in a single frame rather than easing, deliberately: a frost is a
  sample rect that stops being valid the instant the transform starts, so fading
  it out fades out a picture that is wrong for the whole fade.
- **The lattice is a substrate, and it says so** (`WidgetCanvas.qml`'s `lattice`
  item at `z: -1`). The desktop widgets arrive as EXTERNAL children of the
  canvas — `Background.qml`'s `Repeater` over the plugin manifests — so nothing
  in `WidgetCanvas.qml` decides whether they are drawn over the grid; the order
  is a consequence of when each `Repeater`'s model filled. A widget whose panel
  is translucent, which every desktop widget is and which this mode makes more
  so by standing the frost down, then has a crisp full-strength line running
  across it, and a line is a foreground cue whatever is really in front.
- **...and it belongs to the GESTURE, in the mode as well as out of it.** The
  mode forced it on for the whole mode on the spec's §4.1 discoverability
  argument, and that argument predates the mode having any chrome: the toolbar
  and the tab bar say it is on now, and a mode that opens on a screen of graph
  paper hides the desktop you came to look at. What the mode overrides is the
  config SWITCH (`background.showGrid`, "draw the grid while I drag"), so
  `gridVisible` is `showGrid && (editMode || the switch)` — the gesture is a
  required conjunct and a top-level `||` is what the contract forbids. The
  trigger is the distinction `AbstractWidget` already draws and never a second
  one: `showGrid` is written from `onDraggingChanged`, which follows
  `dragActive`, which `onPositionChanged` raises only past `drag.threshold`.
  That matters because every one of a widget's own controls presses without
  travelling — the resize grip, the right-click, a click that selects — and a
  lattice flashing up under each of them is worse than one that never goes away.
  Two consequences: the fade is `elementMoveFaster` rather than `elementMoveFast`
  because its reference is now the pointer rather than the 500ms shrink, and
  `widgetRemoved` takes the lattice down, because a widget destroyed mid-drag is
  the one end of a gesture that never reaches `onDraggingChanged`. The pixel half
  is three frames (at rest, mid-drag, and a whole-frame comparison of after
  against before), because `gridVisible` goes false the instant a drag ends while
  the fade still has 150ms to run — a lattice that never finished leaving reports
  the same false.
- **The whole mode animates on ONE scalar, and it is `GlobalStates.editProgress`
  rather than a property of the surface that uses it.** The desktop's transform
  and the chrome that frames it are on two different layer surfaces, in two
  different scene graphs, and both build their geometry out of the progress —
  so a second `Behavior on (editMode ? 1 : 0)` on the other surface is two
  numbers that have to agree, agreeing at rest (the only place anyone looks)
  and disagreeing exactly on the frames where the chrome frames a rectangle the
  desktop is not at. `test_edit_mode_contract.py` sweeps the tree for a second
  `Behavior on editProgress` rather than naming files, because the second one is
  written by whoever adds the next surface.
- **The chrome is a SECOND surface, and the viewport deliberately does not move
  onto it** (`modules/imi/editMode/`). The desktop stays on `quickshell:background`
  because that is where the wallpaper and the `WidgetCanvas` already are and
  where a `ShaderEffectSource` can still reach the live Wallpaper Engine layer —
  but that surface is on `WlrLayer.Bottom`, and measured live the layers come out
  background / dock+bar / screenCorners+barPopup, so chrome drawn there renders
  under a bar the mode leaves at full size. Three things a screen-sized surface
  has to get right, all three of which this repo has already paid for once:
  **input** (the mask is the toolbar's and the tab bar's rects and nothing else,
  or the desktop underneath — the thing being edited — stops taking clicks; the
  surface also does not exist while the mode is off, which is the state nobody
  looks at); **blur** (a minted namespace absent from `rules.lua` falls through
  the catch-all `ignore_alpha = 0.05`, under which a screen-sized surface of
  transparent pixels asks the compositor to blur the entire screen —
  `quickshell:editMode` is listed at `ignore_alpha = 1` because its two toolbar
  bodies are opaque `m3surfaceContainer`, the same treatment
  `quickshell:recordingRegion` and `quickshell:overlay` carry, and reusing
  `quickshell:popup` is the trap `BarPopupOverlay.qml:53-69` records); and
  **keyboard** (`WlrKeyboardFocus.None`, or a surface on `Overlay` sits in front
  of the background and swallows the Escape the exit ladder is answered on).
- **The chrome's placement IS the shrink's arithmetic, which is why it carries no
  motion of its own.** Both pieces sit between two rectangles from
  `edit_mode.js` — `cardRect`, the desktop's own, and `areaRect`, the screen
  minus what the bar and the dock occupy — for the reason `ClockDepthCutout` is
  one component. Placed against the SURFACE's own edges instead, which is how
  stage 4 shipped, the chrome clears the card and lands on whatever is on that
  edge; `areaRect` is what makes clearing the two panels a property of the
  arithmetic rather than a literal tuned against `Appearance.sizes.barHeight`.
  Both are functions of the same progress, and `areaRect` closes in from the
  whole screen rather than being fixed at the usable area — so at progress 0 the
  two rectangles coincide, both bands have zero height, and both pieces are
  parked half off screen and arrive *with* the desktop rather than sliding in
  from wherever the bar happens to end. A `Behavior` on either would be a target
  that moves every frame, which restarts every frame and never ticks
  (b710ef731). Note also what the pixel probe adds over the geometry checks and
  what it does not: a chrome item left `visible: false` reports its box, passes
  every geometry assertion, and paints nothing, so the probe measures the drawn
  extent — while re-asserting "the chrome is outside the card" in the pixel half
  would read the harness's own numbers back and agree with itself. The probe
  stands two opaque bands on the reserved edges now, UNDER the chrome, because
  the class no rect assertion can reach is chrome whose geometry is right and
  whose shadow or content overhangs into one: planted as a decoration 40px above
  the toolbar, that is the only check in either half that reddens.
  620a480de ("test(editMode): score the chrome against the panels, and the edge
  as a bevel").
- **The drawer spends the reservation, and the ONLY term of the transform its
  open state reaches is the desktop's `x`.** `edit_mode.js`'s `drawerTravel` is
  what the centred desktop's free side cannot absorb of the drawer-plus-margin
  slot (zero on screens where the scale ceiling left more room than the slot
  needs), and `atProgress` takes it as a shift applied to `x` alone — the size
  takes the drawer's WIDTH whether or not it is open, so opening it translates
  the desktop and can never resize it (spec §1.3; a resize mid-edit is
  b710ef731's moving target under every widget at once). The shift rides the
  same `t` as the scale, so the exit lands on the identity even while both
  scalars are mid-flight. Those scalars are `GlobalStates.editDrawerOpen` /
  `editDrawerProgress`, beside the mode's own pair for the same two-scene-graphs
  reason, and the one-scalar sweep in `test_edit_mode_contract.py` refuses a
  second `Behavior` on either. The drawer itself (`EditModeDrawer.qml`) is
  chrome: `drawerRect` pins its right edge to the usable area's and animates its
  WIDTH, because the surface's input mask tracks exactly x/y/width/height — a
  closed drawer is a zero-width rect whose mask region is empty, which is what
  lets it sit in `quickshell:editMode`'s mask as a third region without a
  permanently-reachable full-height rect eating clicks on whatever panel lives
  on that edge. Its rows are deliberately `MouseArea`s, not buttons: a drag out
  of the clipped panel needs the implicit grab of the press to keep delivering
  events after the pointer leaves the reveal, and the contract's no-MouseArea
  sweep names the drawer as the one exception. The drawer writes no store —
  both gestures are signals, and `EditModeChromeSurface` makes every write: a
  drop maps screen→canvas through `canvasPointFromScreen` (the inverse composed
  out of the same `atProgress` the desktop is drawn with, so the two directions
  cannot drift), is centred on the span the widget will come up at, snapped and
  clamped by `dropPosition`, and the position is written BEFORE the enable — a
  newly enabled plugin mounts at whatever the store holds, and spec §8.3 places
  an added widget the moment it is added rather than inventing an unplaced
  state. (feat(editMode): the drawer's travel, rectangle and drop point as
  arithmetic; feat(editMode): the drawer, fed by the plugin catalogue, and
  add-at-pointer.)
- **The drawer's reveal is the one place a clamp was a defect, and its
  contents are the one place this tree had no cascade.** Two separate
  findings, both measured through `EditModeMotionProbe.qml` (the mode has
  no IPC handler, so nothing outside the shell can drive it).
  `GlobalStates.editDrawerProgress` runs on `elementMove`, whose
  `expressiveDefaultSpatial` curve leaves the unit box - it peaks at
  1.0139 at 280ms and only comes back inside 1 at the end of its 500ms.
  The desktop's own travel is that scalar times `drawerTravel`,
  unclamped, so it overshoots and settles; `drawerRect` clamped the same
  scalar with `Math.min(1, ...)`, so the panel arrived at 226ms and then
  stood perfectly still for the remaining 271ms - 55% of one gesture with
  its two halves running different motions, and nothing in the source
  shows it. The floor stays, because the same curve run backwards
  undershoots to -0.0139 and a negative width is a rect the input mask
  cannot build. **A `Math.min` on a scalar animated by an overshooting
  tier is a freeze, not a guard** - ask what the tier's curve does past 1
  before clamping one.
  The second finding is that the duration was never the complaint: the
  reveal's travel is 96% done at 128ms and 100% at 226ms, so 500ms is a
  226ms reveal plus a settle. What was missing is that everything inside
  the panel arrived with it, which is
  `docs/p3drovfx-motion-measured-2026-08-22.md` §4.2's finding about
  adoption. The column's members now arrive individually, at their final
  positions, on the three properties §3 measured - opacity, a scale, and
  a small rise - all driven by one `appear` scalar so they cannot land on
  different schedules. The wave itself is a `StaggerWave` declared beside
  the column it walks, so the ranking, the clamp, the scaled step and the
  cancellation are the shared runner's and this file decides only WHEN.
  Three things about doing that are not obvious.
  **This is the one adopter whose container has a progress to gate on**,
  and it therefore carries NO `leadIn`. Every other container's motion is
  something QML has no scalar for - a settings page's cross-fade, a layer
  surface the compositor slides - so a fixed head start is the best
  available guess at "the container is there now"; the drawer's reveal IS
  `GlobalStates.editDrawerProgress`, so
  `Appearance.animation.contentsArrived` asks the real question and the
  wave is simply not started until it answers. A lead-in as well would be
  two waits in front of one wave, only one of them answerable.
  **Ranking by VISIBLE position matters more here than anywhere else that
  staggers**, because only one of the four sections is drawn at a time -
  most of the column is hidden on any given open, and an unranked wave
  would spend most of its clamped slots on nothing while the one list the
  user is looking at arrived last. Measured through the probe, the
  Widgets section's four members and the Lock section's six land on the
  same frame ladder for the ranks they share, which is the check that the
  ranks are visible positions rather than indices in `children`.
  **Arming and running are two events** - the first version reset the
  members at the gate, so they were drawn at full strength through the
  whole run up to it and then blinked out to cascade back in; the park
  hangs off the intent flag and the wave off the container's progress.
  That parked state is `StaggerWave.park()`, shared with the runner's own
  wait-for-an-unmapped-container branch rather than spelled twice.
  A correction worth keeping, because it was written down before it was
  measured: the lock section's two re-link rows are **not** left out of
  the wave. They are `RippleButton`s, and a `RippleButton` declares
  `appear` itself and folds it into its own opacity and a 6px rise - so
  they ride the wave through exactly the property the runner writes, one
  and two ranks behind the list above them. What they must not do is take
  the drawer's own three-channel dressing: `scale` is the interaction
  model's and that same opacity binding carries the disabled dim, so a
  second writer of either REPLACES the control's binding rather than
  composing with it, which is what `lint_interaction_motion_double.py`
  and `lint_disabled_opacity.py` exist to fail on. The earlier wording
  ("the one member that takes no entrance") was true of the drawer's
  dressing and false of the wave, and nothing distinguished the two until
  the probe was pointed at the section those rows are in.
  (fix(editMode): the drawer's reveal rides the curve the desktop rides;
  feat(editMode): the drawer arrives as a surface and then fills;
  test(editMode): a probe that samples the drawer's motion per frame;
  test(editMode): point the motion probe at the section the rows moved to.)
- **The drawer's drag has two directions and ONE rectangle, and the two halves
  live in different windows.** A row dragged out of the drawer lands on the
  desktop; a widget dragged back over the drawer and let go there is REMOVED —
  and a release back over the drawer from the *outward* gesture is still an
  abandon, which is the same rectangle answering a third question.
  `edit_mode.js`'s `pointInDrawerReveal` is the one predicate all three ask; a
  closed drawer needs no "is it open" term, because `drawerRect` animates the
  WIDTH and an empty rect is the same answer. Four things about wiring it up:
  - **The rect is PUBLISHED, not re-derived on the desktop's side.** Everything
    else in the mode is re-derived on both surfaces (see the chrome-surface
    entry above), but `test_the_drawer_reaches_the_desktops_x_and_nothing_else`
    counts `GlobalStates.editDrawerProgress` in `Background.qml` and admits
    exactly one occurrence — the shift — so a second derivation there is a
    contract failure rather than a style choice, and rightly: the check exists
    because the drawer's *state* reaching the geometry rescales every widget
    mid-drag. `EditModeChromeSurface` writes its own `chrome.drawer` into
    `GlobalStates.editDrawerReveals` keyed by screen, the `clockDepthViewports`
    shape, and drops the entry on destruction so the map is always "the screens
    whose drawer exists".
  - **A subclass cannot get in front of a base class's `onReleased`.** Signal
    handlers declared at two levels of one component BOTH run, base first —
    probed with `qml6` rather than reasoned about (`base;mid;leaf;` for three
    levels, with the mid level's call to an overridden function reaching the
    leaf's version). So a second `onReleased` on `PluginWidget` arrives *after*
    `AbstractBackgroundWidget` has already committed the placement. The
    decision is therefore an overridable predicate the one release handler
    asks — `releaseRemovesWidget(mouseX, mouseY)`, false in the base — and the
    subclass overriding it is what the base's handler resolves.
  - **...and the same ordering makes a subclass's `mouse.x/y` the WRONG
    coordinates in `onPositionChanged`.** `AbstractWidget`'s handler maps the
    event out into the parent frame and then moves the widget to follow the
    pointer, so by the time a subclass's handler runs, the item those local
    coordinates are relative to has travelled: mapping them out a second time
    lands at `pointer + this event's delta`. On a drag that crosses the desktop
    in one move that is most of a screen, and the failure is silent — the drop
    hint simply never lit up while the release, whose handler moves nothing,
    was exact. `AbstractWidget.dragPointerParentX/Y` is the pointer as the drag
    itself read it, recorded before it moves anything; anything answering a
    question about WHERE a drag is reads that, and only a release may map its
    own event.
  - **The drop commits NO position, and that is what makes undo correct.** The
    store still holds where the widget was, so the undo entry — the whole
    `plugins.enabled` list from before, exactly the menu's Remove — brings it
    back where it stood rather than under the panel it was dropped on. A commit
    on the way out would store the drawer's own coordinates as a placement the
    user never chose, which is 705e9006d's defect arriving through a new door.
  - **The hint asks the WRITE's question, membership included.**
    `EditModeDrawerDrop` declines an id that is not in `plugins.enabled`, and a
    widget can be on screen, hit-testable and draggable without being in that
    list: `PluginWidget.lockOnlyWidget` is exactly one — drawn on the Lockscreen
    tab, and still a live `MouseArea` at `opacity: 0` on the Desktop tab. With
    `dropWouldRemoveAt` asking only about the rectangle, the drawer lit up, the
    release swallowed its own commit on the strength of that, and the removal
    was then declined: one gesture, a panel promising a removal, and no change
    anywhere — the quiet failure the "not gated on which section" decision above
    exists to avoid, arriving through the other door. Both halves of it are
    driven (`EditModeRuntimeTest`: the hint stays dark AND the drop commits the
    move), because "nothing was removed" is also what a release that never fires
    reports.
    (fix(editMode): the drop hint asks the same question the write does.)
  - **The write is one `QtObject` beside the chrome, not a method on the
    surface.** `plugins.enabled` is one global list drawn on every monitor, so a
    listener per chrome surface answers one drop once per screen and spends an
    undo entry on each; and the surface is a `PanelWindow`, which weston cannot
    build, so a write put there is a write no harness can drive — the reason
    `EditWidgetMenuContent` owns its own Remove. `EditModeDrawerDrop.qml` is
    declared once in `EditModeChrome.qml` and the runtime harness builds it
    directly. The FEEDBACK crosses the same boundary the other way
    (`GlobalStates.editDrawerDropScreen`): the widget being carried is drawn on
    the surface BELOW the chrome, so it passes under the panel and cannot show
    anything itself — the drawer paints its own row-press tint on its body
    instead, which is the vocabulary its rows already use for "the pointer is
    down on me".
  (feat(editMode): one predicate for both directions of the drawer's drop;
  feat(editMode): publish the drawer's reveal to the surface that owns the desktop;
  feat(editMode): a widget dragged back into the drawer leaves the desktop;
  feat(editMode): the drawer says a drop will remove, in its rows' own tint;
  fix(widgetCanvas): the drop hint reads the pointer before the drag moves the widget.)
- **The sidebars are closed on entry and refused for the length of the mode,
  and that is a decision about what the mode EDITS rather than about layers.**
  Both sidebars are `WlrLayer.Top` and the chrome is `Overlay`, so the widget
  drawer — which shares the right sidebar's edge — is painted straight over an
  open one. Neither sidebar is editable in the mode: no drawer section, no
  remove badge, no reorder the mode drives, and no key in
  `lint_edit_mode_scope.py`'s allowlist (the quick toggles' own drag is the
  sidebar's gesture and works with the mode off). So it is a panel covering the
  thing being edited, which is exactly what `activeBarPopup` beside it already
  answers by closing. Two alternatives lose. Dropping the chrome *under* the
  sidebar leaves the drawer half unusable while one is open, and
  `EditModeChromeSurface.underneath` — the mode's one layer trick — exists for
  a special workspace covering the WHOLE desktop, where being as invisible as
  the desktop is the point; a panel on one edge is not that case. And closing
  on entry alone is half a fix: the screen corners, the bar's buttons and the
  IPC handlers can all open one again while the mode is on, so the refusal
  lives on the flag in `GlobalStates` — the one gate every path shares, the
  same argument `StyledPopup.claimSlot` records for refusing there. It sits
  BEFORE the notification sweep in `onSidebarRightOpenChanged`, or a refused
  open marks as read what it never showed.
  (fix(editMode): the sidebars close for the mode and stay closed.)
- **What the mode may write is a failing check now**
  (`tests/lint_edit_mode_scope.py`): a write from any file under the edit-mode
  directories to a `Config.options.*` path outside spec §7.1's placement and
  presence keys, a `PluginState.setOption` key outside `{__gridSize,
  positionLocked, clickThrough}`, or a computed path or key — which no allowlist
  can verify — reddens the suite. Three spellings are caught (assignment,
  in-place `push`/`splice`, `setNestedValue`), the detector is proven against
  in-memory fixtures inside the module, and the sweep asserts it still found the
  edit-mode files so a directory move cannot leave it green over nothing.
  (test(lint): fail on an edit-mode write outside placement's scope.)
- **A right-click on a widget is the per-widget menu in the mode and the global
  lock toggle outside it, and the boundary between the two is the canvas.**
  `AbstractWidget` resolves the mode off its owning canvas — the same property
  the marquee and the Escape ladder already run on, so the overlay's canvas
  (which never follows the mode) keeps today's behaviour with no special case —
  and only ANNOUNCES the click (`contextMenuRequested`): the base class knows
  nothing about what a widget is, and `PluginWidget` is what carries an
  identity. It maps the click with `mapToItem(null, …)` — Qt's own transform
  chain, which composes the mode's scale, the drawer's shift and the press
  scale — never a hand-multiplied viewport scale, which is the compensation the
  contract forbids and is wrong at every scale but 1. The menu's rows are
  exactly spec §9's three licences: Pin writes the one existing
  `positionLocked` writer (`PluginState.setOption` — one writer, two call
  sites) with its drawn check a BINDING on the stored value, seeded the way the
  host seeds it; Size is a stepper over `offeredGridSizes` in the manifest's
  own order writing `__gridSize`, with no row at all for a single-span widget
  (`rowVisible`, not `visible`) and nothing for a widget that declined `grid`,
  whose own handles keep the size they chose; Remove is presence —
  `plugins.enabled` is one global list rendered on every monitor, so it removes
  everywhere, through the same `EditMode.enabledWithout` the drawer's toggle
  uses. The window is the desktop menu's shape on its reused
  `quickshell:desktopMenu` namespace (a minted name would repeat the rules.lua
  threshold exercise to reach the same treatment), the widget vacates the menu
  from `Component.onDestruction` (the `BarContent.filterLayout` shape — its own
  Remove destroys the widget under the open menu), and `closeMenu` is the
  Escape ladder's FIRST rung, so Escape dismisses the menu rather than exiting
  the mode. (feat(editMode): the menu's open state, and an Escape rung that
  dismisses it; feat(editMode): right-click in the mode asks for the widget's
  menu; feat(editMode): the per-widget menu - Remove, Pin, and a Size stepper.)
- **`WidgetsSubmenu` is gone.** Its widget list had been empty since the desktop
  widgets became plugins, and its one live control was the global lock the mode
  suppresses — a switch that turns off something the editor turns back on. The
  desktop menu's Widgets row keeps its click through to Settings and loses the
  hover submenu and the chevron that promised it; the sanctioned writers of
  `background.widgetsLocked` shrink to `AbstractWidget`'s right-click.
  (refactor(desktopMenu): remove WidgetsSubmenu.)
- **The bar and the dock are edited in place, at full size — stage 8.** The
  mode holds them on screen as a TERM of the expressions they already answer
  auto-hide with (`mustShow` in both bars, the dock's `reveal`), never
  anywhere near a surface's `visible`, and the reservation stays
  configuration-only — a bar coming out of hiding changes nothing about the
  shrunk desktop. Their widgets go inert through an input EATER, not through
  `enabled`: disabling a MouseArea disables only that area, and disabling the
  whole subtree runs every control's disabled dim at once. The eater, the
  reorder gesture (`ReorderDragArea`, whose only arithmetic is
  `layout_ops.dropTarget`) and the shared `EditRemoveBadge` load per widget
  from `BarGroup` — one Loader covering both orientations — and
  `BarEditController` (one component both content trees instantiate, turned
  by a flag) owns the indicator, the ghost and every commit. Commits map
  visible indices back to STORED ones (`nthVisible` and friends): the drawn
  slots are the filtered layouts, and an unmapped edit eats whichever hidden
  entry sat between. Each bucket's visible boundary doubles as its drop
  anchor, which is what makes an empty middleLayout a valid drop target. The
  drawer offers bar widgets (`BarWidgets.offerFor` — the policy promoted so
  the settings dropdown and the drawer cannot drift) and dock apps
  (`DesktopEntries` through `AppSearch`), by CLICK only: their drop targets
  live in other windows whose slot geometry this surface cannot map, so
  placement is the in-place drag the panels themselves carry. Escape reaches
  a bar drag through composition into the ladder's `gestureInFlight` (no new
  rung — the precedence does not care which gesture is in flight) and
  `GlobalStates.editReorderCancel` is the return path to a grab held on
  another surface; every commit is also guarded on the mode, because a drag
  can outlive it. `test_bar_dock_edit_contract.py` pins all of it on BOTH
  bars, and `BarEditRuntimeTest.qml` drives the along/across pair at both
  orientations — the axis-inert comparison only real events can see.
  (feat(bar): the mode holds the bar and the dock on screen, as a term;
  feat(bar): bar widgets become inert, badged and reorderable in the mode;
  feat(dock): pinned icons grow remove badges and go inert in the mode;
  feat(editMode): the drawer grows Bar and Dock sections.)
- **The Lockscreen tab is a filter on the viewport, and its preview cannot
  authenticate — stage 9.** The tab is `GlobalStates.editTab`, a string beside
  the mode holding `edit_mode.js`'s tab constants (the literal lives in that
  file alone), reset on exit like the drawer and the menu; the ONE derivation
  of "the viewport is showing the lock screen" is
  `GlobalStates.editLockPreview`, and the contract forbids an `editTab ===`
  comparison anywhere else — the chrome's tab bar maps index↔tab through the
  module's `tabAt`/`tabIndex` for exactly that reason, and its two directions
  are imperative on purpose, because `ToolbarTabBar`'s wheel handler assigns
  the inner index directly and would destroy a binding placed on it. What the
  tab changes is gates on things `Background.qml` already draws: the lock
  wallpaper, the lock WE project, the peel state, the lock blur (through one
  local `lockLook`), `AbstractBackgroundWidget`'s lock filter, and the clock's
  four lock-look bindings (one `lockLook` in the plugin — centring, style,
  show-only-when-locked, the Locked caption). The islands are the REAL
  `LockSurface`, neutered by construction: `interactive: false` gates the
  root area, the field (`enabled` AND `readOnly`), `forceFieldFocus` and
  every click/key handler uniformly — so `tests/test_lock_preview_contract.py`
  holds ALL handlers to the one guard and asserts how many it found, since a
  sweep here that matches nothing is a security hole reading as green — and
  the context is `LockPreviewContext`, a separate component enumerated
  against `LockContext`'s whole surface that constructs no pam machinery and
  spawns nothing (never "the real one with a flag"). The host is a fifth
  sibling carrying the one edit matrix at z 4, above the widgets the way the
  real session lock surface is. The bar and the dock leave the tab through
  the lock's own gates (the bars' loader `active`, the dock's `visible` — a
  surface teardown per tab flip, sanctioned where auto-hide suspension never
  is), while `EditModeInsets` deliberately does NOT drop with them: the
  reservation is configuration-only, and a card resized per tab flip is
  b710ef731's moving target under every widget at once. Island visibility is
  the drawer's Lock section — rows signal, the chrome surface flips the three
  `lock.show*` booleans at literal paths. Known fidelity gaps, accepted and
  stated: no fingerprint glyph in the preview (knowing means asking the
  daemon), parallax stays desktop-framed (its zoom feeds the viewport's
  size), and `centeredWallpaperOnlyWhenLocked` does not preview.
  (feat(lock): LockSurface takes an interactive switch, default on;
  feat(lock): LockPreviewContext, a context that cannot authenticate;
  feat(editMode): the mode's tab, a GlobalStates string beside it;
  feat(background): the viewport draws its locked inputs on the Lockscreen tab;
  feat(bar): the bar and the dock leave the Lockscreen tab;
  feat(editMode): the drawer grows a Lock section for island presence.)
- **The islands' CONTENTS are three ordered lists, resolved by one module —
  stage 9b, spec §14 answered "reorder".** `Config.options.lock.islands.
  {main,left,right}` are declared `list<string>` properties (a `JsonAdapter`
  cannot hold a dynamic map) whose defaults are the hand-placed order the
  surface always drew, and `modules/common/functions/lock_islands.js` is the
  only reading of them: `orderedItems` renders a known id MISSING from a
  stored list at its default position rather than disappearing it, skips an
  UNKNOWN stored id without destroying it, and `storedOrder` merges a commit
  back with every unknown id's presence kept — both directions of the
  version-skew rule, because a list written by one shell version and read by
  another is where silent removal happens. `LockSurface` draws each island
  as a Repeater over the resolver's answer through one `IslandSlot` Loader
  (Layout facts in `islandItemMeta`, components in `islandComponents`, both
  pinned to the module's whole vocabulary — a missing entry is an empty slot
  or a zero margin, not an error); the password field is rendered from the
  list and pinned unmovable by the module's `reorderable()`, reachable
  through the published `passwordField` property. The reorder is stage 8's
  machinery with no fifth copy: `LockIslandEditItem` (eater + shared
  `ReorderDragArea`), `LockIslandReorder` per island (ONE bucket each — a
  cross-island move would write an id the receiving island's resolver
  correctly skips, vanishing it from both), commits through `layout_ops` +
  `storedOrder` at three literal paths, guarded on the mode, with
  `GlobalStates.editLockDragActive` composed into the Escape ladder beside
  the bar's flag. The scope lint sweeps `modules/imi/lock` and admits
  exactly the three list paths.
  **Verifying any of this must never touch the live display.** A lock-screen
  probe run against the user's Wayland session locks the real session, and
  on this machine a real lock suspends the laptop — so every harness and
  probe for the lock surface runs under headless weston with its OWN
  `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` (the shape
  `test_lock_island_reorder_runtime.py` uses), never a `qs -p` against the
  session, and anything that genuinely needs a real `WlSessionLock` is
  recorded as unverified rather than attempted.
  **The session BUS is part of that isolation, and was the half this harness
  missed.** `islandItemVisible` hides `username` and `keyboardLayout` while a
  media player is registered, so a harness on the developer's own bus drags
  two invisible slots and commits nothing — the reorder check failed on the
  maintainer's machine, where a browser held an MPRIS name, and passed
  everywhere else with the shell's code identical. A harness that launches
  `qs` now wraps it in `dbus-run-session` (or names a bus it starts itself);
  `tests/lint_runtime_bus_isolation.py` fails a new one that does neither and
  carries the 33 existing harnesses as a ratchet.
  (feat(lock): lock_islands.js, the islands' order as arithmetic;
  feat(config): three ordered island lists under lock.islands;
  refactor(lock): the three islands become data-driven;
  test(lint): the scope lint reaches the lock surface and admits its lists;
  feat(lock): island contents reorder in the mode;
  test(lock): the reorder harness gets a session bus of its own;
  test(lint): a qs harness must decide which session bus it talks to.)
- **"The lock's look is on screen" is ONE derivation, and the palette is one
  of the things it decides.** `GlobalStates.lockLookActive` is
  `screenLocked || editLockPreview`, and it sits beside `editLockPreview`
  rather than replacing it because the two answer different questions:
  `editLockPreview` decides which SOURCE a layer draws, which every layer
  answers for itself, and `lockLookActive` decides which THEME the picture is
  in, of which the shell has exactly one. The disjunction had been written out
  at six sites across three files and the seventh — `MaterialThemeLoader.
  lockThemeActive` and Appearance's `wallColorQuant`, which the transparency
  is derived from — was missed, so Edit Mode's Lockscreen tab drew the lock's
  wallpaper under the desktop's colours. Six copies of a question is how the
  seventh gets forgotten. `test_edit_mode_contract.py` pins the definition as
  well as the sites, because every gate now reads it and a narrowed definition
  un-filters all of them at once.
  (feat(editMode): one derivation of "the lock's look is on screen";
  fix(editMode): the Lockscreen tab carries the palette with it;
  test(editMode): the tab's palette is driven, and the derivation is pinned.)
- **The lock screen's widget layout forks from the desktop's on the first Lockscreen-tab
  edit, and the SPAN forks with the position.** Spec §4.3 chose one shared position and gave two
  objections; the maintainer overruled it (2026-08-18) and both objections are answered rather than
  waved off. `modules/common/plugins/layout_surfaces.js` is the arithmetic: `lockPositions` beside
  `desktopPositions`, same shape, a screen ABSENT from it inherits the desktop's — so every user is
  still in the one-position model until they move something there — and the first lock write is a
  SNAPSHOT of the whole screen through one `forkedScreen()` that both writers share. The desktop's
  span stays the per-plugin `__gridSize` option; a forked lock screen's lives IN the widget's lock
  record as `gridSize`, so a media widget can be 3×2 on the desktop and 1×2 on the lock (the
  report). `PluginState.currentSurface` resolves the default from `lockLookActive`; **every
  undoable write captures the surface at push time** — a closure resolving it at pop time writes
  the lock's position into the desktop store from the other tab, and the store still reads valid.
  Planted and caught by name in `EditModeRuntimeTest` for both position and span. Presets carry
  `lockPositions` under the same `has()` rule as the desktop map, so an older preset keeps a fork.
  The drawer's Lock section shows "follows the desktop / is separate" and the re-link.
  (feat(plugins): layout_surfaces.js - two widget layouts, one store, fork on first edit;
  feat(editMode): every position and span write captures its surface into its undo;
  test(editMode): the fork is driven through the real drag and the real grip.)
- **PRESENCE forks under that same rule, and the setting it grew out of became the master
  gate rather than being superseded.** `lock.showWidgets` ("show every desktop widget while
  locked") was one all-or-nothing boolean beside a layout that had already forked, so a widget
  could not be on the desktop and off the lock. `lockPresence` in the same store answers "which":
  **null** while the lock follows the desktop's `plugins.enabled`, a MAP once the first pick on
  the Lockscreen tab snapshots that set — and absence is a null rather than a `{}` precisely
  because an empty map is a legitimate forked state, a lock screen with no widgets on it. It is
  **not per screen** while the layout is: `plugins.enabled` is one global list drawn on every
  monitor (the reason the mode's Remove row removes everywhere), and a per-screen presence store
  would invent a capability the desktop has not got. The desktop's set lives in `Config`, which
  the pure module cannot see, so it arrives as an argument — and both the map check and the
  membership walk go by `length` and indices, since a `list<string>` that crossed into a
  `.pragma library` is `typeof "object"` and fails `Array.isArray` (109e6d897).
  Three consequences worth not re-deriving. **The gate keeps the upgrade silent**: off, nothing
  shows, as before; on with the choice still following, all of them do, as before — superseding
  it instead would have needed a migration to turn `showWidgets: false` into a forked empty set,
  in a key every preset already carries. **A lock-only pick costs two edits**, because the host
  builds a widget or it does not: `Background.qml`'s loader gate is the UNION of the two choices,
  and `AbstractBackgroundWidget` gained `visibleOnDesktop` beside `visibleWhenLocked` so one
  expression asks which surface is on screen and then that surface's own filter. And
  `PluginWidget.lockOnlyWidget` is deliberately **narrower than "not in `plugins.enabled`"** — a
  widget being removed from BOTH is in neither list, and hiding it from the widget's own opacity
  would race the loader's exit fade to zero and cut that transition short. No migration entry
  accompanies the field, for the reason `lockPositions` needed none (2262040bc): its absence IS
  the correct upgrade state.
  (feat(plugins): layout_surfaces.js - the lock's widget choice forks too;
  feat(plugins): a widget's presence is asked per surface, not once;
  feat(editMode): the Lock section picks which widgets the lock screen shows.)
- **A dragged widget holds a neighbour's edge through a Schmitt trigger, and
  both thresholds read the SHADOW — stage 10, spec §6.**
  `modules/common/functions/edge_snap.js` owns the arithmetic: four relations
  per neighbour per axis, each carrying the `target` the widget travels to AND
  the `guide` the line is drawn at (they differ for half the relations,
  because the line belongs to the OTHER widget's edge); the two ADJACENCY
  relations land one `Appearance.sizes.widgetGridGap` off the neighbour, not
  flush — flush shipped first and glued widgets into a slab, and the gap that
  already separates cells INSIDE a widget is what makes two widgets read as
  one grid (the module takes the gap as a parameter to stay pure; the widget
  hands in the scaled token; the guide is still at the neighbour's own edge);
  a perpendicular relevance filter measured as the GAP between extents,
  boundary excluded; and
  acquire-at-18/release-at-32 compared against `dragProxy`, never the rendered
  position — with one threshold the decision boundary and the resulting
  position are the same number and the widget flip-flops per event.
  `AbstractWidget` captures neighbour rects at the press (after
  `widgetDragStarted`, so a group drag's followers are already flagged and
  excluded), regenerates candidates per event in the drag proxy's handlers
  (the resolve is stateful, so it lives beside `updateCenterHighlight`, not
  in the drag Binding), and a held target REPLACES the lattice snap rather
  than stacking on it — rounding an exact alignment misses the edge by up to
  half a cell. Snap-then-clamp survives; the group leader snaps and followers
  ride by delta with no new code. The feature rides
  `background.showSnapLines` (the switch that already gates the alignment
  visuals, and the one the dead designsystem duplicate rode for the same
  feature): the guide and the detent travel together, because either alone is
  a mystery. Guides draw ABOVE the widgets in the centre-line family's
  animation tier, travelling while visible and placing instantly while not.
  Two traps paid for: the hold must be cleared one turn AFTER the drag ends
  (`Qt.callLater`) — `onDraggingChanged` and the drag Binding's `when` both
  observe `dragging` with nothing ordering them, and nulling the hold under a
  still-live Binding rounds an off-lattice landing onto the lattice (measured:
  released holding 465, committed 468) — and the runtime harness's landings
  sit on edges the lattice cannot produce (an anchor at x 305), or a wiring
  that silently fell back to `snapX` passes by coincidence.
  (feat(widgetCanvas): edge_snap.js, widget edge alignment as arithmetic;
  feat(widgetCanvas): a dragged widget holds a neighbour's edge, under a travelling guide;
  fix(widgetCanvas): clear the edge-snap hold after the drag Binding stands down;
  test(widgetCanvas): the walk pins the detent in raw numbers, not the module's own;
  test(widgets): drive the edge snap's acquire, detent and release with real drags.)
- **Ctrl+Z reverses the last COMMITTED mutation, and it lives on the canvas
  because that is where the keyboard measurably works — stage 10, spec §7.3,
  gated on §11.4 probe 4 and now measured.** The probe ran in a nested
  Hyprland on the blur probe's shape, hardened: the nested instance gets its
  OWN `XDG_RUNTIME_DIR` and reaches its wayland parent through an
  ABSOLUTE-path `WAYLAND_DISPLAY` (libwayland only prefixes the runtime dir
  onto a relative name), so its sockets cannot land beside the session's; a
  fully headless nested Hyprland is not possible — Aquamarine's
  `CBackend::create()` aborts with no wayland parent and no seat. Keys were
  injected with wtype (a virtual-keyboard CLIENT of the nested display —
  ydotool writes uinput into the kernel and reaches the user's real seat, so
  it is never the tool for this). Measured on 0.56.2: a `Bottom`-layer
  surface with `keyboardFocus: OnDemand` receives real compositor keys while
  holding that focus, an Overlay/Exclusive control proved the injection path,
  and a mapped toplevel beside it did not take the keyboard away
  (`activewindow: Invalid` throughout). The undo stack sits in `GlobalStates`
  with its arithmetic in `edit_mode.js` (bounded at 50 dropping the OLDEST,
  LIFO, copy-on-write because a `property var` signals on reassignment only);
  recording is gated on the mode, one entry per committed mutation (a release
  that moved nothing pushes nothing — every click on a draggable widget
  releases through `commitPosition`), and every entry is a closure over the
  store write that captures plain data and SINGLETONS only — the mode
  destroys its overlays, menus and widgets while the stack outlives them, so
  a closure over a controller throws on the exact keystroke that exists to
  repair a mistake. The dock-pin entry is the same flip again through
  `TaskbarApps.togglePin`, because restoring the list would need the chrome
  surface to read `Config.options.dock` — the second derivation the
  one-answer contract forbids, and it caught exactly that draft. Two edges
  the first cut got wrong, both review-caught: a GESTURE that commits several
  mutations is one entry, so a group release opens a batch the canvas closes
  with `Qt.callLater` (the leader's commit runs later in the same signal
  chain and has to fall inside — without it the leader's entry lands last
  and the first Ctrl+Z moves the leader alone, deforming the cluster); and
  `PluginState.setOption` treats null as REMOVE, because undoing a
  first-ever span commit otherwise persisted a literal null that `option()`
  — which falls back only on `undefined` — would answer past every later
  caller's fallback.
  (feat(editMode): the undo stack's arithmetic - bounded, LIFO, copy-on-write;
  feat(editMode): Ctrl+Z reverses the last committed mutation, on the surface the keyboard reaches;
  test(editMode): drive undo's record, reverse and gate, and pin its shape;
  fix(editMode): a group release is one undo entry, and undoing a first commit leaves no null behind.)
- **An undo BATCH replays backwards, and a keyboard step moves the PLACEMENT
  coordinate rather than the drawn one.** Both were found building the arrow-key
  nudge, and both are traps the mouse could never spring. A batch is one
  gesture's commits, so reversing it means walking from the end: three arrow
  steps on one widget push "back to 36", "back to 48", "back to 60", and
  replaying those in order leaves the widget where the second press left it —
  Ctrl+Z appearing to move it *forward*. The group drag that introduced batches
  could not show it, because its entries are one per widget and independent, so
  any order looks right. And `x` is the DRAWN coordinate, carrying a position
  Behavior: a step that assigned to it and committed in the same turn read the
  value the animation had not reached yet and stored that back, so the widget
  returned to where it started — measured as three presses with `x` unchanged at
  36, the keys reading as completely inert. `AbstractWidget.moveTargetBy` moves
  `targetX`/`targetY` and `PluginWidget.commitPlacement` — the tail of
  `commitPosition`, shared rather than copied — writes the store from them, so a
  translation needs no conversion (the parallax cancellation is constant across
  the step) and the two ways of moving a widget cannot disagree about what is
  persisted. The lattice for the step comes from the CANVAS: `PluginWidget`
  shadows `gridSize` with its component-grid span, so one read off a widget from
  the canvas is an object and every step is silently NaN (8a534a7da).
  (feat(widgetCanvas): widget_nudge.js, a keyboard step as arithmetic;
  feat(widgetCanvas): arrow keys move a selected widget one lattice cell;
  fix(editMode): an undo batch replays its entries backwards.)
(feat(editMode): shrink the desktop into a viewport on the background surface,
feat(editMode): stand the per-widget frost down for the mode,
feat(editMode): draw the shrunk desktop as a card, not as a cropped screenshot,
feat(editMode): shrink the desktop about dead centre, and move it only for the drawer,
feat(widgetCanvas): the lattice is a substrate, and it dissolves at the edges,
feat(editMode): animate the mode on one scalar, shared by every surface,
feat(editMode): draw the mode's toolbar and tab bar on a surface of their own,
test(editMode): score the chrome against the desktop it frames,
fix(widgetCanvas): the lattice comes up with the drag, not with the mode,
feat(editMode): give the card's edge thickness instead of a drawn line,
fix(editMode): stop the card's rounded corner biting a widget the user placed,
fix(editMode): the card's edge becomes a catch, not a rim,
feat(editMode): the drawer's open state, one scalar beside the mode's,
feat(editMode): opening the drawer translates the desktop,
test(editMode): drive the drawer's translation with real gestures.)

**The clock depth layer is the counter-case to that rule, and it is why it is a
FOURTH sibling.** `widgetCanvas` sits at `z: 2` as a sibling of
`parallaxViewport`, so a child's `z` can only reorder it against its viewport
siblings and can never lift it above the desktop widgets — `weTransition` at
`z: 1` is exactly that case. Anything that must draw *over* the widgets while
tracking the wallpaper therefore cannot live in the viewport at all: it is a
sibling at `z: 3` that reconstructs the pan by binding `x`/`y`/`width`/`height`
to `parallaxViewport`'s **live** properties (never `bgRoot.parallaxOffsets`,
which is the 600ms Behavior's destination — the frost's `wallpaperRect` reads the
same four for the same reason), carries its own `visible: !bgRoot.suppressContents`,
and declares `enabled: false` because `desktopRightClickArea` at `z: -2` works
only while everything above it lets clicks through.
`tests/lint_clock_depth_geometry.py` pins all of that;
`tests/test_clock_depth_compositing.py` renders it under headless weston and
samples the pan mid-animation, because a layer bound to the destination settles
in exactly the right place and passes every settled check.

**Being above the widgets is also why it stands down for Edit Mode**
(`ClockDepthLogic.eligible`'s `editing` refusal). Once the mode's cover moved
below the widget canvas, this layer was the one thing left drawing above it, and
it cannot follow the widgets down without putting the widgets under the cover
again — which is the bite that move removed. Two reasons to refuse rather than
reorder, and they are both its own: it paints the wallpaper's subject OVER the
widgets the mode exists to let the user arrange, which is a partly hidden widget
in the one mode where that matters most (the sibling of the `selecting`
refusal); and it reconstructs the parallax viewport, which is deliberately
larger than the screen (`workspaceZoom`, 1.1 by default) with only the layer
surface's own edge keeping that overscan off screen. The mode's transform pulls
the desktop's edge away from the surface's and puts the blurred backdrop in
between, so a subject reaching the picture's edge would be free to paint up to
154px past the card at 5120x1440. The refusal touches nothing else:
`ClockDepth.watching` is `enabled || picking`, so entering the mode drops no
cached answer and leaving it re-runs no segmentation.
(feat(background): draw the wallpaper's subject over the desktop widgets,
fix(clockDepth): stand the depth layer down for the mode that arranges widgets.)

**`OpacityMask` masks by the mask's ALPHA channel and nothing else, so a
grayscale mask is opaque everywhere.** The obvious artifact for a segmentation
mask is an "L" PNG — white subject, black background, and a mask you can look at
— and handed to `OpacityMask` it lets the *whole* source through, because black
at alpha 255 is as opaque as white. The clock depth layer drew the entire
wallpaper flat over the clock that way, with correct geometry throughout and
nothing in any log. `scripts/background/subject_mask.py` writes "LA" — the same
plane in both channels — so the alpha masks and the luminance keeps the file
inspectable. Anything else here that reaches for `OpacityMask` has the same
question to answer about what its mask's alpha actually is.
(fix(background): write the subject mask into its alpha channel too.)

**A mask cut at the model's square input is not the wallpaper's aspect, and
filling it into the same box is not the same crop.** `isnet-anime` squashes the
whole picture to 1024² (padding is measurably worse — with black bars the model
returns the entire picture as the subject), so the stored mask WAS square (it is
aspect-true since the entry below) while the wallpaper is drawn `PreserveAspectCrop`. Filling both into the viewport
stretches them differently — by 3.5× on this monitor. `ClockDepthLogic.coverRect`
returns the rectangle the whole wallpaper would occupy if nothing clipped it; the
mask is `Image.Stretch`ed into that and the surface clips it back, which is
undoing the squash and re-applying the crop in one step. Kept as a pure function
in `modules/common/functions/clockDepth.js` beside the eligibility predicate for
the same reason `ParallaxMath.sampleOrigin` is: nothing about the rendered layer
is reachable from `qmltestrunner`, so the arithmetic has to be.
(feat(background): draw the wallpaper's subject over the desktop widgets.)

**The model's square is the right INPUT and was the wrong STORAGE, and the two
came apart because the softness was being upscaled with the mask.** Squashing a
5760x2318 wallpaper into 1024² gives every mask texel ~5.6 picture pixels, and
what shipped was that raw matte upscaled bilinearly by Qt: hair claimed a band
of wall around itself and a striped wall behind a hairline showed through as
subject. The producer now hardens every mask around 0.5 with a k=6 sigmoid
(0.5 stays at 0.5, so no pixel changes sides) AFTER resampling it to the
storage size — 4096 on the long side, aspect-true, never larger than the
wallpaper — and the order is what makes it work: soft band 0.307 Mpx as
shipped, 0.235 with harden-then-resample, 0.119 with resample-then-harden.
Three things to carry forward. **A second model pass over the subject's box
was landed and reverted in the same PR**: measured, it lost 17.7% of the
coarse subject (the neck went 0.994 → 0.671) for 0.5% gained, and the stripe
cleanup it was credited with was the hardening's — the stripes were already at
0.257 in the single pass. **A guided filter was tried and rejected** for
widening the band along low-contrast outlines. And `coverRect` needed no
change for a non-square salient mask, for the reason the prompted-model entry
below already gives — it is a rectangle for the wallpaper and never reads the
mask's shape — but the comments on both sides of it *said* the mask was
square, and now say what it was and what it is.
`tests/test_subject_mask_refine.py` pins the curve, the resample-then-harden
order (against a control that must itself show the ramp) and the storage size
without loading a model. Design doc §9.
77497c63a ("feat(background): harden a mask's edge around the model's own boundary"),
983e4c529 ("feat(background): store a mask aspect-true at 4096 on the long side"),
7e0dc5f16 ("revert(background): drop the second model pass over the subject's box"),
1a6a2b970 ("feat(background): harden the edge after the resample to storage size, not before").

**Two captures separated in wall-clock time on a desktop somebody is using are
not an A/B test, and the thing that changes between them becomes your signal.**
The clock depth layer was reported as making the wallpaper's quality "drop
completely", measured with two `grim -o DP-1` shots taken minutes apart with the
feature toggled between them, and scored at 97.8% of pixels differing with a mean
absolute difference of 48.5/255 over the whole frame. That was read as the masked
copy landing off by a scale factor, and a whole geometry hypothesis was built on
it. **The user had changed the wallpaper between the two captures.** The diff was
two different pictures. Nothing about the numbers looked wrong — they were
enormous, consistent, and reproduced the reported symptom exactly, which is what
made them convincing. Before diffing two frames of a live desktop, ask what else
could have moved; if the answer is "anything", the measurement belongs in one
process with the inputs pinned.

The repair generalises past this feature: **find the invariant that turns the
question into an oracle.** The depth layer paints the wallpaper's own pixels back
over the wallpaper, so where no widget sits it draws a picture over itself —
which means with an empty widget canvas, depth on and depth off must be the same
frame *whatever the mask contains*. `tests/test_clock_depth_noop.py` runs exactly
that: one `qs` process, one wallpaper nothing can swap, only the depth flag moving
between the two grabs. On the current code it is bit-identical on its synthetic
fixture and differs by at most one least-significant bit on 0.18% of pixels
against the real 3840x1594 wallpaper — the source making a round trip through the
effect's intermediate buffer — so the alignment question is settled rather than
argued. Its fixture's wallpaper aspect is deliberately nothing like its
viewport's, because at a matching aspect `PreserveAspectCrop` is the identity and
every crop bug is invisible; the sibling compositing probe's 2:1-into-2:1 fixture
has that hole, which is why "the fixture actually crops" is a check there rather
than a comment. Note the half the oracle cannot see: a mask registered to the
wrong pixels still passes, because masking the wallpaper with the wrong shape
still draws the wallpaper over the wallpaper.
(test(background): score the depth layer's no-op invariant in pixels.)

**A visualizer that computes its own geometry is a visualizer that can lie about
the thing it exists to judge.** The wallpaper selector's depth picker is where
the accept/decline verdict is given, and it drew its preview from its own copy of
the layer's stack — the same `coverRect` call, the same clipping surface, the
same `OpacityMask`. Two hand-written copies of a registration is the shape this
repo keeps paying for, except worse in this direction: a picker whose crop drifts
from the layer's certifies a mask against a geometry the desktop never draws, and
the drift is invisible precisely because both look plausible. They are one
`modules/imi/background/ClockDepthCutout.qml` now, and the rule the lint enforces
is the deliverable rather than the component — `coverRect` may be called from
that file and from its own unit test and nowhere else, so a second caller
reddens the suite instead of becoming a second opinion.

Three things about building the inspection view on top of it. The veil that dims
what the model did *not* claim is `OpacityMask { invert: true }` over the **same**
surface the cutout is masked by, so the lit region and the drawn region cannot be
a pixel apart. The contour is a `Glow` with `transparentBorder: true`, because
without it the blur clamps at the item's edge and a subject touching the bottom of
the frame smears into a band across it — which reads as a defect in the mask being
judged rather than in the instrument judging it. And its colour is hardcoded,
which is the one place in this shell that is right: every `Appearance` token is
generated *from* the wallpaper on screen, so a token there is guaranteed to be a
colour the picture already contains.
(refactor(background): one cutout for the layer and the picker to draw.)

**And when both models return nothing, the answer is a different QUESTION, not a
lower threshold.** Swept over the 94 wallpapers in this library, the two salient
detectors leave 45 of them at `none` — half the library, with the picker
correctly reporting that neither found a subject and nothing to be done about it.
The tempting read is that `EMPTY_FOREGROUND = 0.005` and the `mask > 0.5`
binarisation are throwing away a faint answer. They are not, and the measurement
is what settles it: before any threshold, on `aishot-3263.jpg`,
`isnet-general-use` claims 2.78% of the frame at 0.1 confidence and 0.28% at 0.5,
`isnet-anime` 0.07% and 0.00%; on `aishot-1206.jpg` it is 1.20%/0.19% and
0.00%/0.00%. Admitting a claim that small admits noise. These are salient-object
detectors — one dominant object against a separable background — and a full-bleed
wallpaper has no background to separate from, so the model is being asked a
question the picture does not answer. `mobile-sam` is asked a different one
("what is the thing at this point"), which is why it is a third column in the
picker rather than a fourth detector, and why the user clicking is not a fallback
but the mechanism. (feat(background): a third model that answers a click instead
of the picture.)

Four things about that column generalise past it:

- **The encoder/decoder split is a contract, not an implementation detail.**
  Encoding the picture costs seconds and depends only on the picture; decoding a
  mask from clicks reads the embedding and costs milliseconds. Measured on a
  7680x2160 wallpaper: 1.63s for the first click, 0.34s for the second, of which
  0.24s is starting Python. A fused single-file export would charge the first
  click's price for every click, and refinement — which is the entire interaction
  — would be unusable. `tests/test_clock_depth_cache.py` pins the pair as two
  files, and pins that a cached embedding comes back with the encoder file absent
  and `onnxruntime` raising on import.
  (feat(background): a third model that answers a click instead of the picture.)
- **The prompt lives inside the mask, in a PNG text chunk.** A SAM mask is a
  function of the clicks as well as the picture, so something has to record them
  — and every other place to put them is a pair that has to agree. In the key
  they mint an entry per click, so a five-click refinement leaves five masks and
  needs a sixth file to say which was accepted. In a sidecar they are two files a
  sweep, a copy or a crash can separate, and `accept` is a byte copy so the
  sidecar would have to be copied by hand in the one place forgetting is silent.
  In `Config` they are a map keyed by a runtime path, which the `JsonAdapter`
  cannot hold. Inside the file the prompt cannot arrive without its mask or
  outlive it, `accept` carries it for free, and the accepted copy keeps saying
  what it was cut with after the candidate is refined further. `status` reads it
  back with a hand-written chunk reader, because that path may not import Pillow.
  (test(clock-depth): pin the prompt, its home in the mask, and the embedding cache.)
- **`coverRect` needed no new case, and that was confirmed rather than assumed.**
  A prompted mask comes out at the picture's own aspect (SAM resizes the longest
  side and pads) where a salient one is square (isnet squashes), and `coverRect`
  exists precisely because of that squash — so the obvious guess is that a
  non-square mask needs a second path. It does not: the rect is a rectangle for
  the WALLPAPER and the function never reads the mask's dimensions at all, so
  stretching any mask into it maps that mask's whole extent onto the picture's
  whole extent. `tst_clock_depth_eligibility.qml` pins both halves, and its
  second case uses a 3.56:1 picture in a 4:3 box on purpose — at a matching
  aspect the box IS the cover rect and every registration bug is invisible.
  (test(clock-depth): confirm a picture-shaped mask needs no new registration.)
- **A file rewritten at the same path is not reloaded, and neither clearing the
  source nor `cache: false` fixes it.** Qt keys its pixmap cache on the URL, so
  an `Image` whose file changes underneath it keeps drawing the old bytes for
  the life of the process. Measured with a `qml6` probe: a 32x8 PNG rewritten on
  disk at 99x17 and re-assigned to the identical URL still reported
  `implicitWidth` 32, and setting `source = ""` first and re-assigning did not
  help; with a `#<token>` fragment appended it loaded the new bytes, and the
  fragment is not part of the filename so nothing else about the load changes.
  This bites twice here — the prompted candidate is rewritten on every click and
  the accepted mask whenever a second candidate is accepted for the same
  wallpaper — and both failures look like the feature ignoring the user rather
  than like a cache. `ClockDepthCutout.maskRevision` carries the producer's
  token (the file's mtime in nanoseconds, as a **string**: 1.8e18 does not
  survive a JSON round trip through a double), and
  `tests/lint_clock_depth_geometry.py` fails on a depth layer that names the
  mask path without it. Anything else here that writes a file the shell is
  already displaying has the same question to answer.
  (fix(background): bust Qt's pixmap cache when a mask is rewritten in place.)
- **A click that finds nothing must not write a `.none` marker, and it does not
  use the detectors' floor either.** That marker means "this model looked at this
  picture and there is nothing in it" and is worth not re-learning at 4.5s a
  time. A click that lands on flat sky is one attempt, and recording it as a
  refusal tells the picker to stop offering the one column the user aims. The
  threshold is a separate constant for the same reason: `EMPTY_FOREGROUND`
  (0.005) divides a model's own answer from a stray fragment, while a click is
  the user asserting there is something there — measured, reusing it discarded a
  76000-pixel object on a 7680x2160 wallpaper as "nothing there", and it was not
  buying the refusal it looked like it was for, since a click on flat sky comes
  back at 1.6-10% because SAM answers with the sky.
  (fix(background): a click's floor is not the detectors' floor.)

**A live Wallpaper Engine scene is masked by a mask of its own STILL, keyed on the
project, and the predicate refuses the wrong silhouette from both sides.** The
shell already photographs every project it renders (`captureGreeterStill`), and
that still is the viewport itself at the viewport's size, so a mask cut from it
registers 1:1 - but the still is re-grabbed every session, so keying its cache
on the file's stat triple would forget the user's acceptance on every restart.
`subject_mask.py` takes `--identity we:<projectId>` on every verb and
`ClockDepth.askingWe` decides when to send it (never during a preview - a
preview is a still picture over the live scene and the question is about that
picture). `ClockDepthCutout.liveSource` paints the live surface through the same
`OpacityMask` (a masked still would freeze every animated pixel inside the
silhouette), falling back to the wallpaper image, which
`lint_clock_depth_geometry.py` pins. `clockDepth.js` compares `weActive` against
`maskIsWe` rather than refusing `weActive`: a project's mask over the static
fallback (`web`, `weFailed`, the safety screen) is the same wrong silhouette as
a still picture's mask over a live scene, and one comparison holds both. Two
things a first cut would get wrong: `status` answers before its picture exists
(`available: false` - a project on screen for the first time has no still until
600ms after its first frame), so the picker says "waiting for the first frame"
and the grab's completion pokes `ClockDepth.refresh()` - observed, not polled -
and the desktop selector cannot sample another window's surface, so it draws the
candidate cut from the still over the live scene, frozen inside the silhouette,
which is exactly the §8.4 honesty question the user is asked to judge.
(feat(clockDepth): the producer takes an identity in place of the stat triple,
feat(clockDepth): mask a live Wallpaper Engine scene with a mask of its still.)

**And the click belongs on the desktop, because a mask judged at screen size
cannot be authored on a thumbnail.** The gesture shipped on a ~300px preview
inside the depth picker, which is a structural mismatch rather than a matter of
taste: the mask is scored against real widgets at 5120x1440 and was being aimed
at a postage stamp, so a click landing on a character's shoulder in the preview
is several hundred pixels off in the thing being judged - and nothing reports it,
because a mis-aimed click comes back as a perfectly good mask of the wrong thing.
`modules/imi/clockDepthSelect/` is a transparent, screen-sized `Overlay` surface
per output; the picker keeps the two detector columns, this wallpaper's verdict
and the way in. Four things about it generalise.

- **Nothing on that surface redraws anything, and that is the whole design.**
  The wallpaper is already on screen at exactly the size and crop the mask has
  to line up with, and the widgets are already under it, so the pixels clicked
  are the pixels the depth layer will mask by construction rather than by
  arithmetic, and the cutout drawn over the widgets IS the occlusion being
  judged. A second copy of either is a second chance to be misaligned, in a
  feature that already spent an evening on a misalignment that turned out not to
  exist (see the two-captures entry above). `test_clock_depth_select_contract.py`
  fails the suite on an `Image` appearing in that file at all.
- **A layer surface cannot read another window's items, so the geometry is
  PUBLISHED rather than re-derived.** The wallpaper viewport is oversized and
  offset by the parallax pan, and `ParallaxMath.offsets` is right there and
  pure - reconstructing it on the selector's side would look like reuse and be a
  second derivation of the one number `ClockDepthCutout` exists to have only one
  of. `Background.qml` publishes the depth layer's own live box per screen into
  `GlobalStates.clockDepthViewports` (including the wallpaper ITEM's source, not
  the config path, for the reason the layer reads the item), the surface draws
  its cutout into that box, and the click is measured against the rectangle that
  same cutout publishes. The binding is null while the mode is disarmed, so it is
  a comparison rather than a fresh object per frame of every pan for the rest of
  the session. Note which coordinate space that leaves: a click arrives in SCREEN
  coordinates and the registration is expressed inside the box, so
  `clockDepth.js`'s `promptFromScreen` composes the translation - and the
  translation is exactly the term that is zero with parallax off, i.e. correct on
  the first screen anyone tries it on and wrong on every workspace but the middle
  one.
- **Two flags meaning "somebody is picking" is one flag too many.** `ClockDepth`
  drops every cached answer the moment nothing is `watching`, and the picker's
  claim (`picking`) dies with the picker as the wallpaper selector closes. Giving
  the new mode a second write of that same bool means whichever surface goes away
  last clears it, on an ordering nothing controls - and clearing it forgets the
  candidate the user walked out to judge. `watching` reads
  `GlobalStates.clockDepthSelectOpen` directly instead, and the entry point arms
  BEFORE either surface closes.
- **The predicate for "can this be picked on" is deliberately not a subset of
  `eligible`.** Two of that function's refusals - no mask, and the per-wallpaper
  opt-out - are precisely the states picking exists to change, so inheriting them
  would make the feature unreachable from the half of the library it was built
  for. `selectable` refuses the other thing they have in common: a desktop whose
  pixels are not the still image the producer is being asked about (a preview the
  wallpaper selector reverts on close, a live Wallpaper Engine project, centred
  mode, the lock screen). `eligible` gains one refusal of its own, `selecting`,
  because the accepted mask drawn under a candidate is a second silhouette and
  wherever the two disagree the difference reads as the candidate having claimed
  something it did not.

  Two smaller ones. The surface takes `OnDemand` keyboard focus, never
  `Exclusive` - there is one per output and an Exclusive grab is session-wide,
  the trap `Screensaver.qml` records. And its namespace needs `blur = false` plus
  a region over its toolbar rather than falling through to the catch-all
  `ignore_alpha = 0.05`, under which a screen-sized surface of transparent pixels
  asks the compositor to blur the entire screen.
  3869f90e9 ("feat(clockDepthSelect): pick the wallpaper's subject on the desktop itself"),
  e3f0f7e00 ("feat(background): stand the depth layer down while a pick is live, and hand over its box"),
  3e30a844b ("feat(clockDepth): answer where a desktop click lands, and when one is allowed"),
  5ad1db2be ("refactor(wallpapers): make the depth picker the way in, not the place to author").

**A segmentation model returning nothing is usually the wrong model, not an empty
picture.** `isnet-anime` and `isnet-general-use` are complementary and neither is
a superset — measured, `isnet-anime` returns `none` on `cat_upscayl_2x…png` where
`isnet-general-use` returns a foreground of 0.143, and the pair swap on other
wallpapers. So a UI that reports one model's refusal as "no subject found" states
a verdict on the image that the evidence does not support, and a user who reads it
stops. Both models are offered side by side, at the same size, and a refusal
points at the other column.
(feat(wallpapers): give the depth picker an inspect mode.)

**A sample rect and the item it samples must be in the same coordinate space —
and "it samples the real thing" is not evidence that they are.** The desktop
widgets' frost hands a `sourceRect` to a `ShaderEffectSource` over the wallpaper.
Every wallpaper layer is declared inside `parallaxViewport`, so all of them are
viewport-sized and viewport-positioned, while a widget's own x/y are measured
inside the widget canvas — a screen-sized *sibling* that travels at
`parallax.widgetsFactor` while the wallpaper travels at 1. That difference is the
whole effect, so the two frames never agree except at rest, and the frost showed
the wrong slice of wallpaper on every workspace but the middle one
([#157](https://github.com/XephyLon/immaterial-impulse/issues/157)). Note which
half the reasoning got wrong first: the live Wallpaper Engine path samples the
genuine, already-transformed surface and was assumed immune for that reason — it
misaligned identically, because sampling a real item fixes nothing when the rect
handed to it is measured from somewhere else. A reconstruction has the same rule
plus one more: it must also be the *size* of the thing it stands in for
(`parallaxWidth x parallaxHeight`, not the screen), or it is a different crop of
the same file. Both corrections are one function,
`ParallaxMath.sampleOrigin(canvasOffset, widgetPos, wallpaperOffset)`, kept pure
beside `widgetOffsets` because nothing about the rendered frost is reachable from
a test — `qmltestrunner` cannot construct Quickshell types and the software scene
graph draws no `ShaderEffect`. Feed it the containers' live animating x/y, not the
parallax targets, or the frost only agrees once the two 600ms pans settle.
e4ff7abbb ("feat(parallax): work out where a widget's frost must sample the
wallpaper"), ca667957a ("fix(widgets): sample the desktop frost in the
wallpaper's own space").

**And ask who is painting the wallpaper before applying any of that.** A video
wallpaper is drawn by `mpvpaper`, a separate Wayland client on its own layer
surface, which `parallaxViewport` does not move — so a video neither pans nor
zooms on screen, and giving its frost the viewport's offset adds travel the
wallpaper never had, breaking the one case that was right at rest. While
mpvpaper owns the screen the wallpaper *is* the screen. Two things that look
like problems there are not: sampling the real player surface is not merely
declined but unavailable (a `ShaderEffectSource` reaches items in this scene
graph, and another client's surface is not one), and the still it samples
instead is not a broken `Image` — `wallpaperPath` already resolves to
`background.thumbnailPath`, the JPEG first frame `switchwall.sh` extracts with
ffmpeg. Branch on `videoRevealed` rather than on `wallpaperIsVideo`: during a
switch cross-fade and on the lock screen the shell draws that thumbnail inside
the viewport itself, and there the viewport is right again. 918592d33
("fix(background): frost a video wallpaper against the screen, not the
viewport").

**A feature that was config-only cannot be revived on its stored values.** The parallax knobs
shipped for the whole life of this shell with nothing reading them, so every `config.json` holds
values that predate the feature doing anything - on the author's machine every switch was `false`.
Turning the code back on against those values ships the feature dead for everyone who has ever
written a config, which is everyone, and no unit test sees it: the QML default says `true`, the
stored config says `false`, and the adapter's answer is the one that runs. Reviving dead config
therefore needs a one-shot migration with a marker (`migrateDeadParallaxSwitches`), and a runtime
test that seeds a real config directory. Reset only the switches - a tuned number is a plausible
preference and usually cannot disable the feature by itself.
(fix(config): revive the parallax switches every stored config turned off.)

**`busctl monitor` is how a Process streams D-Bus signals here, and the sender filter has to live
in the match rule because the output does not carry one you can use.** `services/PhoneConnect.qml`
is the case (`services/Clight.qml` is the sibling that only calls). Measured against a live KDE
Connect daemon on systemd 261: a monitored signal's `sender` is the **unique** name it arrived on
(`:1.55`), never the well-known name, so a QML-side check for "is this the daemon" has nothing to
compare against — `--match=type='signal',sender='org.kde.kdeconnect.daemon',path_namespace='…'` is
the only place the daemon can be named, and dbus-daemon resolves that well-known name for you
across daemon restarts. Four more things about that path, each of which cost a measurement:

- **A `SERVICE` argument to `busctl monitor` does not narrow it the way it reads.** Run as
  `busctl --user --json=short monitor org.kde.kdeconnect.daemon`, the capture came back full of
  other clients' traffic (an unrelated `name.giacomofurlan.ArctisManager` call, portal `Get`s).
  `--match=` did narrow it, to zero lines over ten seconds on the same bus. Filter with the match
  rule, not the positional argument.
- **The output is one JSON document per line and it is flushed per message**, so a `SplitParser` on
  `stdout` sees a signal as it happens — checked by watching the redirect file grow while the
  process was still running, not by reading it after the exit.
- **An instant exit is the normal failure, which is why CONTRIBUTING.md's backoff rule bites
  here specifically.** A match rule the bus rejects fails with `Call to
  org.freedesktop.DBus.Monitoring.BecomeMonitor failed: Invalid match rule` and exit 1, in
  milliseconds. A `running:` binding on that Process is a tight respawn loop. `PhoneConnect`
  starts it imperatively, restarts only through `monitorExitPlan` (capped exponential backoff, a
  ceiling of five per **daemon appearance**, and a healthy-run reset so one daemon restart in a
  long session does not spend the ceiling) and falls back to the poll past the ceiling. The poll
  is never removed: nothing announces a daemon *appearing* — there is no monitor running to hear
  it on — and a daemon that dies without a parting signal would otherwise freeze the model.
- **Signals arrive in bursts, so a signal drives a coalesced re-read rather than a sweep.** One
  device leaving the network emitted **seven** signals within a millisecond
  (`statusIconNameChanged`, `deviceRemoved`, `deviceListChanged`, `reachableChanged`,
  `linksChanged`, `deviceAdded`, `deviceListChanged`), and each re-read is a chain of `busctl`
  spawns. The settle timer also has to **re-arm** rather than fire while a sweep is in flight,
  because the sweep declines then and firing would drop the change that asked for it.

The gate deciding whether to start it was first written as a `readonly property bool` derived from
`backend` and read from `onBackendChanged` — the change-handler trap under
[State propagation is reactive](#state-propagation-is-reactive-or-it-is-a-bug-waiting) — so it
answered with the *previous* backend, the monitor never started, and nothing showed it because the
poll kept the model correct the whole time. Only `tests/test_phone_connect_monitor_runtime.py`
could see it: a source contract reads a gate that is spelled correctly, and `qmltestrunner` cannot
construct the `Process` the gate guards. That harness is also where the *lifetime* is pinned, and
it asserts the spawn **timestamps** as well as the count — "it stopped after six spawns" is equally
true of six spawns in six milliseconds, which is the bug.
(feat(phoneConnect): drive updates from the daemon's signals, not from the poll,
fix(phoneConnect): the monitor's gate is a function, because a handler cannot read its own binding,
test(phoneConnect): drive the monitor's start, its stream, its backoff and its ceiling.)

**A player on the MPRIS bus may be a proxy for another player, and every field you would match on
is the borrowed one.** `playerctld` is `playerctl`'s daemon, not a player: it re-publishes whichever
player it considers *current* — and current means last **interacted with**, not playing — so it sits
at `PlaybackStatus: "Playing"` over a paused player's metadata indefinitely.
[#170](https://github.com/XephyLon/immaterial-impulse/issues/170) measured its `Identity` as
`"Mozilla zen"`: the name of the player it was mirroring. So `identity`, `desktopEntry`, the track
title and the playback state are all second-hand, and a rule as reasonable as "prefer a player that
is playing and has metadata" matches it *truthfully*. The only honest thing about it is its bus
name, which is what `services/MprisSelection.js` excludes it by — and unconditionally:
`media.filterDuplicatePlayers` is a preference about duplicates, while a proxy is not a player at
all. Two neighbours that look like the same case and are not: `plasma-browser-integration` may be
the only MPRIS source for a browser whose own is switched off, and `kdeconnect.mpris_*` is a phone,
which is a genuine remote rather than a local mirror. Both stay.
bb789e017 ("fix(mpris): stop a proxy and duplicate suppression hiding what is playing").

**Duplicate suppression must never drop a bus that is playing, and note which half of that issue's
diagnosis was wrong.** #170 blamed `playerctld` — but on the reporting machine it was already
excluded, and what actually decided the selection was the *other* filter: while
`plasma-browser-integration` is on the bus, every native Firefox and Chromium bus was dropped as its
duplicate. That integration republishes one browser tab at a time, so with a paused video mirrored
through it and music playing in the other browser, the only bus carrying the music was suppressed
and the paused mirror was the sole surviving candidate. A correct-looking diagnosis of a real
lurking bug can still not be the bug in front of you; read what the filter chain actually returns
before fixing the part that was named. bb789e017 ("fix(mpris): stop a proxy and duplicate
suppression hiding what is playing").

**An MPRIS bus name is not stable, so nothing may be stored against it.** The spec lets a program
publishing more than one bus append `.instance<pid>` — Chromium writes
`org.mpris.MediaPlayer2.chromium.instance700643`, Firefox `.instance_1_52` — and that suffix is new
on every launch. `bar.media.preferredPlayer` stores the bus name minus the
`org.mpris.MediaPlayer2.` prefix and minus that suffix, which is what survives a restart and what
the settings picker writes; a `kdeconnect` bus carries no suffix and keeps its whole name, one id
per device and player. Resolution lives in `MprisController` alone (`activePlayer`,
`meaningfulPlayers`, `playerOptions`) because four widgets used to carry their own copy of it and
had already drifted apart; `tests/test_mpris_controller_contract.py` fails the suite on a fifth.
25329ade9 ("feat(mpris): resolve the preferred player once, against a stable bus id").

**Treat repeated binding exceptions as potential resource runaways, not harmless log noise.** A
sidebar media-player binding called `filterDuplicatePlayers()` without defining the helper in that
component. The visible log only gained an occasional `ReferenceError` when MPRIS state changed, but
the `qs` main thread eventually spun at 100% CPU while anonymous resident memory grew past 30 GiB,
freezing the shell and threatening to freeze the whole machine. If the shell becomes unresponsive,
inspect the live process before restarting it (`ps -p <pid> -o stat,%cpu,%mem,rss,vsz,nlwp,wchan` and
`pmap -x <pid>`): a runnable main thread plus rapidly growing anonymous memory points to a QML
evaluation/allocation loop. Correlate the last `WARN scene` entries with reactive bindings, and
verify that every locally-called helper exists in that component or comes from an explicitly
imported singleton/module.

**Do not bind an image source directly to `SystemTrayItem.icon`.** Tray properties are backed by a
third-party StatusNotifierItem over D-Bus. A broken Electron tray provider repeatedly failed its
`IconName` getter; the direct `IconImage.source: item.icon` binding then drove the GUI thread to
100% CPU while anonymous memory grew by gigabytes. `modules/imi/bar/SysTrayItem.qml` deliberately
debounces icon change signals into `stableIconSource`, retains the last non-empty URL, and uses a
fallback glyph for missing/error states. Keep that mediation in place; `tests/lint_systray_icon_binding.sh`
guards the critical source binding.

**Shared chrome must not branch on a specific widget or plugin identifier.** When one overlay widget
needed a brand logo instead of a Material Symbol, the first version taught `OverlayTaskbar.qml` to
check `identifier === "discordVoice"` and imported that plugin's package into generic overlay chrome.
Every later branded widget would have added another branch. The registry entry carries the exception
instead: `OverlayContext.availableWidgets` entries accept an optional `iconComponent`, and the taskbar
renders whatever it is given and binds `toggled` on it. The same rule produced
`StyledOverlayWidget.titleIconComponent`. If shared code needs to know *which* widget it is drawing,
the data model is missing a field.

**A widget whose size inputs are user-configurable cannot have a fixed implicit size on either axis.**
The Discord overlay derived `implicitHeight` from its content but left `implicitWidth` hardcoded, while
avatar size (32-80) and count (1-12) both remained settings — a full row reached ~960px inside a 344px
box. Derive the growing axis too, but compute it *arithmetically* from the inputs rather than reading a
child layout's `implicitWidth`: the content is anchored to this item's width, so reading its implicit
size back would bind width to itself. Cap the result and let the grid wrap instead of growing forever.

**A Wayland client is never told about keys aimed at something else, so the OSK's
physical-key highlight reads /dev/input — and its LIFETIME is the safeguard, not
a promise in a comment.** `scripts/keyboard/key_monitor.py` needs membership of
the `input` group and nothing more (no root, no setuid), and reports evdev
keycodes - the same codes the OSK's keys already carry for ydotool, so a code off
the wire matches a drawn key with no table in between. Three properties are
structural rather than documented, because a program that reads every key on the
machine has to be answerable for it: it carries **keycodes, never characters**
(there is no keymap and no modifier state in it, so `30` is a position whether
the user typed `a`, `A` or a password's first letter - and
`test_key_monitor.py` pins the output's SHAPE, since a later "make this
readable" change is what would turn a position report into a transcript); it
**keeps nothing** (no file writes, and the shell's side holds only what is
down); and `KeyMonitor.watching` is **`readonly` and bound to the OSK's own open
state**, so no second writer can extend it - measured on the live shell as zero
readers at rest, one while the keyboard is up, zero after it closes. Two smaller
findings: a single keyboard appears under several `by-path` names (this machine's
shows up twice), and two descriptors on one device report every press twice with
the second's release clearing a key the first still holds - so devices are
deduplicated by `realpath`; and ydotool's own synthetic keys are NOT seen,
because it creates its uinput device after the scan, which is why a synthetic
press cannot be used as evidence that this works and why the OSK's own taps do
not echo back at it.
(feat(osk): light a key while the physical keyboard holds it.)

## Design language

The shell follows **Material 3 / Material 3 Expressive**. `Appearance.qml` is the single source of
design tokens - color roles (`Appearance.colors.col*`, `Appearance.m3colors.m3*`), font sizes
(`Appearance.font.pixelSize.*`), rounding (`Appearance.rounding.*`), spacing
(`Appearance.spacing.*`), border widths (`Appearance.borderWidth.*`), animation curves/durations
(`Appearance.animation.*`). New UI should pull from these rather than hardcoding colors/sizes/
durations, both for dark/light theme correctness and for consistency with the rest of the shell.
`Appearance.spacing.*` follows Material 3's system scale (`0, 2, 4, 6, 8, 10, 12, 14, 16, 20, 24,
32, 36, 40, 48, 56, 64, 72`), named `space0` through `space900`; `space100` (8px) is the base unit.
Prefer multiples of 8 for the main rhythm and the recommended intermediate tokens for nested
spacing. Use canonical `spaceNNN` names directly; semantic aliases are not supported.
`Appearance.borderWidth.*` is `1/2/4`. Snap raw spacing/padding/margin to the nearest spacing token -
`tests/lint_spacing.py` (run by `tests/run_tests.sh`) enforces declarations and assignments.

**Any `.qml` that references `Appearance` (or any other `qs.modules.common` singleton) as a bareword
must `import qs.modules.common`.** That import is *not* transitive - a file that only has
`import qs.modules.common.widgets` does not get `Appearance` in scope, and the reference silently
throws `ReferenceError: Appearance is not defined` on every binding evaluation. This is not just a
cosmetic error: when the missing token feeds a positioner's `spacing`/`margin`, the binding yields
`undefined` -> NaN geometry, and QtQuick relayout never converges - it pegs a core at 100% CPU and
freezes the shell (this is exactly what a bulk token migration did to `ConfigRow.qml`,
`NotificationListView.qml`, `PluginOptions.qml`, and `StyledPopupMenu.qml`). `tests/lint_qml_imports.sh`
(run by `tests/run_tests.sh` and CI) guards against reintroducing it.

**Strict UI Guidelines:** See [`docs/M3_GUIDELINES.md`](docs/M3_GUIDELINES.md) for the definitive rules on tokens, rounding, layering, and expressive motion that all new components must follow.

**Take a motion tier whole, because half of one is silently a generic curve.**
`NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration }` reads as compliant —
it names a token, it has no literal — and leaves `easing.type` at Qt's default, which is
`Easing.Linear`: exactly the generic curve `docs/M3_GUIDELINES.md` §2 forbids. Every resize grip in
the shell faded in linearly that way beside neighbours easing on `expressiveEffects`, and nothing
about the source shows it. Use the tier's own component
(`animation: Appearance.animation.elementMoveFaster.numberAnimation.createObject(this)`), which
carries the duration, the type and the curve together. Two neighbouring shapes of the same mistake:
a duration written as a literal that happens to match a *different* tier's number (Edit Mode's entry
was `duration: 400` beside `expressiveDefaultSpatial`, which is 500ms's curve at 400ms's clock — a
third timing nothing else in the shell moves at), and an element given no transition at all beside
ones that have them, which is what "not M3E-compliant" usually turns out to mean when someone says
it about a screen rather than about a line. Note `elementMoveEnter`/`elementMoveExit` both carry
`alwaysRunToEnd`, so they are wrong for anything the user can reverse mid-flight — a mode toggled
twice inside its own duration finishes arriving before it starts leaving.
(fix(editMode): take the motion tiers whole instead of half of one each.)

**...and that rule is a failing check now, with a register, because writing it down twice was not
enough.** `tests/lint_motion_tier_partial.py` fails on an animation that names a tier's `duration`
and sets no easing at all. The two fixes above are why it exists rather than a third paragraph:
2044e1b3b ("fix(bar): give the util button's expand the curve it names") repaired the two size
Behaviors in `modules/imi/bar/UtilButton.qml` and left **three more partial takes a dozen lines
below in the same file**, and 8d81d7471 ("fix(editMode): take the motion tiers whole instead of half
of one each") found the resize grip doing it after every grip in the shell had faded linearly since
the file was written. Both fixes repaired the sites someone had noticed.

The tree carried **40** of these across 17 files, deliberately **not** fixed at first — the register
in that file held a count per file, for the reason `docs/M3_GUIDELINES.md` §3 already gives for this
whole class: a curve shape is visually perceptible and cannot be verified from a test, so forty
unverified visual changes in one branch is worse than forty known ones written down. It is a
**ratchet**, not an allowlist: a file outside it may have none, a registered file may not grow, and
a registered file that *shrinks* also fails, so fixing one forces the number down and the register
cannot rot into something nobody rechecks. Two things it deliberately ignores, with the reasoning in
the file: an easing that is present but generic (§3's separate register — a curve somebody chose,
where this is a curve nobody chose), and a duration paired with a curve read straight out of
`animationCurves` (a drift risk, not a live defect, and it would triple the register for no bug).
1c728dd6a ("test(lint): fail on an animation that takes a tier's duration and leaves its curve").

**The register is empty now, and how it emptied is the part worth carrying.** All 40 were taken
whole, one coherent group at a time, each group deciding its tier against what the same gesture
already does elsewhere in the shell rather than against a pattern — the desktop widgets' own hover
handles adopted the spelling `PluginWidget`'s resize grip already used, the settings chevron adopted
the four sibling chevrons', and the niri overview's window rects kept `elementMoveFast` precisely
because `OverviewWidget.qml` animates the same thumbnails for the same gesture on it, so retiering
one of the two overview styles to fix a curve would have made them disagree. Nothing was retiered by
rule: a colour or an opacity already on an effects tier stayed there, and the five span-morph ink
colours stayed on `elementMove` because the colour is a term of the morph rather than an independent
effect — those five are also the only ones written out rather than taken from a factory, and for a
plain reason, which is that `elementMove` publishes a `numberAnimation` and no `colorAnimation`. Do
not re-open the register to land a new one: an entry is a promise somebody comes back, that promise
has been kept once, and a second register growing from zero is an allowlist.
(fix(widgets): a span morph's ink colour eases with the morph, not linearly,
fix(overview): the niri overview's window rects and fades take their tier whole,
test(lint): the motion tier register is empty, and the header says why.)

**`alwaysRunToEnd` is inert inside a `Behavior`, which is most of where this shell reaches for a
tier's factory.** The guideline's carve-out — write the three properties out where the factory's
`alwaysRunToEnd` would change the behaviour — reads as covering every reversible transition, and a
reversible transition here is usually a `Behavior on color`/`opacity`/`x`. It does not:
`QQuickBehavior::write` stops the animation *instance* when the target moves, and `alwaysRunToEnd` is
only consulted on the declarative `running`/`stop()` path. Measured with a `qml6` probe, a 400ms
linear Behavior reversed at t=200 reads **37.4 at t=320 and 0.0 at t=700 with and without the flag**,
while the same pair as *started* animations `stop()`ed at t=200 diverge exactly as advertised — 80.0
then 100.0 against 52.0 then 52.0. So the carve-out is about an animation something calls `start()`
on, and a `Behavior` may take any tier's factory whatever the flag says. This branch's first cut wrote
`ConfigTextArea`'s three focus Behaviors out on the belief that `numberAnimation` (which carries the
flag) and `colorAnimation` (which does not) would resolve its border width and its border colour
differently on an interrupted hover; they do not, and it takes both factories now. Note what this does
*not* license: `elementMoveEnter`/`elementMoveExit` are still the wrong tiers for something the user
reverses, because their curves are directional — that argument survives, the `alwaysRunToEnd` half of
it does not.
(fix(widgets): four shared widgets take their effects tier whole.)

**Its one blind spot, measured while emptying it: `easing.type: Easing.BezierSpline` with no
`bezierCurve` beside it satisfies the check and is Linear.** The lint asks whether an easing is
present, not whether it resolves — which is the right question for §3's "a curve somebody chose", and
the wrong one here. Probed with `qml6`: a 400ms animation declared `Easing.BezierSpline` with an empty
curve and one declared `Easing.Linear` read 52.00 at the same sample, and nothing is logged either
way. `NiriOverview`'s `scrollAnim` had been that since it was written — `elementMoveExit`'s duration
beside `elementMove`'s type — so the overview's scroll-to-workspace was linear while every other
scrolling surface here eased on `Appearance.animation.scroll`, whose duration, type and bezierCurve
both `StyledFlickable`s and both `StyledListView`s already write out. Naming two tiers in one
animation is the tell.
(fix(overview): the niri overview scrolls on the scroll tier, whole.)

**...and the sibling defect is the one that lint deliberately waved through: a duration read out
of `animationCurves` is the tier's BASE, and the speed multiplier is not in it.**
`Appearance.animation.<tier>.duration` is `motion.scale(...)` applied to
`animationCurves.<x>Duration`, so a site reading the second spelling is an animation the motion
slider and the reduce-motion switch cannot reach — silently, in the one tree where 954a7885a
("feat(motion): one policy for the speed, the floor and the stagger") exists so that they can.
Nine sites were doing it, and every one of them reads as compliant: they name tokens, carry no
millisecond literal, and pair with the matching curve. Two of the nine are worse than the rest —
both `ShapeCanvas.qml` copies, so a shape morph was the one animation in the shell that could not
be retimed from `Appearance` at all, the design system's copy having the 350 and the six control
points written out by hand. Nothing in the suite could see any of it; a survey found it
(`docs/p3drovfx-animation-research-2026-08-16.md` §7). Where the duration and the curve are the
same tier, take the tier whole. Where they are deliberately different — `StyledFlickable`'s rubber
band pushes out on the effects duration against `emphasizedDecel`, the recording panel pulses on
500ms against `expressiveEffects` — scale the base through the policy's own door,
`Appearance.animation.scale()`, rather than borrowing whichever tier happens to share the number
and tying the site to a curve it does not use. `tests/lint_motion_multiplier_bypass.py` fails on a
new one; its second fixture is the one that earns its place, because a bare search for the token
reports the honest fix as an offender.
("fix(motion): every catalogued duration goes through the policy").

**There is ONE desktop-widget base class, and a dead copy of it is more dangerous than a live
duplicate.** The vendored design system arrived carrying its own `AbstractWidget.qml` and
`WidgetCanvas.qml` under `designsystem/widgets/widgetCanvas/`, which nothing has ever imported —
`PluginWidget`, `AbstractBackgroundWidget` and the canvas itself all resolve
`modules/common/widgets/widgetCanvas/`. Dead code is not why it was deleted: it still carried the
`MouseArea.drag` + `dragProxy { x: root.x }` pair that d2ebb5aeb ("fix(widgetCanvas): compute the
drag by hand - MouseArea.drag cannot track it") removed against measurements, and it was gated on
a config path that does not exist — three fixes behind the live one and the richer-looking of the
two, so the next agent looking for how a widget drag works finds a plausible file with more snap
code in it and nothing to say it never runs. `tests/lint_no_stale_widget_canvas.py` fails on a
second file of either name and on an import of the deleted path; the first half is the one that
matters, because a dead copy is invisible to every other check in the suite.
("refactor(designsystem): delete the dead copy of the widget base class").

**An animation that loops forever must stop when what it animates is off screen, because a
running animation is a repaint of the whole output — including the parts nobody can see.** The
chain is not visible from the animation: a running animation writes a property every frame; that
dirties the scene; a dirty scene makes the shell commit a frame; and a commit makes the
*compositor* repaint the entire output. So one `RotationAnimation` with `loops: Animation.Infinite`
in `CookieClock.qml` — 30 seconds per turn, behind an opaque fullscreen game — kept a 5120×1440
240Hz screen redrawing continuously, and the user reported "my game's FPS is halved when qs is
running even in fullscreen". It was, and it was that. Measured against FFXIV's own frame counter
(OCR'd off its System Configuration window, so every state used one instrument): shell stopped
108, shell stock **52**, the spin gated on `visible` **94**. Found by `QSG_RENDER_TIMING=1` — one
window syncing at 243Hz for 0ms of render work — and `QT_LOGGING_RULES=qt.quick.dirty=true`
naming the node. `visible` is *effective* visibility, false while any ancestor is hidden, so the
animation never has to know why it is off screen. `tests/lint_infinite_animation_visibility.py`
fails a new ungated one and carries seven registered files whose animations live on surfaces that
are unmapped when idle, as a ratchet.

Two things about the *surfaces* were learned in the same investigation and are worth stating
because both look like the fix and one is forbidden. `quickshell:barPopup` — a screen-sized
surface on the **Overlay** layer hosting the bar's hover cards — was mapped for the whole session
with nothing in it, and a mapped Overlay surface sits over every fullscreen window; unmapping it
while idle was worth 98 → 105 and is safe because no renderer lives in it. The **background**
surface is the same shape one layer down and unmapping it measures better still, and it is
**pinned mapped** by `test_background_fullscreen_suppression.py`: `visible: false` on a
WlrLayershell window destroys it, and destroying that one is what left the embedded Wallpaper
Engine renderer strobing at 30Hz — a photosensitive-seizure hazard. Frame rate does not outrank
that. The frames came back by stopping what kept the window *busy*, not by removing the window.
(perf(clock): the cookie's spin stops when the cookie is off screen;
perf(bar): the popup overlay surface is mapped only while it has a card;
test(perf): infinite animations are gated on visibility, and the overlay stands down.)

**And the last blocker was not the shell at all: any Overlay surface, from anyone, at any size,
holds the fullscreen fast path shut.** With every shell-side cost gone the game still read 84
against a 94 ceiling, `solitaryBlockedBy: other overlays`, and the only overlay left was the
Activate Linux plugin's 340×120 watermark — a process the shell spawns but a surface the shell does
not own. Killing that one process: `solitary` went from 0 to the game's own address, Hyprland's GPU
share from ~9% to **0.0%**, the game to 92. The plugin now stands its watermark down while any
monitor's active workspace has a fullscreen window (`XephyLon/activate-linux-plugin#1`), reading
`HyprlandData.hasfullscreen` like the bar and dock do — a first cut on `Hyprland.workspaces[..].
toplevels` did not re-evaluate on workspace change. The general rule is in `docs/PLUGINS.md`
§"Overlay surfaces and fullscreen windows". Two lessons for the next investigation: `hyprctl
monitors`' `solitaryBlockedBy` is the first thing to read, because it names the class of blocker
outright; and the shell's *own* GPU share reading 0.0% does not clear the shell, because what the
shell spawns and what the compositor does on the shell's behalf are both invisible there.
(docs(plugins): an Overlay surface holds the fullscreen fast path shut.)

**How fast the shell moves is one scalar, and where the bottom of that scale is, is a *different*
declared thing.** `modules/common/motion_policy.js` is the arithmetic (pure, `.pragma library`, so
the decisions are testable and nothing about the rendering has to be); `Appearance.animation`
exposes `multiplier`, `reduceMotion`, `reduceMotionFloor`, `scale()`, `scaleVelocity()` and the
stagger helpers, and every tier duration and velocity in that block — plus `Appearance.interaction`'s
five tiers — goes through them. That reaches ~700 `Appearance.animation` call sites and all 140
`SpanTravel`/`SpanFade` uses without one of them changing.

This is worth having *here* and is largely decorative in the fork it came from, and the difference is
structural: 1728 of their `duration:` values are hardcoded literals across 272 files, so their slider
does nothing for about half of that shell. Ours has 164 literals in 62 files.

Five things about it that are not obvious:

- **The reduce-motion floor is not reachable by the multiplier, and that is the whole point.** The
  fork spells the same idea as `animationMultiplier <= 0.25`, re-derived by hand as a private
  `_animationsDisabled` at seven call sites — so there, "the user turned motion off" and "the user
  likes it snappy" are one number, and dragging a speed slider one notch too far *is* the
  accessibility state. `MULTIPLIER_MIN` is 0.5, `clampMultiplier()` holds for a hand-edited
  `config.json` too, and `appearance.motion.reduceMotion` is a separate declared key with its own
  switch. A floor a slider can land on is a floor a user can leave by accident.
- **The floor is a duration of 0 rather than "switch the Behaviors off", and both halves were
  measured with a `qml6` probe rather than reasoned about.** An animation driven by a `Behavior`
  never emits `finished` at *any* duration — it runs as a job rather than through `start()` — while
  an animation the code *starts* emits it even at duration 0. Every cleanup here that hangs off a
  completion (`BarPopupOverlay.contentExit` releasing the outgoing content tree,
  `ExpandablePanel`'s spent stagger animations) hangs off a started one, so a floor of 0 strands
  none of them; disabling the Behaviors would have reached only half the motion and left the
  started animations at full length. Collapsing the *durations* also reaches the two things a
  `Behavior` does not — a `Timer` whose interval is a tier duration, and a `PauseAnimation` written
  as the difference of two tiers — so a hand-built sequence keeps its order at the floor.
- **A velocity is the reciprocal axis.** `SmoothedAnimation.velocity` is px/s, so a slower shell
  wants a *smaller* number; applying the duration multiplier to it makes "slower" mean "faster".
  `scaleVelocity()` divides, and the floor's velocity is large-but-finite rather than `Infinity`.
- **Two spellings of a tier's base exist in that block and a scaling has to catch both.** Four tiers
  read `animationCurves.*Duration` and eight state a literal; a scaling applied to one spelling
  leaves a third of the catalogue frozen, reads perfectly in review and logs nothing.
  `tests/test_motion_policy_contract.py` reads the whole block rather than a sample, and
  `tests/test_motion_multiplier_runtime.py` reads the catalogue back off a real shell against a
  seeded config — the QML default and the value the `JsonAdapter` merges over it are different
  numbers and only the second one runs.
- **The interaction model is a separate object and is easy to miss.** It carries the motion that
  fires on every hover and press in the shell, so a multiplier that slows every panel while leaving
  every button acknowledging at a fixed 150ms is half a multiplier — and reduce motion would skip
  the class of motion the user touches most.
  954a7885a ("feat(motion): one policy for the speed, the floor and the stagger"),
  da2a87c07 ("feat(appearance): thread the motion policy through every catalogued tier"),
  416dd1420 ("feat(settings): a motion speed slider and a reduce-motion switch").

**One spelling of "these N things arrive in sequence".** `Appearance.animation.staggerRanks()` /
`.staggerStep` / `.staggerDelay()` are it. There were two cascades and they disagreed in exactly the
way that makes duplication a defect rather than redundancy: `Carousel.qml` clamped at ten members
and `ExpandablePanel.qml` not at all, `Carousel` stepped 50ms and `ExpandablePanel` 40ms, and both
numbers were literals. Three rules live in the policy now:

- **Rank by VISIBLE position, never by position in `children`.** A hidden participant that spends a
  slot leaves a hole one step wide in the middle of the cascade, and nothing downstream compensates
  because every later member is still counted from its own index.
- **Clamp the ladder.** `leadIn + index * step` is unbounded and the failure is silent — a twenty
  member group's last member arrives most of a second after the container has finished opening, by
  which point the wave has stopped reading as one gesture.
- **The step is a fraction of a catalogued duration, and it is published UNSCALED.** Whatever
  consumes it scales it once; scaling it in `Appearance` as well would apply the multiplier twice
  and a wave would run at the square of the setting.

**...and a wave with no gate races the reveal it is supposed to land in.**
`Appearance.animation.contentGate` / `contentsArrived(progress, opening)` is the
fourth rule, and it is the one item in
`docs/p3drovfx-motion-measured-2026-08-22.md` §4.1's cross-reference table this
tree had nothing at all for. It is not an M3 rule: M3 says a group enters in
sequence and says nothing about what the group's own container is doing while it
happens, so a group here animated while its container was still growing.
Measured off the sibling fork, their container is at 90% by 133ms and its first
child does not reach 50% until 233ms — container, then fill.

Three things about the predicate. **The two directions are deliberately
different and the asymmetry IS the rule**: on the way in the contents wait for
the gate; on the way out they do not leave at all, they stay drawn and ride the
container off as one rigid transform, so the closing branch holds until the
container has nothing left and the reset happens there, off screen. **`opening`
is the caller's own intent flag**, never a direction inferred from the progress —
an intent flips at the click and the progress follows, so the two branches are
entered by different events and there is no ordering to get wrong. And **the
gate is unitless and unscaled**, because it is a fraction of the container's own
progress: the speed slider and the reduce-motion floor already reach it through
whatever tier that scalar animates on, and a second gate would be the
double-scaling the stagger step exists to avoid.
`EditModeDrawer.qml` is the first adopter; `test_motion_policy_contract.py`
holds it, `ExpandablePanel` and `Carousel` to one spelling.
(feat(motion): a container-progress gate, so contents wait for their container,
feat(editMode): the drawer arrives as a surface and then fills.)

**A start value written through an animated property is not a start value — it
is an animation the next write cancels.** The idiom reads as "put it where it
comes from, then send it home":

```qml
function slideIn() {
    content.y = -content.height;             // the start
    Qt.callLater(() => { content.y = 0; });  // the end
}
```

and it does nothing at all. `y` carries a `Behavior`, so the first write does not
set a value — it STARTS an animation toward one. `Qt.callLater` runs in the same
turn of the event loop, before a frame is drawn, so that animation has advanced
~0ms when the second retargets it *from where the property already is*, and the
result is an animation from A to A: no motion, no warning, and QML that reads
exactly like an entrance. Measured on a 60fps capture of the wallpaper selector
against a control pair of frames differing by 0.0000, the panel's drawn bottom
edge went from off screen to 99.6% of its final position in ONE frame — 690px in
17ms — for the whole life of the feature, while its exit (whose write has no
deferred partner) animated correctly. The asymmetry read as a broken exit rather
than as a missing entrance, and the first repair fixed the exit's curve.

Declare the start state instead of writing it: `property real openProgress: 0`,
or `scale: 0.85` as `DesktopMenu` and `EditWidgetMenu` already spell it. A
declared initial value is not a write, so no Behavior swallows it.
`tests/lint_animated_start_write.py` fails the suite on a body that writes an
animated property and also defers a write to the same one; it is scoped to that
combination because two writes alone are ordinarily an if/else.
(fix(wallpapers): the selector arrives and dissolves instead of flying.)

**And the tier a surface takes is a claim about what KIND of surface it is.**
The wallpaper selector travelled its own full height on `sidebarSlideEnter` /
`sidebarSlideExit`. Those exist for a sidebar — a panel fastened to a screen
edge, whose travel IS its own extent, so a full-extent slide reads as the panel
coming out of the edge it lives on. The selector is a floating sheet with a
margin on all four sides, and moving it 690px in 250ms is the largest single
motion in this shell on the surface with the most content in it. It arrives in
place now (opacity and a scale from 0.85 on one scalar,
`transformOrigin: Item.Top`), which is `docs/M3_GUIDELINES.md` §2's Component
Entrance and Exit and what §2.1 of the survey measured: zero displacement on
every frame of the entrance.

Two decisions from that worth not re-deriving. **A surface's lifetime belongs to
its exit animation, never to a Timer at the exit tier's duration** — a Behavior's
animation starts a frame after the write that triggers it, and an accelerating
curve carries most of its distance in its last frames, so the old Timer tore the
window down with 14% of the exit still undrawn. That also forces the animations
to be *started* rather than declarative, since a `Behavior` never raises
`finished` at any duration. And **`elementMoveExit` is the wrong tier for a fade
in place**: `emphasizedAccel` is shaped for something leaving the screen, and at
its own 200ms it spends 46% of the transition in its last two frames — measured
on an opacity, a panel that sits above 45% for two thirds of the exit and then
blinks out (14, 23, 57, 100 percent gone across the last four frames).
`elementMoveFast` at the same 200ms measured 100, 95, 76, 55, 34, 18, 9, 1.
Where the exit is really an opacity with a scale nudge on it, the effects tier is
the honest one — which is also what §"Expandable Content" of the guidelines
already pairs with a spatial exit.
(fix(wallpapers): the selector arrives and dissolves instead of flying.)

**Two decisions that are each correct can add up to a surface that cannot animate at all, and neither
one is where you would look.** The overview appeared and vanished on a single frame at both ends.
`rules.lua` turns the compositor's own map animation off for `quickshell:overview` - which is right,
because a map animation on a screen-sized surface animates the *surface*, and that reads as the
desktop lurching rather than as a card opening - and the window's `visible` followed
`GlobalStates.overviewOpen`, which is how nearly every panel here is written. Layer-shell forbids
window reuse, so between the two the window was created on the frame the flag rose and destroyed on
the frame it fell, and there was nothing left that *could* animate either end. The repair is the
wallpaper selector's `reallyOpen` shape above; it is now written twice, so it is pinned rather than
described - `tests/test_exit_owned_surface_contract.py` holds both sites to it.

Four things from it worth not re-deriving:

- **Everything else gated on the open flag has to move onto the lifetime flag too, or the exit is
  half a panel leaving.** The overview grid's `Loader.active` read `GlobalStates.overviewOpen`, so
  the grid was destroyed on frame one of the exit and the search bar dissolved on its own. Gating on
  the gesture's flag inside the surface is invisible until the surface outlives the gesture.
- **A blur region is not part of the card it sits behind.** The compositor frosts that rectangle
  whether or not anything is drawn over it, so a region gated on the open flag arrives a whole
  entrance before the card and stays a whole exit after it - a frosted ghost of a card that is not
  there. A region is on or off and cannot be faded, so the step goes where the card is the least
  transparent thing it can be while it happens: the half way point of the card's own opacity.
- **The card does not travel, and that is geometry rather than taste.** The sibling fork drops this
  card in from above the screen edge and pays for the room with a negative margin on all four sides
  of its surface; ours is anchored to the top of a surface that stops at the bar's exclusive zone, so
  a rise is drawn outside the window and clipped - the same constraint the selector's entry states
  from the other end. `transformOrigin: Item.Top` says which edge the card comes out of without
  needing the room. The entrance takes `elementMoveSmall` for its CURVE as well as its duration:
  `expressiveFastSpatial` overshoots by construction (its second control point is 1.67), so the
  bounce is the scale settling past 1 - and the overshoot is clamped off the opacity, where a card
  fading past opaque and back is a flicker.
- **The lifetime is measurable without looking at a single pixel, and it needs a control in the same
  run.** `hyprctl layers` polled straight after a close: `quickshell:overview` survives **196-202ms**
  across three runs, against `elementMoveFast`'s own 200ms, while `quickshell:sidebarRight` - whose
  surface still follows its flag - is gone in **4-5ms**, which is the instrument's floor. On its own
  200ms is a number that could be sampling lag; with the second one it is the exit animation.

And the check's own first draft walked past the plant it exists for, which is the reusable half:
it swept the whole file for a `visible:` line mentioning `reallyOpen`, and putting the *window* back
on the gesture flag leaves the card inside it still matching. A gate is read at the declaration that
maps the surface - located by the `WlrLayershell.namespace` under it - never anywhere in the file.
c837f589e ("feat(overview): the overview arrives and dissolves instead of snapping"),
3e2143eae ("fix(test): read the surface gate at the declaration that maps it").

A delegate cannot see its siblings, so `Carousel`'s rank stays the model index — the clamp and the
scaled step still come from the policy, which was the half that was wrong. And a wave is a
**cancellable** list rather than loose animations: `expanded` flipping twice inside the first wave's
own length used to leave it running, because the collapse created a fade to 0 per child without
stopping the entrances, so a child still sitting in its `PauseAnimation` faded back *in* onto a
panel that had already closed — and its spent object was never destroyed, because `stop()` does not
raise `finished`. The survey this came from proposes a third fix, "store the stagger in the model
row so a recycled delegate keeps its place"; that one **does not apply here** and was not written —
our staggered surfaces are `FlowButtonGroup`s whose contents are fixed for the life of the card that
owns them, and a Docker refresh destroys the whole `ExpandablePanel` rather than recycling anything
under it. fb92b4f5d ("fix(widgets): rank a stagger by visible position, clamp it, and let a wave be
cancelled").

**...and the RUNNER is one component too, because the policy being shared is not the same as the
wave being shared.** `modules/common/widgets/StaggerWave.qml` owns the ranking, the zeroing, the
scaling and the cancellation; `ExpandablePanel` declares one rather than carrying the only copy, and
so does every surface that has adopted a group entrance since. It is a `QtObject`, not an `Item`: a
wave declared inside the container it walks must not become a member of it, and only Items land in
`children` (its animation `Component` is a declared property for the `QtObject`-has-no-`data` reason
under [Dynamic/data-driven QML gotchas](#dynamicdata-driven-qml-gotchas)). A member opts in by
declaring `property real appear: 1` and folding it into its own opacity — `RippleButton` has done
that since the stagger was written, which is why the session screen's nine buttons needed no change
at all. `step` and `leadIn` arrive in BASE milliseconds and are scaled inside, once: handing either
an already-scaled `Appearance.animation.*.duration` applies the multiplier twice. `leadIn` is a
GUESS at when the container has arrived, and an adopter whose container animates on a scalar QML can
read should gate on that instead and pass no lead-in at all — Edit Mode's drawer is the one that
can, and its entry above (`GlobalStates.editDrawerProgress` through
`Appearance.animation.contentsArrived`) says what that costs and buys.
`park()` is the entrance's start state, called both by the runner's own wait for an unmapped
container and by an adopter that learns its gesture has begun before it learns its container has
arrived.
("feat(widgets): StaggerWave, the one runner for a group's arrival";
"feat(editMode): the drawer arrives as a surface and then fills").

**A wave asked for while its container is off screen writes nothing, and leaves the surface blank
for ever.** Ranking asks each member whether it is on screen, and `visible` is EFFECTIVE visibility
(see the `GroupedList` entry under
[Dynamic/data-driven QML gotchas](#dynamicdata-driven-qml-gotchas)) — so a container that is not
mapped yet answers `false` for every member, every rank comes back `-1`, the wave is empty, and the
members keep whatever `appear` the last exit left them at, which is zero. Nothing errors, nothing
logs, and the QML reads correctly. That is precisely what a trigger hung on the state that *asks*
for a panel produces: `GlobalStates.sidebarRightOpen` flips a beat before the compositor maps the
layer surface, and four consecutive opens of the right sidebar came up as an empty panel body
(measured with a temporary print: `included=[false x7]`). `StaggerWave` therefore holds an entrance
until its target is visible rather than trusting whatever announced the open — in the runner, not at
the call site, because the next adopter has the same beat to get wrong and the same silence to debug.
A surface whose trigger is already the container's own `visible` (`ContentPage`, which follows the
settings window's page switch) never showed it.
("fix(widgets): a wave waits for its container to be on screen").

**The adoption is the thing that decays, so the adoption is what is pinned.**
`docs/p3drovfx-motion-measured-2026-08-22.md` §4.2 measured the sibling fork's motion off screen and
found our arithmetic correct, our guideline written, and the wiring at **three** files against their
twenty — a missing capability nowhere, and every surface arriving all at once because nothing asked
it not to. `tests/test_motion_policy_contract.py` now carries a `STAGGER_ADOPTERS` ratchet (a
surface that stops declaring a `StaggerWave` reddens; a new adopter is a line) and fails the suite on
a second file calling `staggerRanks`, which is the only way a second runner can exist. Two surfaces
were assessed and deliberately **not** taken, and the reasoning is the reusable part: the launcher's
results are a list the user is about to type into and that rebuilds on every keystroke, so a wave
there is latency on the one thing being waited for and restarts before it finishes; and the bar
popups' content wants the container-progress gate (§5.1 item 2) rather than a lead-in — its card
unrolls from the height of its first drawn section precisely so that section is legible on frame
one, and its content is reparented between windows with a stale implicit size for a frame.
("test(motion): ratchet the surfaces that stagger, and scope the rank check").

**...and that ratchet needed a second half, because a surface can be adopted, looked at, and
REFUSED — and a register that only grows is a target.** 9e10b8a9c ("feat(sidebar): the right
sidebar's sections arrive in sequence") gave the right sidebar a wave; the user's verdict was *"I
don't like the cascading animation effect in the sidebar… This one feels slow. There's a frame drop
the moment it opens and the moment it closes."* It is off that surface again, and
`STAGGER_DECLINED` in `tests/test_motion_policy_contract.py` reddens if it comes back. Take the
reasoning rather than the removal, because both halves of the complaint were right and only one of
them was the wave's:

- **A `leadIn` is a guess, and on a layer surface it is the only option there is** — which is why
  this surface could not be tuned out of the "feels slow" half. `staggerStep` is 40ms base,
  the sidebar's `leadIn` was `staggerStep * 3` = 120ms, each member fades over
  `elementMoveFast.duration` = 200ms, and `STAGGER_MAX_RANK` is 5. On the panel 9e10b8a9c measured
  (ranks `[0,-1,1,2,-1,3,4]`) the last member starts at 120 + 4×40 = 280ms and lands at 480ms;
  with all seven sections on screen the clamp puts it at 320ms and 520ms. `sidebarSlideEnter` is
  **300ms**. So the group finished arriving 180–220ms after the container had stopped moving, and
  the fix for that is `Appearance.animation.contentsArrived` — which needs a progress scalar the
  compositor's own slide does not give QML. Edit Mode's drawer is the adopter that has one; this
  one never could.
- **The frame drop is NOT the wave, and it is not any of the three obvious suspects.** Measured in
  a nested Hyprland (1920x1080@60, its own `XDG_RUNTIME_DIR`), 12 open/close cycles per run, three
  runs of the wave-removed build as a control against two of the wave build, scored off
  `QSG_RENDER_TIMING`'s own per-frame numbers plus a 1ms heartbeat measuring how long the GUI
  thread was unavailable. **`polish` is 0ms in all 36 control gestures, IQR 0–0**, so the GUI
  thread does no measurable work at either end: it is blocked in `polishAndSync` for a median of
  69.5/76/78ms per open (IQR 66.5–72, 74.5–78.5, 76–84) waiting for the render thread, which is
  waiting on the compositor. What it is waiting for is the surface: `quickshell:sidebarRight`
  appears and disappears from `hyprctl layers` **24 times over 12 cycles**, because
  `PanelWindow.visible` follows `GlobalStates.sidebarRightOpen` and layer-shell forbids window
  reuse — the same teardown-and-rebuild the `hideWhenFullscreen` note under
  [Layer-shell gotchas](#layer-shell-wlr-layer-shell-gotchas) records. It costs that with the wave
  and without it.
- **What the wave added was FRAMES, not a longer block.** Per open, rendered frames go from a
  median of 5 (IQR 5–5 in every control run) to 30, at unchanged per-frame render cost (median
  15–16.5ms in both arms), and the blocked total stays inside the control's own band (79/72ms
  against 69.5–78). Per close the control renders **zero** frames — the surface is gone the same
  frame — while the wave renders a median of 13, every one of them with `render=0`: the exit fade
  keeps the window committing frames for 200ms after the panel has been asked to close, drawing
  nothing. A wave on a surface whose container is torn down by the same gesture is animating
  something that is already leaving.
- **The two cheap suspects are eliminated with numbers rather than by argument.** `StaggerWave`'s
  per-member `createObject`/`destroy` pair costs **55µs** for five members and **80µs** for seven
  (offscreen `qml6`, 2000 repetitions, against a control pass running the same loop without the
  objects) — 1.3% of one frame at 240Hz — and it would show up in `polish`, which is zero. And
  `mediaPlayerLoader`, whose `active` is bound to the open state, never fires for the reporter at
  all: `sidebar.mediaPlayer` is off in their config.
- **Which of the surfaces that still stagger share the mechanism**: `ContentPage` and
  `ExpandablePanel` have no window of their own, and `EditModeDrawer`'s surface exists for the
  length of the mode rather than per drawer open. `SessionScreen` does — it is a `PanelWindow`
  whose `visible` follows its `LazyLoader`, so its wave rides a surface the same gesture creates.
  That is unmeasured here and is a modal opened rarely rather than a panel opened all day, so it
  is named, not changed.

What generalises past the sidebar: **`polish` is where a group entrance's own cost would appear,
and if it is zero the stall is the surface, not the QML.** Before attributing a hitch at a panel's
edge to whatever animation was most recently added there, take one control run with that animation
removed and read `polish` against `blockedForSync`. Two limits of what was measured, stated because
neither is closed: the nested compositor's vsync period is 16.7ms against the reporter's 4.17ms, so
the absolute milliseconds are inflated and only the arm-against-arm comparison carries; and
Hyprland publishes no per-frame present statistics, so the compositor's own timeline — the thing
the user is actually looking at — is inferred from the client's stall rather than observed.
7a7c1b794 ("revert(sidebar): the right sidebar's sections stop cascading"),
1b8d4ac52 ("test(motion): the stagger ratchet runs in both directions").

**...and that stall was then fixed, by the thing the measurement above pointed at and not by the
three things that were bisected first.** After the wave was gone the user reported *"a momentary
freeze right before they open"* and attributed it to the wave. Four trees were bisected on the live
session — before the wave, the wave, the revert, main — and every one stalled; the recorder was
turned off and it stalled; the machine was rebooted and it stalled. None of that was wasted, but all
of it was the wrong instrument: `QSG_RENDER_TIMING` on the real session said it in one line,
`blockedForSync=61 ms, polish=0` on the frame the sidebar's window was created. The shell has ONE
GUI thread for every window it owns, and that thread waits while a new window gets its render
thread, its GL context, its scene graph built from nothing and every glyph uploaded again — so the
bar, the dock and the desktop all freeze for fifteen frames at 240Hz, right before the panel
appears. The compositor's own main loop never stalled (probed at 2ms through its socket: max reply
gap 1.3ms), which is why it read as the shell's freeze and not the screen's.

The fix is the one the `visible: false` note under [Layer-shell gotchas](#layer-shell-wlr-layer-shell-gotchas)
already prescribes for the background: **keep the surface mapped and move the panel.**
`modules/common/widgets/EdgeSlide.qml` is the runner; both sidebars declare one; the compositor's
`animation = slide` rules became `no_anim`; and the `sidebarSlideEnter`/`Exit` tiers were re-pinned
to what those rules had been drawing (400ms on `pc_decel`/`pc_accel`, the first kept as
`panelSlideDecel`) so the motion did not change, only who draws it. Measured live with the same
instrument: 18ms on the first open after a restart (textures), 1–4ms after. Captured at 60fps with
the user's permission and read per frame, the panel enters with its content already laid out and the
frost under it, nothing ahead of it.

Three things a persistent surface costs that an unmapped one never did, and the test that holds them
(`tests/test_persistent_sidebar_contract.py`, read at the `PanelWindow` that carries the namespace):

- **An ungated `mask` on a mapped surface eats every click on the screen edge it occupies**, and
  the left sidebar had shipped with exactly that mask for as long as it existed — harmless only
  because the window was unmapped when closed. Both masks read the open flag now.
- **An unconditional `keyboardFocus: OnDemand` on a mapped surface holds the keyboard while
  showing nothing.** Same file, same history, same gate.
- **Content hides on the runner's `shown`, never on the open flag** — the flag drops on frame one
  of a 400ms exit. And the slide is an `x`, not a transform: the blur region and the shadow both
  follow the item's geometry, and a transform moves neither.

Two generalisations. A Top-layer surface is buried under a fullscreen window by Hyprland itself
(the bar relies on it), so a persistent Top-layer panel needs no stand-down and does not hold the
fullscreen fast path the way an Overlay one does — check `solitaryBlockedBy` rather than assuming
either way. The overview went persistent too — its window declares no `visible:` at all and
`reallyOpen` gates the card instead (`tests/test_exit_owned_surface_contract.py` carries the
per-surface mode). Persistence brought the two focus obligations with it, both taken from the
sidebars: the grab is deferred two rendered frames past the flag flip, and the open names a focus
target (`searchWidget.focusSearchInput()`), because a window created once at boot never gets a
map-time keyboard grant. A third obligation lives in `services/GlobalFocusGrab.qml` and is global:
the grab's whitelist must end with the dismissables — Hyprland hands the grab's keyboard focus to
a surface picked from the END of the list, and with the bar/OSK after the panel, an opening panel
never activates and every keypress is silently dropped (the persistent-sidebar contract pins the
order; fix(sidebars): route the focus grab's keyboard to the opening panel). `SessionScreen` still
maps per open and pays this same 61ms.
(feat(widgets): EdgeSlide, the runner for a panel whose surface stays mapped;
fix(sidebar): the right sidebar's surface outlives the gesture;
fix(sidebar): the left sidebar's surface outlives the gesture;
perf(overview): keep the surface mapped; only the card opens and closes.)

**`Behavior on <non-animatable>` with a trailing bare `PropertyAction {}` defers a write instead of
animating it.** A `Loader.source` is a `url`, which QML cannot interpolate, so the `Behavior` cannot
animate it — and the *bare* `PropertyAction` (no `target`, no `property`, no `value`) means "apply
the pending write here". That is how `modules/imi/onScreenDisplay/OnScreenDisplay.qml` lets the
outgoing indicator leave before its replacement is built, with no pending-value field, no state
machine, and no pair of `Timer`s whose intervals have to keep agreeing with two animations'
durations. The construct is **not new to this tree** — `modules/common/widgets/StyledText.qml` has
carried a `Behavior on text` ending in one since it came from end-4, switched on at ~20 call sites
by `animateChange: true`.

Three things to know before reaching for it. Measured with a `qml6` probe: the **initial** write is
still applied immediately, because a `Behavior` does not fire before its component is finalized — so
a surface that is opening does not wait for a fade of nothing. Naming the action's `target` and
`property` instead of leaving it bare *looks* equivalent and is a hand-written re-derivation of what
the bare form takes from the `Behavior` it sits in, so a rename makes it match nothing with no
warning (`modules/imi/bar/Media.qml` and `modules/imi/sidebarLeft/SidebarPlayerControl.qml` both
spell it that way). And it is pinned from both sides, because the failure direction is bad — a bare
form that stopped being honoured would leave the pending write *never* applied, i.e. the OSD showing
the indicator the user navigated away from, with nothing in any log:
`tests/tst_deferred_property_swap.qml` pins the construct against Qt itself and
`tests/test_osd_indicator_swap.py` pins that the call site still uses it.
f968a55c4 ("feat(osd): let the outgoing indicator leave before its replacement arrives").

**The sidebar's bottom widget group has a fixed height, and that is load-bearing.**
`BottomWidgetGroup.qml`'s `expandedHeight` is a constant (352) rather than a binding on its
content, because the group and the notification list share the sidebar column: every pixel the
group grows is a pixel the notification list loses. Making it content-sized (`Math.max(350,
tabStack.implicitHeight + ...)`) looks like a harmless fix for the calendar being clipped, but it
silently hands ~36px of the notification list to the calendar, and once the group is above the
floor no amount of tightening the calendar's own spacing changes anything visible - the number
just moves around above the threshold. Size the *tab* to the budget instead. The calendar's
`dayCellSize` (36), `CalendarHeaderButton.implicitHeight` (32), the column's `space75` gaps and
`contentPadding` (`space150`) are chosen together so the total is exactly 350 inside 352.

`CalendarWidget`'s column is top-anchored at `contentPadding`, not `anchors.centerIn: parent`. The
parent is stretched to the group's fixed height, so centring drifts the header row down by half
the leftover space and knocks the month pill and the ‹ › buttons off the navigation rail's collapse
button. The rail's `Layout.topMargin` and the calendar's `contentPadding` must stay equal, and the
header button and the rail button must stay the same height, or that shared centre line breaks.

Shared building blocks to reach for before writing something from scratch: `StyledText`,
`StyledComboBox`/`StyledComboBoxSearch`, `StyledSlider`, `StyledToolTip`/`StyledToolTipContent`,
`RippleButton`, `MaterialSymbol`, `ResourceCard`, `GroupedList` + `ConfigSwitch`/`ConfigSpinBox`/
`ConfigSelectionArray`/`ConfigComboBox`/`ConfigTextArea` (settings rows), `StyledPopup` (a bar
widget's hover popup: a declaration plus a hover state machine, *not* a window - its content is
hosted on `modules/imi/bar/BarPopupOverlay.qml`'s shared card, b22a923a5 ("refactor(bar): delete
the per-popup layer surface")), `StyledRectangularShadow`, `DockIconMotion` (wraps a dock icon's visuals with hover-lift /
press-squish / launch-bounce / appear-pop feedback, driven by `services/DockLaunchTracker`; the
lift and the bounce are magnitudes travelling along `dock_geometry.js`'s inward vector, not a
negative y),
`ToolbarTextField` (the shell's text field: a filled pill, from the launcher's search box to the
lock screen's password box - see the note above on why `MaterialTextField` is not this),
`PasswordField` (that field masked: the shell's ONE password prompt, drawing a Material shape per
character through `PasswordChars` - reach for this rather than an `echoMode`, and read the entry
above before adding a third call site),
`SchemePaletteCircle` (an Android 12-style palette circle for a colour scheme, fed from
`services/SchemePreview`, with the scheme's glyph as the fallback while the colour venv has not
answered),
`MarqueeText` (a single-line label that scrolls only while it overflows its box, over the overflow
and back, at a distance-proportional speed with a floor — see the entry below before adopting one),
`CatalogueRow` (one entry of a catalogue, drawn — see the entry below before building a list row).
All in `modules/common/widgets/`.

**A catalogue's rows are one component, and it is deliberately not a control.** Edit Mode's drawer,
every settings row and the widget store's cards all draw the same thing — a leading icon, a name, a
description under it, and an affordance saying what acting on the entry does — and each had spelled
it out for itself: the drawer five times over (desktop widgets, bar widgets, dock apps, the lock
islands, the lock layout row), `ConfigSwitch` a sixth and the store card a seventh. They had drifted
in ways nobody chose: the same plugin's description wraps in one, elides in another and is absent
from the third, and the byline sits beside the title in the settings card and under it in the store's.
`modules/common/widgets/CatalogueRow.qml` is the one shape now, with the differences as properties
(`titleFillsWidth` and `titleElides` — two questions, not one, and folding them
together cost the store card the elide it has always had — `descriptionWraps`, the colours,
`rowSpacing`), four content slots (`titleContent`
on the title's own line, `trailingContent` before the affordance, `affordance` for the terminal
control, `detailContent` full-width beneath) and an `iconComponent` escape hatch for a leading visual
that is not a Material Symbol — a dock app's own icon — so the shared row never learns what a dock
app is.

Three things about it are not obvious.

- **It has no `MouseArea`, no `Button` root and no hover state, and it must not grow one.** Edit
  Mode's drawer rows are pointer areas BY CONSTRUCTION (65602708e): a drag out of the clipped drawer
  needs the implicit grab of the press to keep delivering events after the pointer leaves the row,
  and `test_edit_mode_contract.py` names the drawer as the deliberate exception to its no-`MouseArea`
  sweep for that reason. Every other call site is a `RippleButton`. So the interactive surface stays
  with the call site and this draws inside it — which is also why the affordance is a slot rather
  than a built-in control, and why `trailingContent` and `affordance` are two slots: `ConfigSwitch`
  owns the second (its switch) while still offering the first to its own 159 callers. The rule is a
  failing check, because the failure is silent — drag-to-place simply stops carrying anything out,
  on a gesture nothing in the suite drives.
- **The row's height is decided by its labels and its affordance, never by its leading glyph.** The
  icon sits in a wrapper reporting width only — `OptionalMaterialSymbol`'s own shape, kept rather
  than repaired, because every settings row in the shell was already sized that way and a
  decorative 23px store glyph would otherwise stretch a list whose text is 15px.
- **Both of its rows state `Layout.fillHeight`.** A Layout nested in a Layout defaults to `true`, so
  the main row and the (usually empty) detail row would SPLIT whatever height the row is given beyond
  its implicit one. That is invisible in a settings page, where the control's height IS its implicit
  height, and it is exactly what a fixed-height list row hands it — the same defect
  `EditModeDrawerLayoutProbe` exists for, one component down.

- **Every row body in the drawer is that component, checked per BODY rather than per file.** The
  first version of the check asked only whether `CatalogueRow` appeared in `EditModeDrawer.qml` at
  all, which is true of a drawer where five rows share it and a sixth is spelled out beside them —
  and that is precisely the state two branches arrive in when one extracts the component while the
  other grows a row. The Lock section's widget-choice re-link was written as a hand-rolled
  icon/label/label/glyph `RowLayout` on a branch that never saw the extraction, and a textual merge
  keeps it: one row in the drawer free to drift from the other six, in the file the extraction
  exists to keep from drifting. A row body here is a `contentItem:`, so the rule is that every
  `contentItem:` in that file names the shared row.

Adopting it must not move a settings row: 159 call sites, and a page that reflows is the failure.
Measured before and after against a real window under headless weston — `ConfigSwitch`'s
implicitHeight 31 / 44 / 62 / 44 for a plain row, an icon+wrapping-description row, an
info+trailing+byline+badge row and a disabled one, `contentItem.implicitHeight` 23 / 36 / 54 / 36,
and the disabled row still dimmed exactly once at 0.400.
("feat(widgets): CatalogueRow, the entry shape four surfaces each spelled out",
"refactor(widgets): ConfigSwitch draws its row through CatalogueRow",
"refactor(editMode): the drawer's five row shapes become one",
"refactor(store): a store card's identity is the shared catalogue row",
"test(editMode): hold every drawer row body to the shared catalogue row").

**A marquee is the answer for an IDENTITY, and where it may run is as much of the design as how it
moves.** `MarqueeText` exists because every long label in this shell elides, which is honest about
the truncation and useless about the content: a router that names its two bands and its guest
network off one prefix produces list rows whose elided forms are byte-identical, so the list offers
a choice it does not let the user make. It is *not* a general replacement for `elide`, and the four
call sites it has (the dock's window-preview title, and the SSID, Bluetooth device name and audio
stream name in the right sidebar) are a reviewed register in
`tests/test_marquee_text_contract.py` rather than a starting point for a sweep. Two questions have
to be answered before a fifth joins them, and neither is checkable from a pattern.

- **Is the elided string something the user cannot recover from anything else on that row?** A
  status line, a button label or a settings caption is a string this repo wrote; truncating one
  loses nothing. A name a device or a network advertises for itself is the whole of what the row
  is for.
- **Is the surface hidden when idle?** This is an animation with `loops: Animation.Infinite` on a
  label, i.e. exactly the class that took a fullscreen game from 94 fps to 52 — see the
  infinite-animation entry above. Its `running` is `overflows && visible`, and `visible` is
  effective visibility, which is the right question on the right sidebar (a `PanelWindow` whose
  `visible` follows the sidebar's open state) and on the dock's preview (an xdg-popup that does not
  exist while it is not shown). It is the *wrong* question on the bar, which sits on `WlrLayer.Top`
  and stays `visible` while a fullscreen window covers it (53d1ff893 ("fix(bar): drop the cava
  claim while a fullscreen window covers the bar")) — a marquee there is the performance bug
  wearing the fix's clothes, so it is refused by the register rather than by a comment.

Three things about its motion do not generalise from a tier and are pinned for that reason.

- **The duration is distance-proportional rather than catalogued** (`modules/common/functions/
  marquee.js`, 28ms per pixel of overflow with a 3500ms floor). What has to be held constant is the
  speed the text passes the eye: one tier would run a three-word overrun and a whole sentence on
  the same clock, so one of the two is unreadable. The floor is the same argument from the other
  end — a six-pixel overflow twitches, and a movement that resolves before it can be looked at is
  worse than the truncation.
- **The travel goes through `Appearance.animation.scale()` and the dwell at each end deliberately
  does not.** The travel is motion, so the speed slider retimes it and the reduce-motion floor
  collapses it to zero — which is a *snap* between the two ends, and is how reduce motion still
  leaves the whole string readable rather than permanently cut off. The dwell is reading time, and
  it is the half that keeps that floor from being a strobe: with the traverse at zero the dwell is
  the entire cycle, so a scaled dwell would swap a label's two ends every frame. `dwell()` takes
  `reduceMotion` and gets **longer**; getting that direction backwards is invisible from either
  constant on its own, which is why it is a test rather than a comment.
- **The curve is `Easing.Linear`, spelled out.** An eased scroll reads at a speed that changes
  under the eye, which is the whole thing a constant ms-per-pixel exists to hold still. This is a
  curve somebody chose, not the one `lint_motion_tier_partial.py` exists to catch nobody choosing.

Nothing about the rendered result is reachable from `qmltestrunner` — it can build neither a
`StyledText` nor a laid-out box — so every decision lives in `marquee.js` and
`tests/lint_infinite_animation_visibility.py`'s general gate rule is supplemented by the contract
above, which checks the term that lint cannot see (`overflows`) and refuses to let the widget join
that lint's ratchet.
62da34c1b ("feat(widgets): marquee.js, what a label that does not fit costs to read"),
d7e90dac8 ("feat(widgets): MarqueeText, a label that scrolls only when it overflows"),
91d7f5fab ("feat(sidebar): three names the right sidebar used to cut in half now scroll"),
281ca292c ("test(widgets): pin the marquee's gate, its two durations, and where it may run").

**A colour scheme is shown as its colours, not as a glyph.** The desktop menu's nine scheme
presets were nine abstract Material Symbols sitting directly above a list of transition
animations drawn the same way, so the grid read as more animations
([#142](https://github.com/XephyLon/immaterial-impulse/issues/142)). A preset's colours cannot be
known without running the quantize — that is what `SchemePreview` is for — so the glyph stays as
the fallback rather than as the design.
(782be8329 ("feat(desktopMenu): draw each scheme preset as the palette it produces").)

**`MaterialTextField`/`MaterialTextArea` are not "the shell's text field", and the name is the
whole trap.** Both set `Material.containerStyle: Material.Outlined`, so what they draw is QtQuick
Controls' own outlined container - a boxed border with the placeholder floating in a notch cut
through its top edge. Nothing else in this shell looks like that. Every field the user actually
meets is a filled surface: `ToolbarTextField` (a pill on `colLayer1`, used by the launcher's search
box, the wallpaper selector, the screen translator, the fps limiter - and by the lock screen's own
password box) or `ConfigTextArea`'s bordered field (the settings-row form control). The polkit
authentication dialog had reached for `MaterialTextField`, which meant the shell's **two password
prompts were two different controls**; `tests/test_polkit_dialog_contract.py` now derives the
control from `LockSurface` rather than naming a type, so the two cannot drift again. This is the
same failure shape as the `colLayer0`/`colLayer1` note below - "it uses a real shared widget" is not
"it uses the right shared widget for this position". The four remaining call sites are unreviewed
rather than sanctioned; `modules/imi/sidebarRight/wifiNetworks/WifiNetworkItem.qml` is the next one
of them that is a password prompt.
f957d9e59 ("fix(polkit): give the auth prompt the field the rest of the shell uses").

**...and the same two prompts then drifted again in the half a type name does not carry, which is
why the masking is a control now.** Both were `ToolbarTextField`s, so the check above was green,
and only one of them drew the shell's masked characters: the lock screen paints a `PasswordChars`
overlay - one `MaterialShape` per character, each animating in as it is typed - while the polkit
dialog set `echoMode: TextInput.Password` and got the system's flat bullets. Masking is not one
property, which is the whole reason a second call site gets it wrong: it is a transparent glyph
colour, a transparent selection PAIR, an overlay `Loader` anchored inside the field's own padding,
that overlay's `enabled: false`, and `Config.options.lock.materialShapeChars` gating all of it.
`modules/common/widgets/PasswordField.qml` is the one control that owns those five, and both
prompts are one. Two things about adopting it. The unmasked glyph colour has to stay a property
(`colText`) rather than being folded in - the lock screen's field sits on layer 1 and the dialog's
on layer 4, and it is still what the field falls back to when the switch is off. And `masked` is a
property rather than a constant, because a polkit flow may ask for a VISIBLE response
(`flow.responseVisible`), where a row of shapes standing in for characters the user is supposed to
read is worse than no masking at all. `tests/test_polkit_dialog_contract.py` derives the control
from the lock screen's own field (anchored on `root.passwordField = `, not on a masking property -
every one of those now names the shared file rather than the call site) and refuses a
`PasswordChars` instantiated anywhere outside `modules/common/widgets/`.
("feat(widgets): PasswordField, the masked field both password prompts share"),
("fix(polkit): the auth prompt draws the animated glyphs the lock screen has").

**A confirming action in a dialog carries a FILLED container; the dismissing one stays flat.**
`DialogButton` defaults to a fully transparent background (`transparentize(colLayer3)` with the
default 100%), which is right for Cancel and wrong for the button the dialog exists to offer - two
flat buttons side by side say nothing about which is which. Set `colBackground`/`colBackgroundHover`/
`colRipple` on the primary role and `colEnabled: colOnPrimary` (not `colText`, which is *bound* to
`enabled ? colEnabled : colDisabled` and would lose that binding to an assignment). No disabled
branch is needed: `RippleButton.buttonColor` already transparentizes the fill while `enabled` is
false. The reasoning is `EditModeChromeContent.qml`'s `doneButton` verbatim, arrived at from the
other end.
e8cd6bd04 ("fix(polkit): the confirming action carries a filled primary container").

**...and the other end of that pair is a rule the row derives, not something each Cancel
declares.** Filling the confirm answered "which of these two is what you came here to do" from one
side and left the other open: a bare label beside a filled container reads as a link rather than as
the second half of a choice, which is 283ada440 ("fix(editmode): the toolbar's title stops reading
as a button") arriving from the opposite direction - there the thing that was *not* pressable
looked like it was. **In a dialog whose confirming action is filled, the dismissing action is
outlined; a dialog whose actions are all flat stays flat.** `WindowDialogButtonRow` publishes
`hasFilledAction` (it is the smallest thing that can see both actions) and `DialogButton.outlined`
is derived from it, so the ten dialogs whose actions are all flat are untouched and the next dialog
that grows a filled confirm gets the edge without anyone remembering to. Four things about it:

- **"Filled" is read off `colBackground`, not declared.** The one thing a call site does to make a
  button the dialog's confirming action stays "give it a container". `colBackground` and never
  `buttonColor`, because the latter is transparentized while the button is disabled - a filled
  action would stop counting as one exactly while it waits for the response it submitted.
- **The predicate is `dialogActionFilled`, and the name is the load-bearing part.** The row asks
  every child duck-typed - it has to, since an action row holds spacers, captions and switches as
  well as buttons - so a name another widget answers to is a false positive with a border on it.
  `ConfigTextArea` declares `property bool filled: true` as its own filled-vs-outlined switch, and
  the first spelling of this collided with it: planted, a `ConfigTextArea` in an all-flat action row
  outlined **both** of that row's buttons. Anything else asking a heterogeneous row a duck-typed
  question has the same name to choose.
- **The edge is `colOutline`, not the `colOutlineVariant` `RippleButton` defaults to.** Measured
  against the card's own `m3surfaceContainerHigh` fill, the variant stands off it by **32/255** and
  `colOutline` by **106** - and `docs/M3_GUIDELINES.md` §1 documents the variant as a *subtle*
  boundary, which is the thing that failed here. It is also the tone `WindowDialogSeparator` already
  draws in, so the card carries one outline colour rather than two. A source check for that role
  cannot be a substring test: `colOutlineVariant` **contains** `colOutline`, so the first draft of
  the check passed on the exact token it exists to refuse.
- **The gap between the actions is measured between DRAWN edges.** The row was `space50` (4), M3
  asks for 8, and 4 read fine while the dismissing action was a bare label: the filled OK's
  container sat 4px from Cancel's invisible box and **20px** from the nearest pixel Cancel painted,
  its label. An outline moves that edge out by the button's own 16px padding, so the separation
  collapses to the row's spacing alone. `space100` now, re-measured at 8/24.
- **A call site may not spell the rule for itself.** `tests/test_polkit_dialog_contract.py` refuses
  an `outlined:` outside `modules/common/widgets/` - a rule re-stated per Cancel is a rule the
  fourteenth Cancel gets wrong - and asserts it found DialogButton call sites first.

04f66b498 ("feat(widgets): a dialog's dismissing action carries an outline"),
9803a7734 ("fix(widgets): a dialog's two actions sit 8dp apart"),
3ce984a99 ("test(polkit): the outline-role check stops passing on the role it refuses"),
70a6beec5 ("fix(widgets): the filled-action predicate gets a name no other widget answers to").

**A dialog's content padding is a spacing decision now, and it used to be its corner radius.**
`WindowDialog` spelled the padding twice and both times as `dialogBackground.radius`: the content
column took `margins: dialogBackground.radius`, and the card derived `implicitHeight:
contentColumn.implicitHeight + dialogBackground.radius * 2`. So the padding was 23px because
`Appearance.rounding.large` is 23 - restyling the corner restyled the padding, and changing one of
the two spellings without the other leaves the card a different height from what is in it (planted:
the harness's four-paddings check reads 32/32/32/**14**). There is one `WindowDialog.contentPadding`
now and both come off it. Three things:

- **Everything that BLEEDS had the same coupling from the other side.** `WindowDialogSeparator` and
  eight call sites across the Wi-Fi, Bluetooth, Tailscale, Phone Connect and Volume dialogs cancel
  that padding with `Layout.leftMargin: -Appearance.rounding.large` so a rule or a list reaches the
  card's edge - which is only true for as long as the radius and the padding happen to be equal.
  The content column publishes `contentPadding` for its direct children; `VolumeDialogContent` is a
  grandchild and takes it as a **required** property, so a missing wiring there is loud rather than
  a list that quietly stops bleeding.
- **The value is `Appearance.spacing.space400` (32), one step ABOVE M3's 24dp basic-dialog padding,
  deliberately.** The maintainer asked for more room; `space300` is a *one pixel* change from the 23
  it replaces and would not read as anything. Do not "correct" it back to M3's number - the property
  says so in place.
- **The check is the drawn inset against the token**, not against itself. The four-paddings check
  beside it is satisfied by any number applied consistently, the old radius included.

4fb2a7f02 ("refactor(widgets): a dialog's content padding gets a name of its own"),
1cb34eaa8 ("fix(widgets): a dialog's card pads its content on the 8dp grid").

**`WindowDialog` freezes its card's height at the moment `show` flips, and that is load-bearing for
how a dialog is built.** `onShowChanged` *assigns* `dialogBackground.implicitHeight`, which destroys
the binding to `contentColumn.implicitHeight` - so the card is whatever the content measured at that
instant, for the rest of its life. Note what this is NOT: wrapping is fine at completion, because
`dialogBackground.implicitWidth` is the caller's `backgroundWidth` constant rather than anything
derived from the surface, so a `StyledText` already knows its width and its wrapped height when
`show` flips. Measured - a three-line paragraph declared inline sizes its card correctly. What
breaks is content that arrives or changes *after* that: measured with a probe that assigned the
polkit message once the dialog was already up, the card stayed at the one-line height and the button
row drew 21px BELOW its bottom edge, on the scrim. It is not a live defect, because every dialog
here is built by a `Loader` whose gate is the thing that supplies the content
(`PolkitService.active`, `PluginManager.pendingUninstallId`), so the text exists before the component
does. Anything that wants a dialog to *grow* - a message that changes mid-flow, a field that appears
on a second step - has to repair the binding rather than assume it resizes.
15541101a ("fix(polkit): the dialog's own numbers come off the grid the rest of it uses").

**A dialog's action row is the one child of its content column that used to leave it, and where the
bleed shows depends entirely on what is above it.** `WindowDialogButtonRow` carried
`Layout.margins: -Appearance.spacing.space100` with a comment calling the alternative "a terrible
waste of space" - 8px pulled off three sides of the row, so the actions sat 8px outside the box
every other row in the dialog lines up with. Nine dialogs draw that row and eight of them put text
or a list above it, where a button container hanging 8px wider reads as nothing at all; the polkit
prompt is the one with a FULL-WIDTH field directly over the actions, and there it is a visible
misalignment. Measured on the real prompt in `PolkitDialogRuntimeTest.qml`: the card's four
paddings read 23/23/23/**15**, and the confirming button's right edge sat 8px past the password
field's. The margins are gone; the row is a plain `RowLayout` with the shared button spacing, and
the harness scores the four paddings against each other and the row's edges against the field's
rather than against numbers someone typed. Note which half of the geometry the source shows: that
the row is a `Layout` child of the content column is visible, that it leaves the column is not.
("fix(widgets): a dialog's actions sit in the dialog's own content box").

**The polkit prompt's LAYER surface is out of reach from any harness, and it is worth knowing
before writing one.** `FullscreenPolkitWindow`'s gate is `PolkitService.active`, a read-only alias
onto Quickshell's `PolkitAgent`, and the only thing that raises it is a real authentication
request - which needs the agent registered, and `polkit_agent_listener_register` refuses a second
agent for a session that already has one ("An authentication agent already exists for the given
subject", measured against the running shell). So a harness can build the dialog's CONTENT tree in
a window of its own - which is what `PolkitDialogRuntimeTest.qml` does, and it reaches the layout,
the hover feedback and the masked glyphs - and can say nothing about the surface's input region,
its layer or its keyboard focus. A nested Hyprland does not help: driving it with
`hyprctl dispatch movecursor` delivered no pointer to the client at all, its own in-surface control
`MouseArea` reporting `containsMouse=false` throughout - the family of process-targeting and
input-synthesising traps under [Hyprland integration](#hyprland-integration), arriving in a new
place. That run says nothing about the surface either way, and a harness with no positive control
in it would have reported the silence as a finding.
("test(polkit): build the real prompt and read its layout, hover and glyphs back").

`ConfigTextArea` is the text-entry counterpart to `ConfigSwitch` (icon + label/description on the
left, a bordered `TextArea` field on the right) and is the standard single-line settings field -
prefer it over building a raw `TextField`/`TextArea` row by hand. Set `password: true` for masked
input - this draws the lockscreen's `PasswordChars` Material-shape dots over the field instead of
the native glyphs (`TextArea` has no `echoMode`, unlike `TextField`, so masking is done purely by
making the real glyphs transparent), and shows an optional reveal toggle (`revealButton`, defaults
to `password`). There used to be a separate pill-shaped `ConfigInput` for this; it was removed and
folded into `ConfigTextArea` once `ConfigTextArea` became the de facto standard across the settings
pages - don't reintroduce a second single-line text-entry widget.

`GroupedList` normally separates and subtly rounds each row. Set `cohesive: true` when several
controls form one continuous semantic unit (for example, the fields and actions for a single custom
AI provider). Cohesive mode removes internal spacing and corner rounding while retaining the outer
group corners. Controls rendered inside a group should rely on the group's inset; avoid adding a
second horizontal inset that misaligns their icons or labels with neighboring rows. **A row that
comes and goes declares `rowVisible`, never `visible`** — see the effective-visibility note under
[Dynamic/data-driven QML gotchas](#dynamicdata-driven-qml-gotchas) for the empty plate the second
spelling leaves behind and why the widget cannot repair it by mirroring `visible`.

**`colLayer0` vs `colLayer1`/`colLayer2`/...** - these are not interchangeable "just pick one that
looks transparent enough" tokens:
- `colLayer0`'s alpha comes from `backgroundTransparency` (gated by
  `Config.options.appearance.transparency.enable`, ~0.89 opacity by default) - use it for the
  **outermost** background of a standalone floating surface (a popup/toast/OSD that sits directly on
  a `PanelWindow { color: "transparent" }` with nothing else behind it). See `MediaControls.qml` and
  `OsdTextIndicator.qml`.
- `colLayer1` and above derive from `contentTransparency` (~0.43 default, also gated by the same
  `enable` toggle) and are meant for **cards nested inside an already-opaque parent surface** (e.g.
  a list item inside the sidebar, which itself already provides a `colLayer0` backing). Used at the
  top level of a standalone popup, this token's alpha is low enough to visibly show
  through-but-unblurred transparency without ever clearing the `ignore_alpha` threshold above.
