# AI Model Catalog & OpenRouter Browse — Design

**Date:** 2026-08-31
**Status:** Approved (brainstorm 2026-08-31; the completion round's first half, after built-ins were removed - the user brings providers, and this makes bringing MODELS first-class)

## Decisions

1. **Capability metadata on AiModel:** `thinking: false` (the reasoning ask
   already reads it), `vision: false`, `contextWindow: 0`. The existing
   `tools` property is the request schema list and keeps its name - the
   capability flags do not collide with it.
2. **Imported models land in the existing `extraModels`** config list -
   already the per-model home, migration-free; entries may carry the
   capability keys.
3. **OpenRouter browse-and-import is a sidebar canvas view** (user's call):
   the third view on AiChat's switcher, keys/sessions grammar. A read-only
   remote index; nothing auto-imports - a click imports one model
   explicitly and selects it.
4. **Entry points:** a sentinel "Browse models…" row at the composer
   picker's foot, and the same door from the keys view.
5. **Deviation from the presented design, reasoned:** the attach-affordance
   vision gate is DROPPED. Provider-fetched models cannot declare vision,
   so `vision: false` defaults would produce false "can't see images"
   warnings on models that see fine (the user's GPT endpoint). `vision` is
   stored and shown in the browse rows; enforcement waits until the
   metadata can be trusted.

## Pieces

### `services/ai/openrouter_models.js` (pure, tested)

- `rowFor(raw)` → `{ id, name, provider, contextWindow, promptPrice,
  completionPrice, vision, reasoning }` from an OpenRouter `/models` entry:
  provider is the id's prefix before "/", vision = input_modalities
  contains "image", reasoning = supported_parameters contains "reasoning"
  or "include_reasoning"; prices parsed as numbers (per-token strings).
- `filterRows(rows, query)` - case-insensitive name/id/provider match.
- `importEntry(row)` → an extraModels entry: `{ name, icon: "" ,
  description: "OpenRouter | <id>", endpoint:
  "https://openrouter.ai/api/v1/chat/completions", model: row.id,
  requires_key: true, key_id: "openrouter", api_format: "openai",
  thinking: row.reasoning, vision: row.vision, contextWindow:
  row.contextWindow }`.
- `withImported(extraModels, entry)` - copy-on-write append, deduped by
  `model`.
- `priceLabel(prompt, completion)` - "$0.30/$2.50 per M" style, "free"
  when both zero.

### `services/ai/OpenRouterModels.qml` (singleton)

Fork's shape: `endpoint` (`/api/v1/models?output_modalities=text&sort=
most-popular`), `models` (mapped rows), `loading`, `error`, `fetchedAt`,
5-minute cache, `refresh(force)` via a curl Process. Read-only; no writes
anywhere.

### `AiModel.qml`

Gains the three capability properties with the defaults above.

### Browse view (`modules/imi/sidebarLeft/aiChat/BrowseModelsView.qml`)

Third canvas view (`activeView === "browse"`), keys/sessions grammar: back
arrow + "Browse models" title; an OpenRouter API-key row (keyring
`apiKeys.openrouter`, focus-guarded like the providers editor); a search
field; the rows - name, provider tag, context chip, price label,
reasoning/vision glyphs - capped at 60 after filtering with a "type to
narrow" hint; loading and error states from the singleton. A click:
`Config.options.ai.extraModels = withImported(...)`, `Ai.addUserModels()`,
`Ai.setModel(safeName)`, close the view.

### Wiring

- Picker model gains the sentinel row `{ name: "Browse models…", value:
  "__browse__" }`; `onActivated` on the sentinel opens the view and
  resyncs `currentIndex` back to the real selection.
- Keys view gains a "Browse OpenRouter models" EmptyStateKey-style row.
- The reasoning ask and the browse rows read the new capability keys;
  nothing else enforces them yet (decision 5).

## Testing

`tests/tst_openrouter_models.qml` over the js: row mapping (vision/
reasoning/provider/prices), filter, import entry shape, dedupe, price
labels. Pins (skeleton contract grows): the browse view rides the one
switcher; the import path writes `extraModels` only.

## Out of scope

Auto-import, pricing-based sorting UI, per-model settings pages, catalog
ids ("provider:value") - imi keeps its flat safe names.
