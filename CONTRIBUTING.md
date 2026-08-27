# CONTRIBUTING.md — for coding agents

This is a workflow guide for agents (Claude Code or similar) making changes in this repo. For what
the project *is* and how it's structured, read `AGENT.md` first.

**Both files are read sequentially, in full, top to bottom, before any work starts — and re-read
after a context compaction.** Grepping for the section that looks relevant is not reading; the
rules that get broken are the ones adjacent to the section someone jumped to. The regression that
made this a rule: 5d4bfa773 ("feat(wallpaperEngine): reinstate activeStill, this time with a
writer") — written by an agent that had both files available and the removal's issue one
`gh issue view` away.

## Hard rule: the `superpowers` skill system is required, not optional

Every agent working in this repo - Claude Code, Antigravity/`agy`, or otherwise - must have
`superpowers` installed and active before starting work. This is not a "use it if it happens to be
there" suggestion: **check for it first, and install it if it's missing**, before making any edits.

How to check:
- Claude Code: look for a `using-superpowers` entry in your available-skills listing, or a
  `Skill`/`skill` tool. If present, invoke it - see "Skill Priority" in its own instructions.
- Antigravity/`agy` (Gemini CLI-based): check `/skills` or for an `activate_skill` tool. This
  machine already has the extension at `~/.gemini/extensions/superpowers`; if your session doesn't
  see it, that's a signal to install/import it (see below), not to proceed without it.

How to install if it's missing:
- Claude Code: the marketplace is already added on this machine
  (`~/.claude/plugins/marketplaces/superpowers-marketplace`) - install with
  `/plugin install superpowers@superpowers-marketplace` (and `superpowers-chrome` if browser
  access is needed for the task).
- Antigravity/`agy`: `agy plugin import gemini` to pick up the existing
  `~/.gemini/extensions/superpowers` extension, or `agy plugin install superpowers@<marketplace>`
  if a marketplace source is configured. If neither works, say so explicitly rather than silently
  continuing without it.

Once active, don't skip straight to default behavior when a relevant skill exists - invoke it.
Skills particularly relevant to this repo:

- **`test-driven-development`** - use before writing implementation code for any feature or
  bugfix, and required reading before touching this repo's test suite (see `tests/` once it
  exists).
- **`using-git-worktrees`** / **`dispatching-parallel-agents`** / **`subagent-driven-development`**
  - directly applicable to the "Multi-agent / parallel workflows" section below; prefer these over
  ad hoc worktree/subagent handling if the skill is available.
- **`systematic-debugging`** - use before proposing a fix for any bug or unexpected behavior; pairs
  with this file's "Verify against the live shell" section below.
- **`verification-before-completion`** - run before claiming anything is fixed/complete/passing;
  the same evidence-before-assertions spirit as this file's live-verification loop.

If a skill's instructions and this file disagree, the more specific/current one wins - skills get
updated independently of this file, so don't assume this file has the last word if a skill exists
that covers the exact situation.

## Verify against the live shell, not just "no syntax errors"

There's no test suite and no compiler to catch mistakes — QML errors only surface at runtime, in
the log, when the affected component is actually reached. "The file saved without an Edit-tool
error" is not evidence a change works.

The reliable loop used throughout this project's history:

1. Make the edit.
2. Wait ~2-3s for the hot-reload, then check the log for new errors:
   ```bash
   LOG=/run/user/$(id -u)/quickshell/by-id/$(ls /run/user/$(id -u)/quickshell/by-id/ | head -1)/log.log
   tail -30 "$LOG" | grep -iE 'error|WARN scene'
   ```
   (`WARN scene: <file>[<line>]: ...` is a QML runtime error/warning with a precise location — treat
   these as real bugs to fix, not noise, unless you recognize them as pre-existing/unrelated.)
