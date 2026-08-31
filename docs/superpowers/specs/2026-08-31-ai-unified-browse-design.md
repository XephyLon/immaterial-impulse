# AI Unified Browse & Curation — Design

**Date:** 2026-08-31
**Status:** Approved (user, 2026-08-31: browse shows models from ALL providers merged; naming is "<ProviderName>: <Model>"; the back arrow returns to the opening view - shipped separately as viewReturnTo)

## Decisions

1. **One merged browse list**: every enabled custom provider's fetched
   models plus the OpenRouter index, one search across all. No source
   dropdown.
2. **Naming convention** `<ProviderName>: <Model>` applied AT THE PARSER
   (`parseCustomProviderModels` prefixes the provider's name), so the
   picker, the message headers and the browse rows all agree for free.
3. **Curation per provider**: `customProviders[i].selectedModels: []` -
   empty surfaces everything (small-provider ergonomics unchanged, no
   flood guard - the user's merged-list call supersedes it); non-empty
   surfaces only the named model ids. Browse rows for provider models
   carry a surfaced check-toggle writing that list; OpenRouter rows keep
   the import-copy behavior (their entries need endpoint+key baked in).
4. **Picker** filters provider-fetched models by their provider's
   selection; `extraModels` imports are always surfaced.

## Pieces

- `services/ai/model_curation.js` (pure): `isSurfaced(selected, id)`
  (empty list -> true), `withToggled(selected, id)` copy-fold,
  `providerIndexOf(keyId)` ("custom_provider_2" -> 2, else -1).
- Parser: entries gain `providerName`; `name` becomes
  `${providerName}: ${guessModelName(id)}`.
- `Ai.pickerModelList`: drops provider-fetched models whose provider's
  `selectedModels` is non-empty and misses their raw id.
- Browse view: merged rows - provider rows derived from `Ai.models`
  (kind "provider", check-toggle bound to the selection fold) followed by
  OpenRouter rows (kind "openrouter", import as today); one filter box
  over both; provider rows sort first.

## Testing

`tests/tst_model_curation.qml` over the fold; the catalog contract's
parser fixture pin follows the new name shape; skeleton pins gain: the
picker filter reads the curation fold, browse toggles write only
`customProviders[i].selectedModels`.

## Out of scope

Flood guards, per-source tabs, provider-row pricing (their /models carry
none), un-importing OpenRouter entries from browse (delete via config).
