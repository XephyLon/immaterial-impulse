# Typing test in the cheatsheet - design

**Status:** built on `feat/typing-test` (stacked on `fix/cheatsheet-fit-screen`), 2026-09-02.

## What

A Monkeytype-style typing test as a cheatsheet tab, ported whole from the p3drovfx
fork (`modules/ii/overview/typing`, fork commits 15062d697..5ef6f0d8d, 2026-08-30/31):
time / words / zen (plain and guided) modes, punctuation and numbers, seven vendored
Monkeytype 1k word packs, a results screen (WPM / raw / accuracy / consistency, a graph,
a character breakdown), personal bests, bounded history, a stats page with an activity
map, Monkeytype's key-press and error sounds, a keyboard preview for five layouts, and
an in-page settings page. Full port was the maintainer's call over a core-only one.

## Where it lives

- `modules/imi/cheatsheet/typing/` - the fork's thirteen files, mechanically adapted.
- `modules/imi/cheatsheet/CheatsheetTypingTest.qml` - the page frame (budgets, focus,
  Escape, key hint bar).
- `services/TypingLanguages.qml`, `services/TypingSoundPacks.qml` - manifest-driven
  catalogues; new singletons, so a running shell needs a restart, not a hot reload.
- `modules/common/widgets/KeyHint.qml`, `KeyHintBar.qml` - new; `KeyboardKey.textColor`.
- `assets/typing/` - packs, sounds, manifests, ATTRIBUTION.md (GPL-3.0-only, as this repo).
- `scripts/typing/` - the two sync scripts (development only).
- `Config.options.cheatsheet.typingTest.*` + `cheatsheet.enableTypingTest` (default on:
  the tab is the only host here); `Persistent.states.typingTest` (aggregates only).
- Settings > General > Cheatsheet: the one switch. Everything else is in-page.

## Decisions

- **Cheatsheet only, no launcher host.** The fork also hosts the surface as a search
  panel; this shell's launcher has no hosted-panel contract, and none was built.
- **Config moved from `search.typingTest` to `cheatsheet.typingTest`** - it is the
  cheatsheet's feature here. Every read in the ported files follows (contract-tested).
- **Key hints are plain chords.** The fork's `ConfiguredKeyHint` resolves a launcher
  action's rebound key; there is no such map here.
- **The page fits the window's budget** (`pageWidthBudget` / `pageHeightBudget`, from
  `cheatsheetFit.js`): a 1100x640 stage, never more than the screen leaves.
- **One page list drives the tab bar and the SwipeView.** A second optional page made
  the old parked-Loader shape wrong (developer mode on, typing off: the Components tab
  over an empty loader). `pages` is declared on the window, where the page Components
  are in scope - on the Scope root it was a ReferenceError and an empty window.
- **Spacing literals became `Appearance.spacing` tokens** (44 sites, nearest step), for
  the spacing lint; nothing else in the fork's numbers was retuned.

## Verification

- `tests/test_typing_test_contract.py` (13 checks, in run_tests.sh): the page's wiring,
  every Config leaf declared, bounded local aggregate-only history, read-only stats page,
  the shortcut table, vendored packs/sounds against their checksums, no process or
  network on the input path, golden metrics.
- `DesignSystemCompile.qml` names the page. Full suite green (1589 QML checks, every
  harness) on the branch.
- Driven in a nested Hyprland (1280x720) through a throwaway `qs -p` probe: english_1k
  loaded (1000 words), sound packs loaded, 220 target words, `wtype`d text reached the
  engine (state running, WPM computed). Deployed live with a clean log.

## Not done

- Launcher hosting (see above). Sounds unverified by ear on the live machine.
