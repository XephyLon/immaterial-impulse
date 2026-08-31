.pragma library

// The AI provider/model catalog: every provider and built-in model the shell
// knows, described in one place - id, display name, API dialect, endpoint
// shape, capability flags, key metadata - so the chat service, the settings
// page and the tests read one answer instead of each keeping a copy.
//
// Pure on purpose, like services/frecency.js and services/sound_theme.js:
// no Qt, no Config, no Translation, no processes. services/Ai.qml owns the
// processes, the keyring reads and the request lifecycle; this owns the data
// and the lookups, which is what makes them reachable from qmltestrunner.
//
// Two things deliberately stay OUT of this file:
// - Translated strings. Model descriptions are Translation.tr(...) literals,
//   and the translation extractor only sees that form (see AGENT.md on
//   BarWidgets), so they stay in QML, keyed by the ids declared here.
// - Key MATERIAL. The catalog carries key metadata (keyId, keyGetLink);
//   the keys themselves live in the keyring, read only by services/Ai.qml
//   through services/KeyringStorage.qml. Nothing here may ever hold one.
//
// Until services/Ai.qml reads this catalog (stage 2 of
// docs/proposals/ai-assistant-upgrade.md), the built-in model literals exist
// twice - here and in Ai.qml's `models` map - and
// tests/test_ai_catalog_contract.py pins the two copies equal so neither can
// drift while the wiring waits.
//
// Ids are "provider:value" (stable across renames of either display name).
// Today's Ai.qml keys its models by hand-chosen flat names; each model
// records that name as `legacyId`, and resolve() answers both, so stage 2
// needs no Persistent migration for a saved model choice.

// How a dialect's requests are shaped. `id` must match a strategy in
// services/ai/ (Ai.qml's `apiStrategies` keys); the contract test pins that.
// - endpointShape: where the model name goes. "model-in-path" bakes it into
//   the URL (the {model} slot in the provider's endpoint template);
//   "chat-completions" posts it in the request body to a fixed URL.
// - auth: how the key travels. "query-key" appends ?key=..., "bearer-header"
//   sends Authorization: Bearer. Either way the key reaches curl through an
//   environment variable, never spliced into the script text.
// - streaming: "json-array" is Gemini's streamed JSON array;
//   "sse" is data:-prefixed server-sent events with a [DONE] terminator.
var DIALECTS = {
    "gemini": {
        "id": "gemini",
        "endpointShape": "model-in-path",
        "auth": "query-key",
        "streaming": "json-array"
    },
    "openai": {
        "id": "openai",
        "endpointShape": "chat-completions",
        "auth": "bearer-header",
        "streaming": "sse"
    },
    // Same wire shape as "openai"; a separate dialect because the
    // function-call/tool-response message turns differ enough to need their
    // own strategy (see services/ai/MistralApiStrategy.qml).
    "mistral": {
        "id": "mistral",
        "endpointShape": "chat-completions",
        "auth": "bearer-header",
        "streaming": "sse"
    },
    // The Anthropic Messages API: /v1/messages, x-api-key auth, typed SSE
    // events (see services/ai/AnthropicApiStrategy.qml). Keep quote marks
    // and apostrophes out of comments inside this object - the catalog
    // contract brace-parser reads them as opened strings.
    "anthropic": {
        "id": "anthropic",
        "endpointShape": "messages",
        "auth": "x-api-key-header",
        "streaming": "sse"
    }
};

// Capability flags describe what the shell can DO with the model today, not
// the vendor's brochure: `tools` = this dialect's function-calling table is
// offered, `vision` = a file can be attached and sent (only the gemini
// strategy builds a file-upload step), `thinking` = the model emits a
// reasoning phase the strategy already parses. Provider-level defaults,
// overridden per model; buildModel() does the merge.
var PROVIDERS = [
    {
        "id": "google",
        "name": "Google",
        "icon": "google-gemini-symbolic",
        "dialect": "gemini",
        "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent",
        "requiresKey": true,
        "keyId": "gemini",
        "keyGetLink": "https://aistudio.google.com/app/apikey",
        "homepage": "https://aistudio.google.com",
        "capabilities": { "tools": true, "vision": true, "thinking": true },
        "models": [
            {
                "value": "gemini-3-flash-preview",
                "name": "Gemini 3 Flash",
                "legacyId": "gemini-3-flash"
            },
            {
                "value": "gemini-2.5-flash",
                "name": "Gemini 2.5 Flash",
                "legacyId": "gemini-2.5-flash"
            }
        ]
    },
    {
        "id": "mistral",
        "name": "Mistral",
        "icon": "mistral-symbolic",
        "dialect": "mistral",
        "endpoint": "https://api.mistral.ai/v1/chat/completions",
        "requiresKey": true,
        "keyId": "mistral",
        "keyGetLink": "https://console.mistral.ai/api-keys",
        "homepage": "https://mistral.ai/news/mistral-medium-3",
        "capabilities": { "tools": true, "vision": false, "thinking": false },
        "models": [
            {
                "value": "mistral-medium-2505",
                "name": "Mistral Medium 3",
                "legacyId": "mistral-medium-3"
            }
        ]
    },
    // Models are discovered from the local daemon at runtime (Ai.qml's
    // show-installed-ollama-models.sh); the provider record is here so the
    // discovery path builds catalog-shaped records instead of its own.
    // `tools: true` is the status quo - the shell currently offers the openai
    // function table to every local model - kept so wiring the catalog in
    // changes nothing; whether local models should default to no tools (the
    // sibling fork's choice) is an open question in the proposal.
    {
        "id": "ollama",
        "name": "Ollama",
        "icon": "ollama-symbolic",
        "dialect": "openai",
        "endpoint": "http://localhost:11434/v1/chat/completions",
        "requiresKey": false,
        "keyId": "",
        "keyGetLink": "",
        "homepage": "https://ollama.com",
        "local": true,
        "discovered": true,
        "capabilities": { "tools": true, "vision": false, "thinking": false },
        "models": []
    }
];

