import QtQuick
import QtTest
import "../services/AiModelsParser.js" as AiModelsParser

TestCase {
    name: "AiCustomModelsTest"

    function test_normalizeBaseUrl() {
        // What a base URL pasted from a browser bar looks like, and what the
        // fetch needs: the fetch appends /models, so a base that already ends
        // there produced /v1/models/models - a 404 with an empty body.
        compare(AiModelsParser.normalizeBaseUrl("http://127.0.0.1:8317/v1/models"), "http://127.0.0.1:8317/v1")
        compare(AiModelsParser.normalizeBaseUrl("https://api.example.com/v1/"), "https://api.example.com/v1")
        compare(AiModelsParser.normalizeBaseUrl("https://api.example.com/v1/chat/completions"), "https://api.example.com/v1")
        compare(AiModelsParser.normalizeBaseUrl("  https://api.example.com/v1  "), "https://api.example.com/v1")
        compare(AiModelsParser.normalizeBaseUrl("https://api.example.com/v1/MODELS/"), "https://api.example.com/v1")
        compare(AiModelsParser.normalizeBaseUrl(""), "")
        compare(AiModelsParser.normalizeBaseUrl(undefined), "")
        // ...and the endpoint built from a base that ended in /models
        var parsed = AiModelsParser.parseCustomProviderModels(JSON.stringify({ data: [{ id: "m" }] }), "http://127.0.0.1:8317/v1/models", "CLIP", "custom_provider_0")
        compare(parsed[0].endpoint, "http://127.0.0.1:8317/v1/chat/completions")
    }

    function test_parseCustomProviderModels() {
        // Valid response
        var validResponse = JSON.stringify({
            data: [
                { id: "model-1", name: "Model 1" },
                { id: "model-2" }
            ]
        });

        var parsed = AiModelsParser.parseCustomProviderModels(validResponse, "https://api.example.com/", "Example", "custom_provider")
        compare(parsed.length, 2)

        compare(parsed[0].model, "model-1")
        compare(parsed[0].endpoint, "https://api.example.com/chat/completions")
        compare(parsed[0].requires_key, true)
        compare(parsed[0].key_id, "custom_provider")
        compare(parsed[0].api_format, "openai")
        verify(parsed[0].description.indexOf("Example") !== -1)

        compare(parsed[1].model, "model-2")
        verify(parsed[1].name !== undefined)

        // No trailing slash baseUrl
        var parsedNoSlash = AiModelsParser.parseCustomProviderModels(validResponse, "https://api.example.com", "Example", "custom_provider")
        compare(parsedNoSlash[0].endpoint, "https://api.example.com/chat/completions")

        // Invalid JSON
        var parsedInvalid = AiModelsParser.parseCustomProviderModels("invalid json", "https://api.example.com", "Example", "custom_provider")
        compare(parsedInvalid.length, 0)

        // Missing data array
        var parsedMissingData = AiModelsParser.parseCustomProviderModels(JSON.stringify({ other: "data" }), "https://api.example.com", "Example", "custom_provider")
        compare(parsedMissingData.length, 0)

        // Empty response
        var parsedEmpty = AiModelsParser.parseCustomProviderModels("", "https://api.example.com", "Example", "custom_provider")
        compare(parsedEmpty.length, 0)
    }
}
