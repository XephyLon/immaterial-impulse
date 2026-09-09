# Proposal: local retrieval (RAG) for the assistant

> Draft / tracking proposal. Not scheduled. Paths are relative to
> `dots/.config/quickshell/imi/` unless written repo-relative.

## Goal

Let the assistant answer from the user's own documents: the user names a few
folders, the shell indexes them locally, and a question that matches gets the
relevant passages attached to the prompt with citations. Nothing leaves the
machine unless the chosen chat model is already a cloud model.

## Current state

- **Memory** exists but is fact-shaped: `services/AiMemory.qml` keeps up to
  `ai.memory.limit` (40) short facts the model stores through the
  `remember_fact` tool. It is not a document store and does not search.
- **Attachments** exist per message (multi-attach in the composer), so the
  user can already hand the model one file by hand. Retrieval is the version
  of that which does not require knowing which file.
- **Citations** have a renderer: `modules/imi/sidebarLeft/aiChat/AnnotationSourceButton.qml`
  draws the source chips search mode returns. Retrieved passages can reuse it.
- **Tools** are declared once in `services/AiToolRegistry.qml` and folded per
  dialect by `services/ai/ai_tool_registry.js`, so a `search_documents` tool
  reaches every provider from one definition.
- **Embeddings** are reachable two ways today: a local Ollama
  (`/api/embed`, e.g. `nomic-embed-text`) and the cloud providers whose keys
  sit in `services/KeyringStorage.qml`.

The `ai-assistant-upgrade` proposal deferred RAG explicitly: "a separate
subsystem with its own privacy surface and its own failure modes ... its own
proposal with its own data-retention answers". This is that proposal, and the
retention answers are the first section of the approach.

## Why

- "What did that PDF say about X" is the question people actually ask an
  assistant that lives on their desktop.
- The fact memory tops out at forty lines; anything larger needs retrieval.
- With a local embedder and a local chat model the whole loop is offline,
  which is a selling point the cloud assistants cannot match.

## Approach

**0. The privacy contract, before any code.**

- Nothing is indexed unless the user adds the folder in Settings > AI >
  Documents. The default allowlist is empty.
- `~/.config/immaterial-impulse`, `~/.ssh`, `~/.gnupg`, anything matched by a
  `.gitignore` or a `.noindex` file, and dotfiles are never indexed even if
  inside an allowed folder.
- Removing a folder deletes its vectors and chunks immediately, not on the
  next reindex.
- The index lives in `~/.local/state/immaterial-impulse/user/rag/` and is
  excluded from `setup backup` (it is derived data and can be large).
- The embedder is named in Settings next to a sentence saying where the text
  goes ("locally, through Ollama" / "to OpenAI").

**1. The indexer** — `scripts/ai/ai_rag.py`.

- `index <folder>...`: walks the allowlist, chunks by type (Markdown and
  text by heading/paragraph; code by function-ish blocks with a line budget;
  PDF through `pdftotext` when present), embeds in batches, stores in one
  SQLite file: `chunks(id, path, mtime, start, end, text)` and
  `vectors(chunk_id, model, blob)`. Cosine search in numpy over the model's
  vectors; `sqlite-vec` if installed, not required.
- Incremental: a file whose `mtime` and size match is skipped; a removed file
  drops its rows. Prints progress lines (`{"done": 120, "total": 480}`) so the
  Settings page can show a bar.
- `query "<text>" --k 6`: prints the top chunks with `path`, line span, score.
- `forget <folder>`: deletes rows for that prefix.
- Vectors are namespaced by embedding model; switching the embedder starts a
  new namespace instead of mixing spaces, and the old one is dropped on the
  next `index`.

**2. The service** — `services/AiRag.qml` (new singleton; full `qs` restart
on first deploy).

- Holds the allowlist mirror, index status (`idle` / `indexing n/m` /
  `error`), and last-indexed time.
- `search(text, k)` runs the query subcommand and returns chunks.
- A slow watcher: reindex on a Settings action and, optionally, on a daily
  timer; **no** inotify over user folders (the privacy indicator lesson: a
  cheap subscription over the wrong scope is not cheap).

**3. Wiring into the chat.**

- A `search_documents(query, k)` tool in `AiToolRegistry.qml`, dispatched in
  `Ai.qml`'s `handleFunctionCall` like `get_shell_config`. The model decides
  when to look; this works with every provider that does tools.
- A "Documents" toggle in `ChatControlBar.qml`: when on, the top-k chunks for
  the user's message are prepended as a delimited context block before the
  send, for models without tool support (and for users who want retrieval
  every turn).
- Retrieved chunks render as source chips under the reply via
  `AnnotationSourceButton.qml`; clicking opens the file at the line with the
  configured editor.

**4. Config** — under `ai`:

```
property JsonObject documents: JsonObject {
    property list<var> folders: []
    property string embedder: "ollama:nomic-embed-text"
    property int topK: 6
    property bool alwaysAttach: false
}
```

## Risks

- **Prompt injection through indexed text.** A file can contain
  "ignore previous instructions". Retrieved chunks are wrapped in a data
  block the system prompt names as untrusted quoted material; the tool policy
  from `ai-assistant-upgrade` stage 4 keeps mutation tools behind review
  regardless of what the text says.
- **Index size and time.** A code tree embeds slowly on CPU; the first index is
  a visible background job with a cancel, and a per-folder file cap warns
  before starting.
- **Optional dependencies.** `numpy` is already used by other scripts;
  `pdftotext` (poppler) and an embedder are probed, and a missing one shows a
  hint rather than a stack trace.
- **Embedding model drift.** Handled by namespacing; the cost is a full
  re-embed on change, which Settings says out loud.

## Open questions

- Default embedder: Ollama `nomic-embed-text` (local, needs Ollama running)
  or none until the user picks one? Proposal: none, with Ollama offered first
  when detected.
- Should the file-read tool from the tool-adapters proposal share the same
  allowlist? Proposal: yes, one "folders the assistant may read" setting.
- Chunk size: 400 tokens with 50 overlap is the usual answer; measure on the
  user's Markdown notes before fixing it.

## Out of scope

- Indexing mail, browser history, or chat logs.
- A reranker model. Cosine top-k first; add reranking only if answers are
  visibly wrong on real notes.
- Sharing an index between machines.
