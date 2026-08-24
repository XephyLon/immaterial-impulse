# Proposal: AI assistant upgrade — catalog, permissions, reviewed mutation

> Stage 1 (the provider/model catalog as a pure module) is implemented on the
> branch that carries this document: `services/ai_catalog.js`,
> `tests/tst_ai_catalog.qml`, and `tests/test_ai_catalog_contract.py`, which
> pins the catalog and `services/Ai.qml`'s literals to each other until stage 2
> deletes the second copy. Nothing is wired into the UI yet, deliberately —
> see stage 2 for why.

## Goal

Take the three transferable *shapes* from the `P3DROVFX/ii-p3drovfx` AI
assistant rebuild — a provider/model **catalog** ("describe providers and
models in one place"), a per-tool **permission vocabulary**, and a
**reviewed-mutation** pattern (every shell-touching tool goes through one
validated, approvable road) — and land them on our architecture, without
taking the parts the surveys already rejected and without moving a single
credential out of the keyring.

This is the "own proposal" that
[`docs/p3drovfx-feature-delta-2026-08-24.md`](../p3drovfx-feature-delta-2026-08-24.md)
§2.2 and §3 call for: *"if ever, take the catalog + permission shapes, and no
`.env`"*.

## Current state (ours)

- `services/Ai.qml` (984 lines) is the whole chat service: three built-in
  models declared as inline `aiModelComponent.createObject` literals
  (Gemini 2.5 Flash, Gemini 3 Flash, Mistral Medium 3), Ollama models
  discovered at runtime, custom OpenAI-compatible providers fetched from
  `Config.options.ai.customProviders` with keys in the keyring, and
  `Config.options.ai.extraModels` for hand-written entries.
- Three API dialects, each a strategy under `services/ai/`
  (`GeminiApiStrategy`, `OpenAiApiStrategy`, `MistralApiStrategy`), selected
  by the model's `api_format`.
- The tool table (`Ai.qml`'s `property var tools`, ~150 lines) declares the
  same four tools **three times over**, once per dialect —
  `switch_to_search_mode`, `get_shell_config`, `set_shell_config`,
  `run_shell_command` — as near-identical JSON blocks that have to be kept in
  step by hand. This is the two-copies drift shape `BarWidgets` and
  `MprisController` each grew a check against, here as three copies.
- Approval exists for exactly one tool: `run_shell_command` sets
  `functionPending` and waits for `approveCommand`/`rejectCommand`.
  `set_shell_config` writes `Config.setNestedValue(key, value)` **immediately,
  with no approval** — and its branch in `handleFunctionCall`
  (`Ai.qml:881-888`) sends no function-output message back and never calls
  `makeRequest()`, so after a config write the model is left waiting for a
  result that never comes. The mutation path is both ungated and half-built.
- Credentials are right already: every API key lives in the keyring
  (`KeyringStorage.keyringData.apiKeys`, keyed by `key_id`), reaches `curl`
  through an environment variable, and the one place a secret meets a shell
  string passes it as a positional argument with a comment naming the
  injection hole that shape closed (`Ai.qml:366-370`). The 2026-08-16 survey
  (§3.1, §5) judged this layer *equal or better* than the fork's — this
  proposal must not regress it.
- One latent defect found while surveying our side: custom-provider keys are
  keyring entries keyed **by list index** (`custom_provider_${i}`). Removing
  provider *i* clears key *i* and splices the list, so every later provider
  shifts down one slot while its key stays put — provider and key silently
  disagree from then on (`ServicesConfig.qml` remove button + `Ai.qml`'s
  `fetchCustomModels`).
- Chats persist as JSON under `Directories.aiChats` (`saveChat`/`loadChat`,
  plus an automatic `lastSession`). Serviceable; per-conversation permission
  state has an obvious home there.
- Tests: `tst_ai_custom_models.qml` covers `AiModelsParser.js`. Nothing else
  in the AI stack is reachable from a test, because almost none of it is pure.

## The evidence (theirs)

The fork rebuilt its AI stack across ~60 commits, merged as their PR #98
(`40df34f9`, "Merge pull request #98 from P3DROVFX/feat/ai-rebuild",
2026-08-22, author P3DROVFX / Pedro Lucas). Read at their tip `81a5f57`
(2026-08-24), the pieces this proposal draws on:

- `dots/.config/quickshell/ii/services/ai/ModelCatalog.qml` (597 lines) —
  "the single source of truth for which AI providers and models exist":
  provider definitions with per-model capability overrides (thinking, tools,
  vision, attachments, context window, max output, prices), models keyed
  `provider:value`, endpoint templates with a `{model}` slot, a
  key-whitelisted sanitiser for user-declared models, and a loopback-endpoint
  predicate backing the local-only policy. Claude (`anthropic` dialect,
  `AnthropicApiStrategy.qml`, 329 lines) and current Gemini are catalog
  entries like any other.
- `services/ai/AiToolRegistry.qml` (1,963 lines) — "everything that is true
  about a tool before anyone runs it": one declaration per tool, read by the
  schema sent to the model, the Tools settings page, the approval card and
  the dispatcher, with a small closed vocabulary — `kind` (localRead /
  explicitContextRead / navigation / externalRead / localWrite /
  externalWrite / dangerous), `network` (never / optional / required),
  `sensitivity` (none / device / personal / secret), approvals
  (allow / ask / deny) — and risk *derived* from `kind` "so there is one
  classification". Permissions are grouped by domain (`c4f7c64`) and scoped
  **per conversation** (`04a2614`, "feat(ai-tools): scope permissions per
  conversation").
- `services/ai/AiToolBroker.qml` (512 lines) — "the one place a tool call
  actually happens": schema-check the arguments (coerce the fixable, drop
  unknown keys), ask the policy **at call time** rather than trusting the
  answer from when the tool was offered, run with a deadline, truncate the
  result to what the model can hold, journal what happened. What replaced it
  is exactly what we still have: "a chain of `if (name === ...)` inside the
  chat service".
- `services/ai/AiConversationRepository.qml` (139 lines) and the usage/RAG/
  integration cluster around it — read for context, not taken (see Out of
  scope).

Both repositories are GPL-3.0, so taking code is licence-compatible; anything
taken **substantially as written** gets a credit line in the commit body
naming the repo, the commit and the author, per the 2026-08-16 survey §6.
This proposal mostly takes shapes and rewrites against our architecture; the
few candidates for near-verbatim porting are flagged in their stages.

The same survey's hard blockers stand and bound every stage below: the
fork's plaintext `<shellconfig>/.env` credential pattern (which their
2026-08-19 work *expanded* — Google OAuth was unified into it) does **not**
come over in any form, and their `bash -c` bearer-token interpolation
(`TickTickService.qml:48-80`, visible in `ps` to any local process) is a
named anti-pattern, not a style choice. Our rule is already better: keys
live in `services/KeyringStorage.qml`, travel as environment variables or
positional arguments, and are never spliced into script text.

## Why

- **The catalog** removes the three-way scatter our model knowledge lives in
  today (Ai.qml literals, `AiModelsParser.js`, `extraModels` conventions
  documented only in a Config comment), gives capability flags one home so a
  UI can honestly say "this model cannot see images" instead of failing
  downstream, and is the precondition for adding a dialect (Claude) without
  growing a fourth hand-kept copy of everything. It is also the shape this
  repo already trusts: `WallpaperTransitions`, `BarWidgets`, `MprisSelection`
  — one catalogue, pure where possible, with a check against a second copy.
- **The permission vocabulary** replaces the triplicated tool table with one
  declaration per tool, and gives "what may this conversation do" a data
  model. Today the only knob is `Config.options.ai.tool` (search / functions
  / none) — all tools or nothing.
- **The reviewed mutation** closes a real hole: a model can rewrite any key in
  the user's `config.json` today with no approval, no feedback to the model,
  and no record. The approval card exists (for `run_shell_command`); the
  pattern just never generalised.

## Approach

### 1. The catalog (`services/ai_catalog.js`) — stage 1, implemented

A pure `.pragma library` beside `services/frecency.js` and
`services/sound_theme.js` — data plus lookups, no Qt, no Config, no
processes — so every rule is reachable from `qmltestrunner`. Deliberately a
JS module rather than the fork's `QtObject` singleton: their catalog binds
`Config` and `Translation` directly, which is what makes it untestable
outside a shell.

What it declares, per the fork's shape reduced to what our shell can honestly
do today:

- **Dialects** (`gemini`, `openai`, `mistral` — exactly the strategies under
  `services/ai/`): endpoint shape (`model-in-path` vs `chat-completions`),
  auth transport (`query-key` vs `bearer-header`), streaming framing
  (`json-array` vs `sse`).
- **Providers** (`google`, `mistral`, `ollama`): endpoint template with a
  `{model}` slot, dialect, key *metadata* (`keyId`, `keyGetLink` — never
  material), capability defaults, and the built-in model list with per-model
  overrides. Ollama is a `discovered` provider whose models arrive at
  runtime.
- **Models**: id `provider:value`, plus a `legacyId` recording the flat key
  today's `Ai.qml` (and every stored `Persistent.states.ai.model`) uses;
  `resolve()` answers both, so stage 2 needs no migration for a saved model
  choice. Capabilities are merged provider-default ⊕ model-override
  (`buildModel`, exposed so the merge is testable and stage 2's custom-model
  path can reuse it).

What deliberately stays out: translated descriptions (they are
`Translation.tr(...)` literals and the extractor only sees that form — same
reasoning as `BarWidgets`' names), and anything key-shaped
(`test_the_catalog_stays_pure` refuses the key plumbing's names in code).

Until something reads it, the catalog and `Ai.qml` are two copies of one
truth, so `tests/test_ai_catalog_contract.py` pins them equal field by field
in both directions and pins the dialect vocabulary to the strategy files.
Stage 2 inverts that check rather than deleting it.

**Why nothing is wired yet**: `Ai.qml`'s `models` map is one monolithic
translated literal; there is no *small* read that could adopt the catalog
without rebuilding that map, and rebuilding it is a behaviour-bearing change
to a live service that this round cannot verify against the running shell
(no live-session contact). A drift pin now, one reviewed rewiring in stage 2.

### 2. `Ai.qml` reads the catalog — stage 2

One commit series, all in `services/`:

- `Ai.qml.models` is built from `AiCatalog.builtinModels()`, with
  descriptions supplied as a `Translation.tr` map keyed by catalog id.
  `modelList`, `setModel`, `currentModelHasApiKey` and the strategy pick
  (`apiStrategies[dialect]`) read catalog records. Stored legacy model ids
  keep resolving via `resolve()`.
- Ollama discovery (`getOllamaModels`) builds catalog-shaped records through
  `buildModel(provider("ollama"), …)`; `guessModelName`/`guessModelLogo` move
  into the catalog (they are duplicated today between `Ai.qml` and
  `AiModelsParser.js` — a drift already in the tree).
- Custom providers and `extraModels` go through one catalog sanitiser (the
  fork's key-whitelist `sanitizeCustomModel` idea), folding
  `AiModelsParser.js` in; `tst_ai_custom_models.qml` moves with it.
- The local-only policy (`policies.ai === 2`) stops being
  `endpoint.includes("localhost")` and becomes a loopback-endpoint predicate
  in the catalog — the fork's `isLoopbackEndpoint` (127.0.0.0/8, `::1`,
  `unix://`, userinfo/bracket handling) is small enough to port near-verbatim
  **with the credit line** (ModelCatalog.qml, PR #98, author P3DROVFX).
- Fix the index-keyed custom-provider keyring ids: give each provider a
  stable generated id, key the keyring entry by it, and migrate existing
  `custom_provider_<i>` entries once (the keyring already has a lazy re-key
  precedent in `KeyringStorage`).
- `test_ai_catalog_contract.py` inverts: `Ai.qml` may declare **no** model
  literals.

No Config schema change is required for the core rewiring. The custom-provider
stable id wants one addition (an `id` field inside each `ai.customProviders`
entry — a `list<var>`, so no new declared property; written here per this
round's Config freeze).

### 3. New dialects the catalog can name: Anthropic — stage 3

- New `services/ai/AnthropicApiStrategy.qml`: `POST /v1/messages`, model in
  body, `x-api-key` + `anthropic-version` headers (both via the existing
  env-var route — the key never enters the script text), SSE parsing,
  `max_tokens` required, temperature capped at 1.0, thinking blocks parsed
  into the existing `thinking` message state. Their strategy (329 lines) is
  the reference; ours is written against our `ApiStrategy` base and message
  model, with credit if any parsing survives as written.
- Catalog: `anthropic` dialect record + provider (keyId `anthropic`, key link
  `https://console.anthropic.com/settings/keys`) + a small model list;
  capability flags per model (tools, vision, thinking).
- The contract test's dialect map gains the pair; the tool table (or, once
  stage 4 lands first, the registry's per-dialect projection) gains the
  anthropic tool schema.
- Verification limit, stated now: streaming against the real API needs a key
  and a network call, which agent rounds here do not make — the strategy's
  parser is pinned against recorded fixture lines, and the first live run is
  the maintainer's.

### 4. The permission vocabulary (`services/ai_tool_policy.js`) — stage 4

A second pure module, same pattern:

- One declaration per tool — our four to start — carrying the fork's
  vocabulary trimmed to what we enforce: `kind` (their seven-value scale,
  with risk *derived*, never declared beside it), `network`, `sensitivity`,
  `defaultApproval` (allow/ask/deny), `timeoutMs`, `maxResultTokens`, and the
  parameter schema **once**, with per-dialect projection functions replacing
  the three hand-kept copies in `Ai.qml.tools`. Our tools classify as:
  `get_shell_config` = localRead/device, `switch_to_search_mode` =
  navigation/network-required, `set_shell_config` = localWrite,
  `run_shell_command` = dangerous.
- Per-conversation grants: a plain `{toolId: "allow"|"ask"|"deny"}` object
  resolved as grant ?? per-tool default ?? `kind`-derived fallback (a write
  is never silently `allow`). The fork scoped grants per conversation
  (`04a2614`); ours ride the existing chat JSON (`chatToJson`/`loadChat`
  gain one field), so a restored conversation keeps its answers and a new
  one starts from defaults.
- Config keys this needs (written here, **not** into `Config.qml` this
  round — the schema is a hotspot owned elsewhere): per-tool default
  approvals. Note the trap for whoever lands it: a `JsonAdapter` cannot hold
  a dynamic map (AGENT.md), and tool ids are known at compile time, so this
  is a fixed `JsonObject` — e.g. `ai.tools.approvals` with one declared
  `property string` per tool — not a `property var` keyed by tool id.

### 5. The reviewed mutation — stage 5

`handleFunctionCall`'s if-chain becomes one road, the fork's broker shape
sized to four tools (ours will be well under their 512 lines):

- **Validate**: arguments checked against the registry's schema — coerce the
  fixable, drop unknown keys so a handler never sees a key it did not ask
  for.
- **Ask the policy at call time**, not at offer time: `allow` runs, `deny`
  answers the model with a refusal, `ask` raises the approval card —
  `set_shell_config` moves behind the same card `run_shell_command` already
  has (its `ask` default is the recommendation below), and the card gains
  the registry's title/summary so it can say *what* is being approved.
- **Run bounded**: `timeoutMs` from the registry; a result cut to
  `maxResultTokens` before it goes back on the wire.
- **Always answer**: every outcome — success, denial, timeout, rejection —
  produces a function-output message and continues the request, which fixes
  the stalled-turn hole in today's `set_shell_config` branch as a
  side effect of the shape rather than as a patch.

Files: `services/Ai.qml` (the dispatch), `services/ai_tool_policy.js` (the
pure halves: validation, resolution, truncation arithmetic), the approval
card in `modules/imi/sidebarLeft/aiChat/` generalised from
command-specific to registry-driven.

### Staged plan

| Stage | What | Files | Size | Status |
|---|---|---|---|---|
| 1 | Catalog as a pure module + drift pin | `services/ai_catalog.js`, `tests/tst_ai_catalog.qml`, `tests/test_ai_catalog_contract.py`, `tests/run_tests.sh` | Small (~800 lines, most of it tests) | **This branch** |
| 2 | `Ai.qml` reads the catalog; custom models through one sanitiser; loopback policy; stable custom-provider key ids | `services/Ai.qml`, `services/ai_catalog.js`, retire `services/AiModelsParser.js`, tests | Medium (~200-line service diff + tests) | Proposed |
| 3 | Anthropic dialect + Claude catalog entries | new `services/ai/AnthropicApiStrategy.qml`, `services/ai_catalog.js`, tests | Medium (~300 lines; live verification maintainer-run) | Proposed |
| 4 | Tool registry + permission vocabulary, per-conversation grants | new `services/ai_tool_policy.js`, `services/Ai.qml` (tool tables deleted), chat JSON field, tests | Small–medium (~250 lines + tests); Config keys deferred to schema owner | Proposed |
| 5 | Reviewed mutation: one validated, approvable, bounded, always-answering tool road | `services/Ai.qml`, `services/ai_tool_policy.js`, `modules/imi/sidebarLeft/aiChat/` approval card, tests | Medium (~300–400 lines) | Proposed |

Stages 2 and 3 are independent of 4 and 5; 5 depends on 4. Every stage keeps
the suite's shape: pure modules carry the decisions, `qmltestrunner` covers
them, a contract check pins whatever must not drift, and anything only a live
shell can show is verified per CONTRIBUTING's live loop by whoever deploys.

### How credentials stay keyring-only

Restated as a rule each stage is reviewed against, because the fork's stack
fails it wholesale:

- `services/KeyringStorage.qml` is the **only** credential store. The catalog
  carries key metadata (`keyId`, `keyGetLink`) and its purity check refuses
  the key plumbing's names in code.
- A key reaches a process as an environment variable or a positional
  argument — never interpolated into `bash -c` text, never written into the
  request script, never into `config.json`, presets, or any `.env`.
- No stage adds a file that could hold a secret. Per-conversation permission
  grants are approvals, not credentials, and live in chat JSON.

## Open questions (maintainer decisions, all flagged)

1. **Id scheme going forward.** The catalog's canonical ids are
   `provider:value` with legacy flat ids resolving. Should stage 2 keep
   *writing* legacy ids into `Persistent.states.ai.model` (safest, forever
   dual) or start writing canonical ids (needs `setModel` to accept both,
   which `resolve()` already gives, and a one-line read-side migration)?
2. **Ship Anthropic in the default catalog at all**, and if so which models —
   a named model list is a maintenance commitment (the fork tracks theirs by
   hand). Alternative: ship the dialect only, and let users add Claude models
   as catalog-shaped custom entries.
3. **Ollama tool default.** Today every local model is offered the function
   table; the fork defaults local models to `tools: false` because the daemon
   does not say which can. The catalog currently records the status quo so
   wiring it in changes nothing — flipping the default is a behaviour change
   that needs your call (and a per-model override either way).
4. **Custom-provider keyring migration** (stage 2): re-keying
   `custom_provider_<i>` entries to stable ids touches the user keyring; the
   index-drift defect argues for it, but it is a migration and those get
   review here.
5. **`set_shell_config` behind the approval card** (stage 5): recommended
   `ask` by default — it is a write to the user's config by a language model —
   but it is a behaviour change to a shipped feature.
6. **Where per-conversation grants persist**: chat JSON (proposed — survives
   reload with the conversation) vs session-only (stricter: every session
   re-asks).
7. **The settings surface.** ServicesConfig's AI section eventually renders
   the catalog (provider rows from `providers()` instead of hand-built
   controls) and stage 4's defaults want a Tools section. Settings pages are
   owned elsewhere this round, so both are listed as follow-ups for whoever
   owns that surface, with the data model ready.
8. **Local-only policy strictness** (stage 2): adopting the loopback
   predicate makes `policies.ai === 2` *stricter* (a custom model pointing a
   `localhost` path at a remote host via DNS tricks still passes today's
   substring check; a non-loopback "local" daemon on a LAN host stops
   passing). Confirm the boundary is "loopback", not "user says local".

## Out of scope

Each of these is in the fork's rebuild and deliberately not in this proposal:

- **RAG** (`scripts/ai/ai_rag.py`, `AiRagService.qml`): an embeddings
  pipeline, an on-disk vector store, and a background indexer over the user's
  files — a separate subsystem with its own privacy surface and its own
  failure modes, orthogonal to all three shapes here. If ever wanted, it is
  its own proposal with its own data-retention answers.
- **Gmail / Google integrations** (~11,500 lines, `gmail.modify` +
  `gmail.send` scopes): excluded categorically by survey §6 — the OAuth
  client secrets and tokens live in their plaintext `.env` (their 2026-08-19
  work moved *more* credentials into it), and their `oauth_server.py` prints
  the refresh token to stdout, which the shell captures into its log. There
  is no version of this that comes over by accident; it would need its own
  proposal and a ground-up keyring OAuth story.
- **Sports scores** (ESPN): an undocumented third-party endpoint scraped
  without a contract — churn we would own forever for a widget with no
  relation to the assistant's job. No.
- **OpenRouter / Ollama catalog browsing with model pulls**: a store-like
  network browsing surface (search remote catalogs, download models) with its
  own review needs. Our custom-provider `/models` fetch already answers "what
  can my key reach"; the catalog shape does not preclude adding browsing
  later, and nothing here depends on it.
- **Also not here**, for the record: the conversation-repository rebuild (our
  chat JSON gains one field in stage 4 and is otherwise sufficient), the
  usage/cost dashboard (wants per-model price data the catalog could carry
  someday, but the dashboard is its own surface), personas/memory/attention
  hooks, and dictation (delta §2.3 — a separate feature with its own entry on
  the shortlist).
