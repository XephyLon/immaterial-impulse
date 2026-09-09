# Proposal: the assistant in the overview search

> Draft / tracking proposal. Not scheduled. Paths are relative to
> `dots/.config/quickshell/imi/` unless written repo-relative.

## Goal

Ask the assistant from the launcher: a prefix (or a fallthrough when nothing
else matches) turns the query into a question, Enter opens the chat with the
answer streaming, and short factual questions can answer inline in the
results list without leaving the overview.

## Current state

- **The search pipeline** is `services/LauncherSearch.qml`: a `query` string,
  prefix routing (`Config.options.search.prefix.*` for action, app, clipboard,
  emojis, symbols, math, shellCommand, webSearch, keybinds, file), and a
  `results` binding. Its comments record the two traps this proposal must
  respect: never spawn from the `results` binding (eight `qalc` processes per
  keystroke), and decide from the query alone before anything runs.
- **The bar** (`modules/imi/overview/SearchBar.qml`) has a
  `SearchPrefixType` enum and gives each type a shape and an icon
  (`MaterialShape.Shape.*`, a Material Symbol). A new type slots in there.
- **Result rows** are `SearchItem.qml`; a math result already shows a
  computed value in place, which is the visual precedent for an inline
  answer.
- **The chat** opens through `modules/imi/sidebarLeft/SidebarLeft.qml`'s IPC
  (`sidebarLeft` target, `open()`), and `services/Ai.qml` sends with
  `sendUserMessage(message)` and streams into the current session.
- **The overview** has its own IPC (`target: "search"`) and
  `setSearchingText`, which is how the clipboard/emoji toggles prefill a
  prefix today.

## Why

- Super, type, Enter is the fastest path on the desktop; the assistant is
  currently three clicks and a panel away.
- A typed question that matches no app is the most common "dead" launcher
  query; today it falls to web search.
- The pieces exist; this is routing, one row type, and a config block.

## Approach

**1. A prefix and a fallthrough.**

- `search.prefix.ai` (default `?`). `?how do I rotate a monitor in hyprland`
  is a question regardless of what else matches.
- `search.ai.fallthrough` (default off): when on and a query of four or more
  words matches no app, action, or file, the ask row appears at the bottom.
  Off by default because it changes what Enter does on a miss.

**2. The ask row.** A `SearchItem` whose title is "Ask <model>: <query>" and
whose icon is the model's logo (`Ai.qml` already maps names to
`ollama-symbolic` etc.). Enter: open the left sidebar's chat, send the query
as a user message, close the overview. No network until Enter.

**3. Inline answers** (`search.ai.inline`, default off).

- For a `?` query of at least three words, after a 700 ms pause in typing,
  send it to the configured model with a "answer in one sentence" system
  prompt and stream the first 200 characters into the ask row's subtitle.
- Any keystroke cancels the request (`Ai.qml` already has a stop path for
  streaming). One request in flight at a time.
- Enter on a row with an inline answer still opens the chat, with the
  question and the partial answer already there, so the conversation
  continues instead of restarting.
- Only offered when the selected model is local (Ollama) **or** the user has
  turned on "inline answers may use my cloud key" in Settings, because
  keystroke-driven cloud calls cost money and leak typing.

**4. Natural-language actions** (later phase). `?dark mode`, `?mute` route
through the assistant's existing tools (`set_shell_config`, `control_media`,
`focus_window`) with the tool's normal review; the overview shows the
proposed action as a row and Enter confirms it. Reuses the permission
vocabulary from `ai-assistant-upgrade` stage 4 rather than inventing one.

**5. Config** — under `search`:

```
property JsonObject ai: JsonObject {
    property bool fallthrough: false
    property bool inline: false
    property bool inlineWithCloud: false
    property int inlineDelayMs: 700
}
```

and `prefix.ai: "?"` beside the existing prefixes.

## Risks

- **Latency on the keystroke path.** The overview redraws per character;
  nothing here may run in the `results` binding. The inline request is
  driven from `onQueryChanged` through a restartable Timer, exactly like the
  math path's `nonAppResultsTimer`.
- **Privacy.** Typed text goes to a model only on Enter unless inline is on,
  and inline is off, and cloud-inline is a second switch. Settings says what
  each switch sends where.
- **No model configured.** The ask row is hidden when `Ai` has no usable
  model (no key for the selected provider, no Ollama), so the launcher never
  offers a dead end.
- **Conflicting prefix.** `?` is a poor choice if a future prefix wants it;
  it is configurable and the enum keeps prefixes disjoint.

## Open questions

- Default prefix: `?` or `>`? Proposal: `?` reads as a question.
- Should Enter on the ask row open the chat **detached** (the left sidebar
  can float) so the overview's context is not lost? Proposal: follow the
  sidebar's current pin/detach state.
- Does the inline answer belong in the row subtitle or a card under the
  list? Row subtitle first; a card only if answers routinely exceed a line.

## Out of scope

- Voice input from the overview (see the voice-input proposal).
- Replacing web search; `webSearch` stays its own prefix.
- Answer caching across sessions.
