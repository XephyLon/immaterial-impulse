import QtQuick
import QtTest
import "../services/ai_catalog.js" as AiCatalog

TestCase {
    name: "AiCatalogTest"

    function test_dialect_vocabulary_is_closed_and_complete() {
        const dialects = AiCatalog.dialects()
        const ids = Object.keys(dialects).sort()
        // Exactly the strategies services/ai/ implements today. A fourth
        // dialect lands here together with its strategy file, or the
        // contract check reddens.
        compare(ids.join(","), "anthropic,gemini,mistral,openai")
        for (const id of ids) {
            compare(dialects[id].id, id)
            verify(dialects[id].endpointShape.length > 0)
            verify(dialects[id].auth.length > 0)
            verify(dialects[id].streaming.length > 0)
        }
        compare(dialects["gemini"].endpointShape, "model-in-path")
        compare(dialects["gemini"].auth, "query-key")
        compare(dialects["openai"].endpointShape, "chat-completions")
        compare(dialects["openai"].auth, "bearer-header")
    }

    function test_every_model_names_a_declared_dialect() {
        const dialects = AiCatalog.dialects()
        for (const provider of AiCatalog.providers()) {
            verify(dialects[provider.dialect] !== undefined,
                   `provider ${provider.id} names undeclared dialect ${provider.dialect}`)
            for (const model of provider.models) {
                verify(dialects[model.dialect] !== undefined,
                       `model ${model.id} names undeclared dialect ${model.dialect}`)
            }
        }
    }

    function test_builtin_models_carry_the_full_record() {
        const models = AiCatalog.builtinModels()
        verify(models.length >= 3)
        for (const model of models) {
            compare(model.id, `${model.providerId}:${model.value}`)
            verify(model.name.length > 0)
            verify(model.endpoint.length > 0)
            verify(model.endpoint.indexOf("{model}") === -1,
                   `unresolved endpoint template in ${model.id}`)
            compare(typeof model.capabilities.tools, "boolean")
            compare(typeof model.capabilities.vision, "boolean")
            compare(typeof model.capabilities.thinking, "boolean")
            if (model.requiresKey)
                verify(model.keyId.length > 0,
                       `${model.id} requires a key but names no keyId`)
        }
    }

    function test_model_in_path_endpoints_resolve_the_model_slot() {
        const gemini3 = AiCatalog.resolve("google:gemini-3-flash-preview")
        verify(gemini3 !== null)
        compare(gemini3.endpoint,
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent")
        // A chat-completions endpoint has no slot and passes through whole.
        const mistral = AiCatalog.resolve("mistral:mistral-medium-2505")
        verify(mistral !== null)
        compare(mistral.endpoint, "https://api.mistral.ai/v1/chat/completions")
    }

    function test_legacy_ids_resolve_to_the_same_record() {
        // Today's Ai.qml keys, i.e. what Persistent.states.ai.model can hold.
        const pairs = [
            ["gemini-3-flash", "google:gemini-3-flash-preview"],
            ["gemini-2.5-flash", "google:gemini-2.5-flash"],
            ["mistral-medium-3", "mistral:mistral-medium-2505"],
        ]
        for (const [legacy, canonical] of pairs) {
            const viaLegacy = AiCatalog.resolve(legacy)
            const viaCanonical = AiCatalog.resolve(canonical)
            verify(viaLegacy !== null, `legacy id ${legacy} did not resolve`)
            compare(viaLegacy.id, viaCanonical.id)
            compare(viaLegacy.endpoint, viaCanonical.endpoint)
        }
    }

    function test_unknown_and_empty_ids_resolve_to_null() {
        compare(AiCatalog.resolve("no-such-model"), null)
        compare(AiCatalog.resolve("google:no-such-model"), null)
        compare(AiCatalog.resolve(""), null)
        compare(AiCatalog.resolve(undefined), null)
        compare(AiCatalog.resolve(null), null)
    }

    function test_provider_lookup() {
        const google = AiCatalog.provider("google")
        verify(google !== null)
        compare(google.dialect, "gemini")
        compare(google.models.length, 2)
        compare(AiCatalog.provider("no-such-provider"), null)

        const ollama = AiCatalog.provider("ollama")
        verify(ollama !== null)
        verify(ollama.local)
        verify(ollama.discovered)
        compare(ollama.requiresKey, false)
        compare(ollama.models.length, 0)
    }

    function test_build_model_merges_provider_defaults_under_entry_overrides() {
        const providerDef = {
            "id": "p",
            "name": "P",
            "icon": "p-icon",
            "dialect": "openai",
            "endpoint": "https://p.example/v1/chat/completions",
            "requiresKey": true,
            "keyId": "p",
            "keyGetLink": "https://p.example/keys",
            "capabilities": { "tools": true, "vision": true, "thinking": false }
        }
        const model = AiCatalog.buildModel(providerDef, {
            "value": "m-1",
            "capabilities": { "vision": false, "thinking": true },
            "requiresKey": false
        })
        compare(model.id, "p:m-1")
        compare(model.name, "m-1")           // falls back to the value
        compare(model.icon, "p-icon")        // provider default
        compare(model.dialect, "openai")
        // Entry override wins per flag; untouched flags keep the default.
        compare(model.capabilities.tools, true)
        compare(model.capabilities.vision, false)
        compare(model.capabilities.thinking, true)
        compare(model.requiresKey, false)
    }

    function test_build_model_refuses_an_entry_with_no_value() {
        const providerDef = AiCatalog.providers()[0]
        compare(AiCatalog.buildModel(providerDef, {}), null)
        compare(AiCatalog.buildModel(providerDef, { "value": "" }), null)
        compare(AiCatalog.buildModel(providerDef, null), null)
    }

    function test_resolve_endpoint() {
        compare(AiCatalog.resolveEndpoint("https://x/{model}:stream", "m"),
                "https://x/m:stream")
        compare(AiCatalog.resolveEndpoint("https://x/v1/chat/completions", "m"),
                "https://x/v1/chat/completions")
    }

    function test_returned_records_are_fresh_copies() {
        // A caller mutating what it got back must not corrupt later answers.
        const first = AiCatalog.resolve("google:gemini-2.5-flash")
        first.endpoint = "https://tampered.example"
        first.capabilities.tools = false
        const second = AiCatalog.resolve("google:gemini-2.5-flash")
        verify(second.endpoint.indexOf("generativelanguage") !== -1)
        compare(second.capabilities.tools, true)
    }
}
