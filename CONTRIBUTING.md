# CONTRIBUTING.md — for coding agents

This is a workflow guide for agents (Claude Code or similar) making changes in this repo. For what
the project *is* and how it's structured, read `AGENT.md` first.

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
  even rendered it correctly during review - but the user's actual long-running `qs -c ii`
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
throughout `modules/ii/`. A fix or feature that touches a shared widget (e.g. `StyledComboBox`)
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

## Settings additions are two-sided

A new persisted option needs both halves, or it silently does nothing:
1. The schema property in `Config.qml` (inside the correct nested `JsonObject`).
2. A corresponding row in the relevant `modules/ii/settings/pages/*.qml` file, wired with
   `checked`/`value`/`currentValue` reading from `Config.options....` and an `on*Changed` handler
   writing back to it.

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
- **A green suite does not mean the shell loads.** The QML tests only instantiate pure-logic
  singletons, so any widget that fails to *compile* (a `FINAL` property override, a bad type name, a
  missing `import qs.modules.common`) passes every test while taking down every panel that reaches
  it. After touching any `.qml` under `modules/`, check the live log for `Configuration Loaded` and
  for `ERROR:` - not just `WARN` - before calling the change verified. See AGENT.md's "Where to look
  when something goes wrong" for the cascade format and the `pgrep -af 'qs -c ii'` caveat.
- **A new Python check must actually run.** `run_tests.sh` invokes each one as `python3 <file>`, so
  a module of bare `test_*` functions exits zero without executing anything. Either subclass
  `unittest.TestCase` with `unittest.main()`, or end the file with the `contract_runner` block
  documented in `tests/README.md`. Confirm the new check fails when you break the thing it guards -
  three modules shipped as silent no-ops precisely because nobody checked that.
- **Prove a new static check can fail.** These checks match source text; a pattern with baked-in
  indentation passes vacuously after any reformat.
- If the code you're touching depends on live compositor/audio state and genuinely can't be unit
  tested with the current harness (most `modules/ii/*` UI), that's fine - fall back to this file's
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

## Multi-agent / parallel workflows (git worktrees)

This repo lives at `~/.config/quickshell/ii` and is loaded by exactly one running process,
`qs -c ii`, pointed at that exact directory. That has real consequences once more than one
agent (main session + subagents, or several parallel Claude Code sessions) is touching the repo at
once:

- **Stop the primary shell before a multi-file edit burst.** Every QML source write hot-reloads the
  configuration and rebuilds Quickshell's desktop-entry registry. On systems with large Wine/Steam
  application directories, several rapid reloads can queue millions of desktop-entry parses,
  consume gigabytes of memory, and make the shell appear frozen. Stop it once with
  `qs -c ii kill`, finish and test the batch, then launch exactly one clean
  `qs -c ii -d`. A single small edit may still use hot reload.

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
- `git remote -v` before assuming which remote is "upstream" vs "the fork you push to" - this repo
  has both, and they matter for where a `git pull`/`git push` actually lands.
- **Hard rule: agents do not add themselves as co-authors** (no `Co-Authored-By: <agent/model>` or
  similar trailer). Commits in this repo are attributed to the human maintainer only, regardless of
  which agent or model did the work. The same applies to **pull request bodies** - no "Generated
  with <tool>" footer or equivalent attribution line, even when the agent's own tooling suggests one
  by default.
- `gh pr create` defaults its base to the **parent** repo (`pctrade/end4-pC`) because `origin` is a
  fork. Pass `--repo XephyLon/immaterial-impulse` for a PR that stays in this fork.

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