3. If the change is behavioral (not just visual), **drive the actual state change and read back a
   real value**, rather than reasoning about it in the abstract. This project's Hyprland/PipeWire
   integrations are full of "should be reactive" assumptions that turned out subtly wrong in
   practice (see the two examples below). A temporary `console.log` in an `onXChanged` handler,
   checked against `grep` on the log file, then removed once confirmed, is the standard technique:
   ```qml
   onSomePropertyChanged: console.log("[TempDebug] someProperty ->", someProperty)
   ```
   Always remove these before considering the change done — check with `git diff` that no stray
   `console.log`/`[TempDebug]`/similar markers are left in the final diff.
4. Don't stop at "the property changed" if the ask was about visible/clickable behavior — a property
   can be logically correct while the compositor still doesn't render or route input to it correctly
   (see the layer-shell gotchas in `AGENT.md`). When in doubt, ask the user to confirm the actual
   visual/interactive result before declaring it fixed.

Two real examples from this project's history that justify the paranoia:
- A gate (`if (!Audio.ready) return`) copied from a nearby, superficially similar handler silently
  ate every audio-device-switch toast, because the *new* device's `ready` flag lags the pointer
  swap by a tick. Nothing about this was visible from reading the code; only driving a real device
  switch and reading the log exposed it.
- A "fix" that made a bar clickable under fullscreen+special-workspace, verified via debug logging
  as "layer and mask both correct," still failed for an unrelated reason (a same-layer stacking
  conflict with a different widget) that only showed up once the user tried it for real.
- A new toast's background used `Appearance.colors.colLayer1` - a legitimate, correctly
  transparency-aware design token, chosen by reasonable-looking analogy to other cards in the
  codebase. It still rendered as flat unblurred transparency in practice, for two compounding
  reasons invisible from reading the QML alone: `contentTransparency` (which `colLayer1` derives
  from) wasn't gated on the `transparency.enable` toggle the way `backgroundTransparency` was, and
  even after fixing that, `colLayer1`'s alpha never cleared the Hyprland companion config's
  per-namespace `ignore_alpha` blur threshold the way `colLayer0` does. "Uses a real design token"
  is not the same as "uses the *right* design token for this position in the surface hierarchy" -
  see AGENT.md's `colLayer0` vs `colLayer1` note.
- A Hyprland window rule the shell registers at startup via `execDetached(["hyprctl", "eval", ...])`
  was "verified" by running the same `eval` chunk from a terminal and observing the window behave
  correctly. It did behave correctly - because of the manually-registered rule, which persists until
  the next `hyprctl reload`. The shell's own registration had never survived startup for even a
  second, since the shell reapplies the Hyprland theme (and thus reloads) moments after registering.
  **Reproducing an effect by hand is not verifying that the code produces it.** Clear the state the
  code is supposed to create, restart the thing that should create it, and read it back. Here that
  also revealed the registration was unnecessary: fixed size hints already floated the window.
- A commit claiming to have "migrated existing plugins to the new format" only moved the files into
  new subdirectories - it never actually renamed the JSON schema key their content used, so both
  bundled example plugins silently stopped rendering. **A commit message describing what a change
  did is not evidence it did that** - re-read the actual diff/file content against the claim,
  especially for rename/migration-style changes where "moved" and "renamed the thing inside" are
  easy to conflate. The unit tests here didn't catch it either, because they validated the schema
  function in isolation and never loaded the real bundled manifest files - a passing test suite is
  not the same as the real data path working.
- A brand-new feature (the plugin system: a new singleton, a new settings page, a new shared-widget
  property) merged cleanly, tests passed, and a disposable throwaway `qs -p <worktree>` instance
  even rendered it correctly during review - but the user's actual long-running `qs -c imi`
  process kept showing an empty page, because that process had been running since *before* the
  merge and a brand-new `pragma Singleton` file needs the process to actually restart to get
  registered, not just a hot-reload of edited files (see the Runtime model section of `AGENT.md`).
  Restarting it (`hyprctl dispatch 'hl.dsp.exec_cmd("killall ydotool qs quickshell; qs -c
  $qsConfig &")'` - see `~/.config/hypr/hyprland/keybinds.lua` for the canonical form) surfaced four
  more real, previously-invisible bugs in the same feature (a missing import, an async-API misuse, a
  `Repeater`/`required property` scoping mistake, and the missing widget property above) - all of
  which "worked" in the earlier disposable-instance test only because that instance was a fresh
  process to begin with. When verifying against the live shell, prefer restarting the actual running
  instance over trusting a separate disposable one, especially for anything involving a new
  singleton.

