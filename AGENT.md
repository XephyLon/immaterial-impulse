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
  widgets/                   Shared UI components: StyledText, StyledComboBox, StyledSlider,
                              StyledToolTip(+Content), RippleButton, MaterialSymbol, ResourceCard,
                              PopupToolTip, StyledPopup, GroupedList, ConfigSwitch/ConfigSpinBox/
                              ConfigSelectionArray (settings-page form controls), DockIconMotion
                              (M3E feedback-motion wrapper for dock icons), SchemePaletteCircle
                              (a colour scheme drawn as its own palette), etc.
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
                              The widgets themselves are all bundled plugins now (see
                              modules/common/plugins/bundled/); background/widgets/ holds only
                              AbstractBackgroundWidget.qml, which is the plugin host's base class.
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
                              clipboard actions. Its parser logic is kept byte-for-byte in
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
                              background.clockDepth.enable or the picker is open. The `run` half is
                              reached ONLY from the wallpaper selector's picker; nothing reactive
                              can start segmentation
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
  background/subject_mask.py  Segments a wallpaper's subject through ONNX Runtime (isnet-anime or
                              isnet-general-use, fetched on first use, ~1.3-4.5s and ~1GB RSS per
                              run) and owns the mask cache in ${Directories.cache}/clock-depth. It
                              owns the CACHE KEY too - path/mtime/size - and the shell never
                              computes one, so an in-place wallpaper edit invalidates its mask, its
                              opt-out and its candidates together. `status` and `sweep` are
                              stdlib-only and load no model; `run` needs the uv venv
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
  resize grip with real mouse events").
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
    strip and requires a swap, then ACROSS it and requires none, with the horizontal edge first
    as the control — "nothing happened" is also what a harness that stopped delivering events
    reports. It reaches the dock's *content* tree only; weston implements no wlr-layer-shell, so
    anchors, the exclusive zone, the reveal push and the compositor's inferred slide are all
    invisible to it.
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
  password box uses the identical overlay structure but never hit this, since it
  `forceActiveFocus()`s itself programmatically instead of depending on a click.
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
(feat(background): draw the wallpaper's subject over the desktop widgets.)

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
returns the entire picture as the subject), so the stored mask is square while
the wallpaper is drawn `PreserveAspectCrop`. Filling both into the viewport
stretches them differently — by 3.5× on this monitor. `ClockDepthLogic.coverRect`
returns the rectangle the whole wallpaper would occupy if nothing clipped it; the
mask is `Image.Stretch`ed into that and the surface clips it back, which is
undoing the squash and re-applying the crop in one step. Kept as a pure function
in `modules/common/functions/clockDepth.js` beside the eligibility predicate for
the same reason `ParallaxMath.sampleOrigin` is: nothing about the rendered layer
is reachable from `qmltestrunner`, so the arithmetic has to be.
(feat(background): draw the wallpaper's subject over the desktop widgets.)

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
`SchemePaletteCircle` (an Android 12-style palette circle for a colour scheme, fed from
`services/SchemePreview`, with the scheme's glyph as the fallback while the colour venv has not
answered). All in `modules/common/widgets/`.

**A colour scheme is shown as its colours, not as a glyph.** The desktop menu's nine scheme
presets were nine abstract Material Symbols sitting directly above a list of transition
animations drawn the same way, so the grid read as more animations
([#142](https://github.com/XephyLon/immaterial-impulse/issues/142)). A preset's colours cannot be
known without running the quantize — that is what `SchemePreview` is for — so the glyph stays as
the fallback rather than as the design.
(782be8329 ("feat(desktopMenu): draw each scheme preset as the palette it produces").)

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
second horizontal inset that misaligns their icons or labels with neighboring rows.

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