function _copyCapabilities(caps) {
    return {
        "tools": caps.tools === true,
        "vision": caps.vision === true,
        "thinking": caps.thinking === true
    };
}

/** The endpoint template with its {model} slot filled. A template without
 *  the slot (chat-completions dialects) is returned as-is. */
function resolveEndpoint(template, modelValue) {
    return String(template).split("{model}").join(modelValue);
}

/**
 * One model record from a provider definition and a model entry: the
 * provider supplies the defaults, the entry overrides field by field.
 * Exposed (rather than folded into builtinModels) so the merge rules are
 * testable with synthetic inputs, and so stage 2's custom-model path can
 * build records the same way.
 */
function buildModel(providerDef, entry) {
    if (!entry || entry.value === undefined || String(entry.value).length === 0)
        return null;
    var value = String(entry.value);
    var caps = _copyCapabilities(providerDef.capabilities || {});
    var overrides = entry.capabilities || {};
    for (var key in caps) {
        if (overrides[key] !== undefined)
            caps[key] = overrides[key] === true;
    }
    return {
        "id": providerDef.id + ":" + value,
        // Normalized to a string here so resolve() may ask .length without
        // ceremony: stage 2's extraModels feed is user-authored JSON, where
        // a null legacyId is one typo away.
        "legacyId": typeof entry.legacyId === "string" ? entry.legacyId : "",
        "providerId": providerDef.id,
        "value": value,
        "name": entry.name !== undefined ? entry.name : value,
        "icon": entry.icon !== undefined ? entry.icon : (providerDef.icon || ""),
        "dialect": entry.dialect !== undefined ? entry.dialect : providerDef.dialect,
        "endpoint": resolveEndpoint(
            entry.endpoint !== undefined ? entry.endpoint : providerDef.endpoint, value),
        "requiresKey": entry.requiresKey !== undefined
            ? entry.requiresKey === true : providerDef.requiresKey === true,
        "keyId": entry.keyId !== undefined ? entry.keyId : (providerDef.keyId || ""),
        "keyGetLink": entry.keyGetLink !== undefined
            ? entry.keyGetLink : (providerDef.keyGetLink || ""),
        "homepage": entry.homepage !== undefined
            ? entry.homepage : (providerDef.homepage || ""),
        "capabilities": caps
    };
}

function _providerRecord(def) {
    var models = [];
    for (var i = 0; i < def.models.length; i++) {
        var model = buildModel(def, def.models[i]);
        if (model !== null)
            models.push(model);
    }
    return {
        "id": def.id,
        "name": def.name,
        "icon": def.icon || "",
        "dialect": def.dialect,
        "endpoint": def.endpoint,
        "requiresKey": def.requiresKey === true,
        "keyId": def.keyId || "",
        "keyGetLink": def.keyGetLink || "",
        "homepage": def.homepage || "",
        "local": def.local === true,
        "discovered": def.discovered === true,
        "capabilities": _copyCapabilities(def.capabilities || {}),
        "models": models
    };
}

/** Dialect records, keyed by id. Fresh objects per call. */
function dialects() {
    var result = {};
    for (var id in DIALECTS) {
        var d = DIALECTS[id];
        result[id] = {
            "id": d.id,
            "endpointShape": d.endpointShape,
            "auth": d.auth,
            "streaming": d.streaming
        };
    }
    return result;
}

/** Provider records with their built-in models resolved, in catalog order. */
function providers() {
    var result = [];
    for (var i = 0; i < PROVIDERS.length; i++)
        result.push(_providerRecord(PROVIDERS[i]));
    return result;
}

/** Every built-in model, flat, in catalog order. */
function builtinModels() {
    var result = [];
    var provs = providers();
    for (var i = 0; i < provs.length; i++) {
        for (var j = 0; j < provs[i].models.length; j++)
            result.push(provs[i].models[j]);
    }
    return result;
}

/** The provider record for an id, or null. */
function provider(id) {
    for (var i = 0; i < PROVIDERS.length; i++) {
        if (PROVIDERS[i].id === id)
            return _providerRecord(PROVIDERS[i]);
    }
    return null;
}

/**
 * The model for an id, or null. Answers the canonical "provider:value" id
 * and the legacy flat id today's Ai.qml (and every stored
 * Persistent.states.ai.model) uses, so a saved model choice keeps resolving
 * when the catalog takes over.
 */
function resolve(id) {
    if (id === undefined || id === null || String(id).length === 0)
        return null;
    var wanted = String(id);
    var models = builtinModels();
    for (var i = 0; i < models.length; i++) {
        if (models[i].id === wanted)
            return models[i];
    }
    for (var j = 0; j < models.length; j++) {
        if (typeof models[j].legacyId === "string" && models[j].legacyId.length > 0
                && models[j].legacyId === wanted)
            return models[j];
    }
    return null;
}
