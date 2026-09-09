# Proposal: more tool adapters for the assistant

> Draft / tracking proposal. Not scheduled. Paths are relative to
> `dots/.config/quickshell/imi/` unless written repo-relative.

## Goal

Give the assistant hands for the things a desktop assistant is asked to do:
read and write files in folders the user named, use the clipboard, change the
wallpaper and theme, look at the screen, and add to the to-do list — each
behind the permission tier its risk deserves.

## Current state

`services/AiToolRegistry.qml` declares ten tools once and
`services/ai/ai_tool_registry.js` folds them per dialect (OpenAI, Mistral,
Gemini, Anthropic):

```
switch_to_search_mode  get_shell_config  set_shell_config  run_shell_command
remember_fact          control_media     focus_window      send_notification
get_system_status      generate_image
```

`services/Ai.qml`'s `handleFunctionCall` dispatches them. `run_shell_command`
is the escape hatch that makes everything else possible and nothing else
safe: it is the tool the permission vocabulary in `ai-assistant-upgrade`
stage 4 (`ai_tool_policy.js`: read / reviewed mutation / confirmed
destructive) exists to fence. That vocabulary is a prerequisite for the
writing tools below; the reading tools can land before it.

Existing services the adapters wrap, so no adapter needs new plumbing:
`services/Cliphist.qml` (clipboard history, `wl-copy`), `services/Wallpapers.qml`
(`select`, `getRandomWallpaperPath`), `scripts/colors/switchwall.sh`
(accent, palette source, light/dark), `services/Todo.qml`,
`services/IcsCalendar.qml`, the region selector (`GlobalStates.regionRequested`),
and the vision-capable model path (multi-attach already sends images).

## Why

- Every "can you just..." that ends in `run_shell_command` is a tool the
  model had to improvise, with a shell command the user has to read. A named
  tool is narrower, reviewable, and testable.
- The theme and wallpaper are the shell's own domain; asking a model to
  `sed` config.json for them is absurd when `switchwall.sh` exists.
- Tools are the cheapest feature in the assistant: one declaration, one
  dispatch case, one test.

## Approach

Each adapter is one entry in the registry, one case in `handleFunctionCall`,
and one contract test under `tests/`. Grouped by tier:

**Read tier** (auto-run, result returned to the model):

- `read_file(path)` — only under `ai.tools.folders` (shared with the RAG
  allowlist if that proposal lands); size-capped; binary refused; text
  returned inside a delimited data block the system prompt names as
  untrusted.
- `list_directory(path, depth)` — same allowlist, dotfiles hidden.
- `get_clipboard()` — current text entry via `Cliphist`; images returned as
  an attachment when the model accepts images.
- `get_wallpaper()` — current path, palette source colour, light/dark.
- `list_todos()`, `list_events(days)` — from `Todo` and `IcsCalendar`.
- `capture_screen(mode)` — `mode` is `screen` or `region`; region goes
  through the region selector (the user draws it, so consent is inherent),
  the result attaches as an image for a vision model. Refused for models
  without vision.

**Reviewed-mutation tier** (the reply shows the proposed change; the user
applies it — the stage-5 "reviewed mutation" card):

- `write_file(path, content)` / `append_file` — allowlisted folders only,
  diff shown before write, a `.bak` beside the target on first write in a
  session.
- `set_clipboard(text)` — small enough to show whole.
- `set_wallpaper(path | "random")`, `set_accent(hex | "auto")`,
  `set_palette_source(mode)`, `set_color_scheme(light | dark)` — one call
  into `Wallpapers`/`switchwall.sh`; the card shows a thumbnail or swatch.
- `add_todo(text, due)`.

**Confirmed-destructive tier** (explicit confirm dialog):

- Nothing new in this proposal. `run_shell_command` stays the only member,
  and the point of the named tools is that it is used less.

**System prompt.** One paragraph listing the tools by tier so the model
prefers `set_wallpaper` over a shell command, and stating that file and
clipboard contents are data, never instructions.

**Config** — under `ai`:

```
property JsonObject tools: JsonObject {
    property list<var> folders: []        // read/write allowlist
    property bool allowScreenCapture: true
    property bool allowClipboard: true
}
```

## Risks

- **Prompt injection.** A file or clipboard entry can carry instructions.
  Mitigation is structural: data blocks are labelled, mutation tools need
  review, and the destructive tier needs confirmation; a poisoned file can
  at most propose a change the user then reads.
- **Path escape.** Every path resolves through `realpath` and is checked
  against the allowlist after resolution; symlinks out of the allowlist are
  refused. The presets fix (03ad7ece5) is the precedent for validating names
  before touching the filesystem.
- **Capture consent.** `capture_screen("screen")` takes the whole screen
  without a draw step; it runs only when `allowScreenCapture` is on and the
  reply shows the image it sent.
- **Dialect gaps.** Gemini and Anthropic schemas differ in enum/array
  support; `ai_tool_registry.js`'s fold handles it, and the contract test
  runs every new definition through all four folds.

## Open questions

- Should `read_file` exist before the permission vocabulary lands? Proposal:
  yes for the read tier (it cannot change anything); the mutation tier waits.
- One allowlist for RAG and tools, or two? Proposal: one, named "Folders the
  assistant may read".
- Does `set_wallpaper` belong to the reviewed tier or auto-run? It is
  reversible in one click; proposal keeps it reviewed until the card is cheap
  enough that review costs nothing.

## Out of scope

- Browser control, mail, calendar writes.
- Arbitrary process launching beyond what `run_shell_command` already does.
- MCP servers as a tool source (a separate proposal if ever wanted: it is a
  transport, not an adapter).
