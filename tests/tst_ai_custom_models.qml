import QtQuick
import QtTest
import "../services/AiModelsParser.js" as AiModelsParser

TestCase {
    name: "AiCustomModelsTest"

    function test_parseCustomProviderModels() {
        // Valid response
        var validResponse = JSON.stringify({
            data: [
                { id: "model-1", name: "Model 1" },
                { id: "model-2" }
            ]
        });

        var parsed = AiModelsParser.parseCustomProviderModels(validResponse, "https://api.example.com/", "Example")
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
        var parsedNoSlash = AiModelsParser.parseCustomProviderModels(validResponse, "https://api.example.com", "Example")
        compare(parsedNoSlash[0].endpoint, "https://api.example.com/chat/completions")

        // Invalid JSON
        var parsedInvalid = AiModelsParser.parseCustomProviderModels("invalid json", "https://api.example.com", "Example")
        compare(parsedInvalid.length, 0)

        // Missing data array
        var parsedMissingData = AiModelsParser.parseCustomProviderModels(JSON.stringify({ other: "data" }), "https://api.example.com", "Example")
        compare(parsedMissingData.length, 0)

        // Empty response
        var parsedEmpty = AiModelsParser.parseCustomProviderModels("", "https://api.example.com", "Example")
        compare(parsedEmpty.length, 0)
    }
}