## Don't guess at `hyprctl` CLI syntax on this machine

This machine's Hyprland config uses a Lua binding layer, which changes what `hyprctl dispatch ...`
needs to look like when invoked manually from a shell (see `AGENT.md`). If a `hyprctl dispatch`
command errors with something mentioning Lua, don't retry variations blindly - work out the
`hl.dsp....(...)` form from the relevant `~/.config/hypr/hyprland/*.lua` file instead of guessing.
This only affects manual/CLI invocations for testing, not the QML code itself.

## Reuse before building new

Check `modules/common/widgets/` before writing a new UI primitive - tooltips, combo boxes, sliders,
form rows for the settings page, card/tile layouts, etc. almost all already exist there and are used
throughout `modules/imi/`. A fix or feature that touches a shared widget (e.g. `StyledComboBox`)
benefits every place that widget is used - that's usually preferable to a one-off local
implementation, but also means changes there have wider blast radius, so verify a couple of call
sites, not just the one you were asked about.

Pull visual values (colors, spacing, font sizes, animation curves) from `Appearance.qml` rather than
hardcoding. This is a Material 3 / Material 3 Expressive shell — match that language for new UI
(rounded containers, tonal color roles, expressive motion) rather than introducing a different look.

**Before using a property on a shared widget, grep the widget's actual source for it** rather than
assuming it exists because the name would make sense (e.g. assuming `ConfigSwitch` has a
`description` subtitle property because plenty of list-item patterns have one - it didn't, and the
assignment silently failed with "Cannot assign to non-existent property," not a load-time error).
This is the same failure shape as trusting a design token by "looks right" analogy (see the
`colLayer0`/`colLayer1` example above) - check the real property list, don't infer it.

**`ContentPage` (`modules/common/widgets/ContentPage.qml`) is already a `StyledFlickable` with its
own internal `ColumnLayout`** (its `default property` puts children into that layout automatically).
A settings page should declare its sections directly as `ContentPage`'s children - wrapping them in
another `Flickable`/`ColumnLayout` is redundant and causes a real bug: the inner Flickable ends up
managed by the outer layout, triggering "Detected anchors on an item that is managed by a layout"
and broken scroll/sizing behavior. Look at `GeneralConfig.qml`/`ServicesConfig.qml` for the plain
pattern before adding a new settings page.

## A missing thing is a decision until proven otherwise

Same family as the greps above: don't infer *why* something isn't there. If a field, function or file
is absent where you expected one, the removal has a commit and often an issue, and that reasoning is
a requirement you are about to work against.

`git log -S '<thing>' --all` for the removing commit, read the full message, and read any issue or PR
it cites in full — `gh issue view N`, not the title. Note that a number can be an **issue** rather than
a PR (`gh pr view 103` fails here; `gh issue view 103` is the one that matters). Only then decide. If
the reasoning still holds, your problem needs a different answer; if it doesn't, say so in the commit
message and handle whatever the removal was protecting against.

