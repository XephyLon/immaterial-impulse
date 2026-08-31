# AI Chat Skeleton & Motion — Design

**Date:** 2026-08-31
**Status:** Approved (brainstorm 2026-08-31; sub-project 1 of the AI section polish — sub-2 sessions drawer, sub-3 prompt history + edit/regenerate follow in their own specs)

## Problem

The left sidebar's Intelligence tab is one flat column: a floating status
pill over the message list, an empty state of keyboard hints, an input box.
The p3drovfx fork's AI surface reads as a composed instrument - distinct
surfaces, a chip control bar, entrance choreography, a greeted empty state.
Port that grammar onto imi's tokens and design language; the fork's own
numbers are hand-typed and do not transfer.

## Decisions

1. **Adopt the fork's three-surface skeleton** (user's call over keeping
   imi's): tools bar, chat area, composer.
2. This sub-project is **skeleton + motion only**. The popover/canvas view
   system, sessions, find-in-chat, drag-drop overlay, personas, prompt
   history and edit/regenerate are later sub-projects or parked.
3. All motion on imi's `Appearance.animation` tokens; text through
   `Translation.tr`.

## Skeleton (`modules/imi/sidebarLeft/AiChat.qml` restructure)

Three children of the root column, `colLayer1` surfaces:

1. **Tools bar** — a full-radius pill (`Appearance.rounding.full`, clipped)
   holding the new `ChatControlBar`. Height ~44px from spacing tokens, not
   a hand-typed constant.
2. **Chat area** — `Appearance.rounding.large`, clipped, `fillHeight`.
   Owns: the message `StyledListView` (unchanged model/delegates), the
   `ScrollEdgeFade`, `ScrollToBottomButton`, the empty state (below), and
   the `EmptyStateKey` rail. The floating `statusBg` pill and its shadow
   are DELETED - their content moves into the control bar.
3. **Composer** — the existing input wrapper (attachment indicator, text
   area, command buttons row) as its own surface at the foot.
   `DescriptionBox` and the suggestions `FlowButtonGroup` stay between chat
   area and composer, riding the same column.

## Control bar (`modules/imi/sidebarLeft/aiChat/ChatControlBar.qml`, new)

Fork's `ControlChip` grammar, imi tokens:

- A row of chips: **model** (icon + current model name, caret), **temp**
  (`device_thermostat` + `Ai.temperature.toFixed(1)`), **key**
  (`key`/`key_off`), **tokens** (`token` + total, only when
  `Ai.tokenCount.total > 0`), spacer, **new chat** (`edit_square`, calls
  the existing clear/new-chat command path).
- `compact` rule: below a width threshold derived from the bar's own
  contents, chips drop labels and keep icon + value.
- Chips are `RippleButton`s with `StyledToolTip`s carrying the command
  hints the status pill used to show (`/key`, `/temp`).
- **The bridge, stated:** no popover views in this sub-project. The model
  chip pre-fills `/model ` into the input field and focuses it (the
  existing suggestion flow answers); its caret and the `openView`-shaped
  API stub the seam the sessions drawer (sub-2) will fill. Temp and key
  chips likewise pre-fill `/temp ` and `/key `.
- The bar reads `Ai.*` directly - it is a module component beside
  `AiMessage`, not a common widget, and the dumb-widget rule does not
  apply to `modules/imi/`.

## Motion

One `entranceTrigger` int on the chat root, bumped on sidebar open (the
existing `onSidebarLeftOpenChanged` arm):

- **Composer entrance:** opacity 0→1, translate y 40→0, blur 20→0
  (`FastBlur` layer), on `Appearance.animation` curves - the fork's
  composer rise as the choreography's last rank. One writer per channel:
  the entrance owns opacity/transform/blur; the existing StaggerWave stops
  dressing the composer (its wave membership is removed).
- **Transcript reveal:** a `transcriptRevealToken` int; delegates in view
  when the token bumps run a short fade+rise, offscreen delegates are
  created settled. A closing `Timer` window (enter duration + 2×small)
  resets the token so scroll-created delegates never replay it. Never
  triggered while `Ai.isGenerating` - the fork's guard, reason included.
- **Empty state:** the existing glyph-grow stays. A **greeting** replaces
  the static "Large language models" title: a line rolled per opening from
  a small local list of hellos (via `Translation.tr`), overridable by a
  new `Config.options.sidebar.ai.greeting` string (empty = roll). The
  hint description shrinks to "Ask anything"; the keyboard hints move to:
- **`EmptyStateKey` rows** (`modules/imi/sidebarLeft/aiChat/EmptyStateKey.qml`,
  new): a keycap-styled row - kbd chips + label - anchored at the chat
  area's foot while the chat is empty. Rows: `/key` ("Set an API key to
  get started"), `Ctrl+O` expand, `Ctrl+P` pin, `Ctrl+D` detach. Fades
  with the empty state.
- Wave membership: tools bar and chat area stay StaggerWave members with
  the pane's existing 80/25 cadence; composer leaves the wave for its own
  entrance (above).

## Config

- New key `sidebar.ai.greeting: ""` (string; empty rolls a hello).
- No other schema changes.

## Error handling

- No API key: the key chip shows `key_off` in `colError`-tinted ink and
  its pre-fill is the recovery path; the empty state keeps the `/key` row.
- Model with no name (stale config): chip falls back to the raw model id.
- Reveal token guards: no reveal mid-generation; token window closes.

## Testing

- Python pins (`tests/test_ai_skeleton_contract.py`, contract_runner):
  the three surfaces exist (tools bar pill + chat area + composer ids);
  the floating `statusBg` pill is gone; the composer is not a wave member
  while carrying its own entrance (one writer per channel - grep that no
  `property real appear` remains on the input wrapper); `ChatControlBar`
  chips carry tooltips naming the commands.
- qmllint on every touched file; named tests only, suite parked.
- Maintainer visual pass: open sidebar (bar + chat surfaces wave in,
  composer rises last), empty-state greeting rolls, chips compact on a
  narrow sidebar, transcript reveal on reopen with messages present.

## Out of scope

Popover/canvas views, sessions drawer (sub-2), prompt history and
edit/regenerate (sub-3), find-in-chat, drag-drop overlay, personas,
reduced-motion switches.
