# Proposal: Ollama catalog — browse, pull, remove local models

> Draft / tracking proposal. Not scheduled. Paths are relative to
> `dots/.config/quickshell/imi/` unless written repo-relative.

## Goal

Manage local models from the assistant's model browser: see what is installed
and what is loaded, pull a new model with a progress bar, remove one, and get a
"fits your GPU" hint before downloading multiple gigabytes.

## Current state

- **Installed models are discovered**, not managed: `services/Ai.qml`'s
  `getOllamaModels` runs `scripts/ai/show-installed-ollama-models.sh` and
  turns each name into a catalog record (`services/ai_catalog.js` has the
  `ollama` provider as a `discovered` provider).
- **A browse-and-import view exists for OpenRouter**:
  `modules/imi/sidebarLeft/aiChat/BrowseModelsView.qml` over
  `services/ai/openrouter_models.js` (read-only remote index, explicit import
  into `ai.extraModels`). It is the shape this proposal extends.
- **GPU memory** is already sampled for the resource widgets
  (`services/ResourceUsage.qml`, nvidia-smi behind the runtime-status gate),
  which is what a fit hint needs.
- The `ai-assistant-upgrade` proposal kept "OpenRouter / Ollama catalog
  browsing with model pulls" out of scope as "a store-like network browsing
  surface with its own review needs" while noting "the catalog shape does not
  preclude adding browsing later". This is that later.

## Why

- Today a user opens a terminal for `ollama pull`, then returns to the shell
  and hopes discovery ran. The shell knows the installed list; it should own
  the install.
- Model choice is the single biggest lever on local assistant quality, and
  the browser is where the user already is when choosing.
- Disk and VRAM are the two numbers people get wrong; the shell has both.

## Approach

**1. Talk to the daemon, not the CLI.** Ollama's HTTP API on
`http://127.0.0.1:11434` (or the URL of the `ollama` custom provider):

- `GET /api/tags` — installed models with size, family, parameter count,
  quantization. Replaces the shell script for the browser (the script stays
  for the chat's discovery until the browser is proven).
- `GET /api/ps` — currently loaded models and their VRAM use.
- `POST /api/pull` — NDJSON progress (`status`, `completed`, `total`);
  streamed through a `Process` running `curl -N` into a `SplitParser`, one
  line per event, into a progress bar. Cancel = kill the process; Ollama
  resumes a partial pull on the next request.
- `DELETE /api/delete` — remove.

**2. The remote library.** ollama.com has no public JSON catalog. Two
options; the proposal picks the first:

- **Curated snapshot** in `services/ai/ollama_library.js`: forty-odd models
  with family, sizes, capabilities (tools, vision, embedding), refreshed by
  hand at release time with a script under `scripts/ai/`. Deterministic,
  offline, reviewable in a diff.
- Scraping `https://ollama.com/search?q=` HTML: live but churn we would own.
  Rejected for the same reason the ESPN scraper was.

An "Open on ollama.com" link covers anything the snapshot lacks; the pull
field also accepts any `name:tag` typed by hand.

**3. The view.** `BrowseModelsView.qml` gains a source switch:
OpenRouter | Ollama. The Ollama page lists:

- **Installed** — name, size on disk, loaded badge (from `/api/ps`), "Use"
  (selects it as the chat model), "Remove" (confirm dialog with the size).
- **Library** — the snapshot, filterable by capability; each row shows sizes
  per tag and a fit hint: green when the quantized size fits free VRAM (from
  `ResourceUsage`), amber when it will spill to RAM, red when it exceeds
  both. "Pull" asks once, shows the download size, then streams progress in
  the row.
- A one-line daemon status at the top: running / not running (with
  "Start" running `systemctl --user start ollama` when the unit exists).

**4. Chat integration.** A completed pull refreshes the model list without a
shell reload; a removed model that was selected falls back to the previous
one and says so in the composer status.

## Risks

- **Disk.** Pulls are 1-40 GB. The confirm dialog states the size and the
  free space of the partition Ollama stores in (`OLLAMA_MODELS` or
  `~/.ollama`), and refuses when it would not fit.
- **Daemon absent.** Everything but the snapshot hides behind the daemon
  status; nothing spawns `ollama` itself except the explicit "Start" button.
- **Snapshot staleness.** Mitigated by the free-text pull field and the
  release-time refresh script; the snapshot carries its date in the UI.
- **VRAM hint accuracy.** Context length changes real use; the hint is
  labelled as an estimate for the default context.

## Open questions

- Does the Ollama page belong in the sidebar browser or in Settings > AI?
  Proposal: the browser (it is where OpenRouter lives), with a Settings link.
- Should the chat's discovery move to `/api/tags` in the same change?
  Proposal: yes once the browser has run on two machines; the script is the
  fallback when the daemon URL is unreachable.

## Out of scope

- Creating models from Modelfiles.
- Managing remote Ollama hosts beyond the configured base URL.
- Hugging Face GGUF browsing.