See [AGENT.md → Before you restore something that was removed](AGENT.md#before-you-restore-something-that-was-removed)
for the worked example: 5d4bfa773 ("feat(wallpaperEngine): reinstate activeStill, this time with a
writer") restored one config field without reading its issue, re-introduced the bug that issue was
filed for, and rebuilt a subprocess renderer the embedded one exists to replace.

## Settings additions are two-sided

A new persisted option needs both halves, or it silently does nothing:
1. The schema property in `Config.qml` (inside the correct nested `JsonObject`).
2. A corresponding row in the relevant `modules/imi/settings/pages/*.qml` file, wired with
   `checked`/`value`/`currentValue` reading from `Config.options....` and a handler writing back to
   it — but read both exceptions below before picking which handler.

**Exception — `ConfigSwitch` writes back from `onToggleRequested`, never `onCheckedChanged`.**
`checked` is a pure binding on the config value and only ever follows it; a click raises an intent
instead, and the call site flips the value at its source
(`onToggleRequested: Config.options.x.y = !Config.options.x.y`). The handler must not read the
widget's own `checked` to decide what to write — that is the coupling this removed. The old shape
(`onClicked: checked = !checked` in the widget, `onCheckedChanged` write-back at the call site)
destroyed the binding on the first click, so the switch detached from the config and then lied
about it for the rest of the session (#158). `tests/lint_config_switch_intent.py` fails the suite on
either half of it. See AGENT.md's Config section.

**Exception — `ConfigSpinBox` and `ConfigSlider` write back from `onValueModified`, not
`onValueChanged`.** Their `value` also changes when the control is merely built (QQC2 clamps it to
the declared `from`/`to` at component completion) and, for the slider, on every frame of its
smoothing animation. Hanging the write on `onValueChanged` means opening a settings page rewrites
the config — which is how a hand-set `osd.timeout: 4321` used to become `3000` with no user action.
Use the signal's `newValue` argument in the handler body. See AGENT.md's Config section and
`tests/test_config_control_write_back.py`, which fails the suite on any call site that regresses.

If a feature is gated by config (e.g. "always show X"), search for where the sibling options are
consumed (usually a `Resource`/similar component's `shown`/`visible` binding) and wire the new one
into every layout variant that repeats the pattern (this codebase often has near-duplicate blocks
for e.g. horizontal-bar vs vertical-bar vs "material style" variants of the same widget - grep for
the sibling property name to find all of them before considering the wiring complete).

Dynamic plugin state is the exception to the fixed `Config.qml` schema. Values keyed by runtime
plugin ids or monitor names must go through `modules/common/plugins/PluginState.qml`, which stores
raw JSON in `~/.config/immaterial-impulse/plugin-state.json`. Do not add undeclared children or a
dynamic `property var` object to a `JsonAdapter`; both forms have caused native crashes during
deserialization.

Plugin package structure, manifest entry points, installation, and permissions are documented in
`PLUGINS.md`. Keep the host generic: do not add plugin-id branches to `PluginWidget`, `PluginNode`,
or settings when a manifest component entry point can express the same behavior.

Never keep a streaming `Process` alive with a persistent `running` binding unless it implements
delayed backoff and a retry ceiling. An instant-exit command can otherwise become a tight respawn
loop and starve Quickshell. Prefer bounded polling; the bundled-plugin lifecycle lint enforces this
for known streaming commands.

## New features and bugfixes need tests

`tests/` (see `tests/README.md`) covers pure-logic code — singletons and functions that don't
require a live Hyprland/PipeWire session (color math, config schema defaults, device-name
selection logic, output parsers, etc.) via `qmltestrunner`. When you add a new feature or fix a
bug in anything that qualifies:

- **Add or extend a test that would have caught the bug**, or that exercises the new logic - not
  just a happy-path smoke test, but the actual edge case that was wrong or that the feature needs
  to keep working.
- **Run `./tests/run_tests.sh` before committing** and confirm it's green. A change that breaks an
  existing test is a regression, full stop - fix the change, don't loosen or delete the test to
  make it pass, unless the test itself was wrong (and if so, say so explicitly in the commit).
  **Start it whenever you are ready: do not check `ps` for a suite already running and do not
  stagger runs by hand.** The script takes an exclusive `flock` before its first runtime harness,
  says which checkout is ahead of it, and waits - the static half of the run overlaps freely and
  only the compositor harnesses queue. That used to be the caller's rule and callers forgot it;
  what it costs is `The Wayland connection broke. Did the Wayland compositor die?` in the losing
  run, which is what a real regression looks like too. See
  [AGENT.md → Running the suite while another agent is running one](AGENT.md#running-the-suite-while-another-agent-is-running-one)
  for the boundary, the release, and why `run_*_probe.sh` is not covered.
  8b5f04d6e ("test(suite): serialize a run's compositor harnesses behind one flock").
- **A green suite does not mean the shell loads.** The QML tests only instantiate pure-logic
  singletons, so any widget that fails to *compile* (a `FINAL` property override, a bad type name, a
  missing `import qs.modules.common`) passes every test while taking down every panel that reaches
  it. After touching any `.qml` under `modules/`, check the live log for `Configuration Loaded` and
  for `ERROR:` - not just `WARN` - before calling the change verified. See AGENT.md's "Where to look
  when something goes wrong" for the cascade format and the `pgrep -af 'qs -c imi'` caveat.
  `DesignSystemCompile.qml` (run by `run_tests.sh`, skipped without `WAYLAND_DISPLAY`) narrows this
  for the design system, the bundled packages, every settings page, the desktop-widget host
  (`PluginWidget.qml`, which only compiles once a plugin is enabled on some monitor) and both bars
  - it compiles them, so a bad property on a page nobody opened is caught. Everything else still
  needs the live load. 494580b65 ("feat(plugins): resolve a placed widget's span from its stored
  choice"). The vertical bar joined that list for the same reason the dock is on it: it is opt-in,
  so anything wrong with it stays green until someone switches it on - which is how the two bars
  came to resolve widget files differently in the first place. Note the limit the sweep has, which
  is easy to over-read: it proves a file *compiles*, and a missing `.js` import resolves at binding
  time rather than compile time, so it passes one. ("fix(verticalBar): render plugin bar widgets
  instead of an empty stub").
  The overview's window and `modules/common/widgets/VerticalTabBar.qml` are on that list for the
  same reason both bars are: a window built on every startup is found by a live load and by nothing
  else, and an agent working in a worktree has not got one. The two sidebars' own windows are
  deliberately NOT on it - a by-URL compile in a `qs -p` process resolves neither
  `SidebarLeftContent` nor `SidebarRightContent`, so adding them reports a failure belonging to the
  probe rather than to the file, and `tests/run_persistent_surface_focus_probe.sh` (a nested
  two-output Hyprland, run by hand) is what loads them for real.
  ("test(surfaces): the compile sweep reaches the overview's window and the tab bar").
  **It sweeps a bundled package through its `Widget.qml` only**, on the reasoning that a sibling
  file is a type resolved through the package's `qmldir` and so is reached from the entry point
  anyway. A file the entry point loads *by URL* is not that - it is a standalone component that
  compiles, or does not, on its own - so it has to be named in the explicit list or it compiles for
  the first time on the user's desktop. The media widget's three per-span layouts are the current
  case. 61e2f723c ("refactor(media): move the media widget's content into LayoutLarge").
- **A new Python check must actually run.** `run_tests.sh` invokes each one as `python3 <file>`, so
  a module of bare `test_*` functions exits zero without executing anything. Either subclass
  `unittest.TestCase` with `unittest.main()`, or end the file with the `contract_runner` block
  documented in `tests/README.md`. Confirm the new check fails when you break the thing it guards -
  three modules shipped as silent no-ops precisely because nobody checked that.
- **Prove a new static check can fail.** These checks match source text; a pattern with baked-in
  indentation passes vacuously after any reformat.
- **A runtime harness states how many checks it ran, and its driver asserts the number.** The
  verdict is `[Tag] checks: ${harness.checksRun} failures: ${harness.failures}`, with `checksRun`
  incremented inside the harness's own `check()`; the driver holds the expected count in a
  module-level `EXPECTED_CHECKS` (one per shape, where it launches the harness in more than one)
  and asserts the whole line. Neither half is optional: `failures: 0` is what a harness that ran
  *nothing* prints, so a loop that stops iterating or a step deleted from a list used to shrink
  the suite in silence — and a count read back out of the harness's own output would agree with
  itself by construction. The count must come from the counter rather than from a constant, or a
  harness that gives up half way still reports the full number.
  `tests/lint_harness_check_counts.py` fails the suite on either half.
  0b3a900f4 ("test(lint): fail on a harness verdict that states no check count").
- **Plant mutations only in a clean tree.** Proving a check can fail means planting a bad input and
  reverting it — and `git checkout -- <file>` reverts to HEAD, destroying every uncommitted edit in
  that file along with the mutation. That exact trap has fired three times in two days, most
  recently wiping the first draft of the doc rules themselves (01b07a731b8 ("docs: mechanize the
  agent-doc rules - sequential read, citations, receipts") is the second draft). Commit first — a
  `wip` commit is fine, the granular-history rule wants the journey anyway — or plant the mutation
  in a scratch copy. Never plant-and-revert in a file that holds uncommitted work.
- If the code you're touching depends on live compositor/audio state and genuinely can't be unit
  tested with the current harness (most `modules/imi/*` UI), that's fine - fall back to this file's
  "Verify against the live shell" workflow instead, but say so rather than silently skipping tests.
- CI (`.github/workflows/tests.yml`) runs this suite on every PR - a red check is a blocker, not a
  suggestion.

## Keep AGENT.md in sync

`AGENT.md` is the architecture reference agents read *before* touching this repo - it goes stale
the moment a change it describes lands without an update. If your change does any of the
following, update the relevant section of `AGENT.md` in the same PR/commit series:

- Adds, removes, or repurposes a directory, singleton, or service (the "Directory map" section).
- Changes how the Config system, Hyprland integration, or layer-shell behavior works (their
  respective sections) - not just adds a new leaf setting, but changes a mechanism.
- Introduces a new non-obvious gotcha future agents will hit (a new entry in the relevant gotchas
  list, in the style of the existing `colLayer0` vs `colLayer1` note).
- Adds or changes anything about the test suite (`tests/`) - keep `AGENT.md`'s description of it,
  and `tests/README.md`, matching what actually exists.

A feature that only adds a leaf-level setting or a new widget instance using existing patterns
usually doesn't need an `AGENT.md` update - use judgment, but when in doubt, a one-line addition to
the relevant section costs little and saves the next agent from re-discovering what you just
learned.

**Every PR body must carry a `Docs:` receipt line, and CI rejects PRs without one**
(`.github/workflows/docs-receipt.yml`). One of:

- `Docs: updated AGENT.md §<section>` (and/or `CONTRIBUTING.md`)
- `Docs: not needed — <reason>`

This exists because the judgment call above was silently skipped four PRs running — the HDR codec
work (307c8b4ae ("fix(record): pick the HDR codec when capturing an HDR monitor")) and the RUNPATH
repairs (156b4703b ("fix(install): repair the RUNPATH via a rename, not in place"), 3e07c2a5d
("fix(install): repair the bundled libraries' RUNPATH too, not just the binary")) all met the
"non-obvious gotcha" criterion and none updated `AGENT.md` at the time. A receipt converts "did you
consider the docs" (unverifiable) into "the line exists and the reason holds up" (ten seconds).

**Every point added to `AGENT.md` or this file must cite the commit that motivated it** — the
change it documents, or the mistake it guards against — kernel `Fixes:` style:

```
156b4703b ("fix(install): repair the RUNPATH via a rename, not in place")
```

A point with no commit behind it is unverifiable folklore; the citation is what lets the next
agent judge whether the reasoning still applies, which is this repo's rule for restoring removed
things applied to the docs themselves. `tests/lint_doc_citations.py` extracts every citation from
both files and fails the suite if one resolves to nothing. It resolves by SHA **or** by exact
subject line, because this repo merges with "Rebase and merge": a doc entry landing in the same PR
as the commit it cites will have that SHA rewritten at merge, and the subject is the half that
survives.

## Keep CHANGELOG.md fed

`CHANGELOG.md`'s `[Unreleased]` section is written by the PR that earns the entry, not by the
release. A release that finds it empty has to reconstruct what shipped from the git log — a worse
changelog, written weeks later by someone reading subject lines instead of the change.

**Every PR that changes anything under `dots/` must carry a `Changelog:` receipt line, and CI
rejects PRs without one** (`.github/workflows/changelog-receipt.yml`). One of:

- `Changelog: updated` — the entry is in this PR, under `[Unreleased]`. **The diff must actually
  touch `CHANGELOG.md`, and CI checks that**: a receipt satisfiable by typing the line is the prose
  rule again with a green tick on it, which is what the two empty releases already had.
- `Changelog: not user-visible — <reason>` — a refactor, a test, a lint, an internal rename.
  Liberal about the separator (em dash, en dash or a plain hyphen, spaced however you like), strict
  about the reason: everything after the dash *is* the receipt, so it may not be empty.

A PR that changes nothing under `dots/` — docs-only, CI-only, a proposal — is not asked for one at
all. Docs-only and CI-only PRs are the common case here, and a receipt every PR must carry whether
or not it could possibly need one is a receipt people paste without reading.

This exists because `[Unreleased]` was found **empty at two consecutive releases**: 43d1ffd01
("release: 0.25.0"), with 61 PRs merged behind it, and 58bd53a30 ("release: 0.26.0"), with five
more — whose own message says "the section was empty again". Both reconstructed the changelog after
the fact. The rule was prose both times, so a third paragraph is the one repair already known not to
work: a mistake made twice becomes a failing check in the same PR, never another note.

The matching lives in `dots/.config/quickshell/imi/tests/changelog_receipt.py` and nowhere else —
the workflow checks the repo out and runs that module rather than carrying its own `grep -E`, so the
CI half and the local half cannot become two answers. `tests/test_changelog_receipt.py` drives it
over in-memory PR fixtures, including the two forms offered above, so the rule is testable without
pushing anything.

## Multi-agent / parallel workflows (git worktrees)

This repo lives at `~/.config/quickshell/imi` and is loaded by exactly one running process,
`qs -c imi`, pointed at that exact directory. That has real consequences once more than one
agent (main session + subagents, or several parallel Claude Code sessions) is touching the repo at
once:

- **Stop the primary shell before a multi-file edit burst.** Every QML source write hot-reloads the
  configuration and rebuilds Quickshell's desktop-entry registry. On systems with large Wine/Steam
  application directories, several rapid reloads can queue millions of desktop-entry parses,
  consume gigabytes of memory, and make the shell appear frozen. Stop it once with
  `qs -c imi kill`, finish and test the batch, then launch exactly one clean
  `qs -c imi -d`. A single small edit may still use hot reload.

- **Only the primary checkout hot-reloads against the live shell.** A `git worktree add
  ../end4-pC-<feature> <branch>` checkout elsewhere is a completely separate directory - editing
  files there does *not* trigger the running instance's hot-reload, and the log-grepping /
  `console.log` verification loop above will show nothing for it. If an agent needs live verification
  from inside a worktree, either point a second, disposable `qs -c <path-to-worktree>` instance at it
  (fine for checking "does this even load without errors," but a second instance means a second OSD/
  bar/etc. on screen - don't leave it running), or accept that real verification happens after
  merging back into the primary checkout, not before.
- **Partition work by file/module, not just by feature name, before going parallel.** Two agents
  editing the same file concurrently (even in separate worktrees) just means a merge conflict later
  instead of a collision now - worktrees don't prevent that, they only defer it. Before starting
  parallel agent work, check whether the planned changes touch the same files; if they do, either
  serialize that part of the work or explicitly split who owns which section.
- **Treat `Config.qml`, `Appearance.qml`, and `GlobalStates.qml` as hot spots.** Nearly every feature
  ends up adding a property to one of these three files. If two parallel agents both add settings in
  the same nested `JsonObject`, or both touch the same color-token block, that's a near-guaranteed
  merge conflict even with unrelated features - flag this to the user up front rather than
  discovering it at merge time.
- **Small, single-purpose commits (see below) are what make parallel branches mergeable at all.** A
  worktree whose entire session is one giant commit is much more likely to conflict messily on merge
  than one with granular commits a reviewer (human or agent) can cherry-pick or rebase around.
- **Two worktrees may run `./tests/run_tests.sh` at the same time; the script queues them.** It
  holds one `flock` shared by every worktree and clone on the machine, across the section where
  its harnesses each bring up a nested weston. Before 8b5f04d6e ("test(suite): serialize a run's
  compositor harnesses behind one flock") the losing run reported a broken Wayland connection,
  which reads as a regression in whatever it was testing rather than as contention - and the rule
  that was supposed to prevent it ("check for a running suite first") was forgotten by every kind
  of caller including the maintainer. Do not add a hand check back; if a run is waiting it says
  which checkout it is waiting for.
- **Re-run the live-verification loop against the primary checkout after merging**, even if each
  worktree "passed" its own review - the merge itself, and the fact that the changes were never
  actually hot-reloaded together until now, are both new sources of breakage.
- **Clean up (`git worktree remove <path>`) once a branch is merged.** Stale worktrees pointing at
  already-merged or abandoned branches are easy to lose track of and easy to mistake for
  still-in-progress work later.

If the planned changes are small or touch a single, self-contained module, plain sequential work in
the primary checkout is usually faster than the overhead of standing up a worktree - reach for
worktrees when tasks are genuinely independent (different modules/files) and worth running
concurrently, not as a default for every subagent dispatch.

## Git conventions

- Commit **one logical change per commit** unless told otherwise - a bug fix, a new feature, a typo
  fix, and a UI enhancement discovered along the way are separate commits, even if they landed in
  the same conversation back to back.
- Write real commit messages (not caveman-terse, regardless of any session-level tone setting) -
  explain *why*, especially for anything non-obvious (a gotcha worked around, a race condition
  fixed, a naming/priority decision). Future-you (or the next agent) won't have this conversation's
  context.
- Never push without explicit confirmation for that specific push. An earlier approval to push
  doesn't carry forward to later, unrelated changes.
- This repo has **no upstream**. It publishes to `gh` (`XephyLon/immaterial-impulse`) and nothing
  else is fetched or merged. Never re-add `pctrade/end4-pC` or `end-4/dots-hyprland` as a remote,
  and never justify a code shape by "it keeps upstream merges clean".
- **Hard rule: agents do not add themselves as co-authors** (no `Co-Authored-By: <agent/model>` or
  similar trailer). Commits in this repo are attributed to the human maintainer only, regardless of
  which agent or model did the work. The same applies to **pull request bodies** - no "Generated
  with <tool>" footer or equivalent attribution line, even when the agent's own tooling suggests one
  by default.
- `gh pr create` can still resolve a base from GitHub's fork metadata rather than from this repo.
  Pass `--repo XephyLon/immaterial-impulse` so a PR always lands here.

## Style

- No comments explaining *what* code does - names should do that. A comment is only worth adding for
  a non-obvious *why*: a compositor quirk being worked around, a unit conversion that isn't visually
  obvious (e.g. MiB→KB to match `/proc/meminfo`'s units), a gate that looks redundant but isn't.
- Don't add config options, abstractions, or generalized "for future use" plumbing beyond what was
  asked. This is a personal shell config, not a library - concrete and specific beats flexible and
  speculative.
- **Give interactive elements (buttons, toggles, fields) an explicit `id`, regardless of which
  `RowLayout`/`ColumnLayout` they end up nested in.** A component's conceptual scope (e.g. "this
  action is per-item" vs. "this action is section-wide") doesn't have to dictate where it's declared
  in the tree - but Qt Quick Layouts (`RowLayout`, `ColumnLayout`) only apply their `Layout.*`
  positioning to their own *direct* children, so grouping unrelated-scope actions into one shared
  row still means they're literal siblings in that row's declaration. Use `id`s to keep each element
  individually addressable/referenceable (bindings, tooltips, future logic) independent of that
  physical grouping, rather than relying on structural position alone. See the AI provider action
  buttons in `ServicesConfig.qml` (`removeProviderButton`, `addProviderButton`, `fetchModelsButton`)
  for the pattern.
