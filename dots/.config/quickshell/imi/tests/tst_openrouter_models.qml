import QtTest
import "../services/ai/openrouter_models.js" as OR

// OpenRouter's /models entries as the shell's rows and imports - the
// mapping decisions live here, under a test, not inside a view.
TestCase {
    name: "OpenRouterModelsTest"

    readonly property var raw: ({
        id: "deepseek/deepseek-v4-flash",
        name: "DeepSeek: V4 Flash",
        context_length: 1310720,
        pricing: { prompt: "0.000000065", completion: "0.00000018" },
        architecture: { input_modalities: ["text", "image"] },
        supported_parameters: ["temperature", "reasoning", "tools"]
    })

    function test_row_mapping() {
        const row = OR.rowFor(raw);
        compare(row.id, "deepseek/deepseek-v4-flash");
        compare(row.provider, "deepseek");
        compare(row.contextWindow, 1310720);
        verify(row.vision);
        verify(row.reasoning);
        verify(Math.abs(row.promptPrice - 0.000000065) < 1e-12);
    }

    function test_row_mapping_defaults() {
        const row = OR.rowFor({ id: "x", name: "X" });
        compare(row.provider, "x");
        compare(row.contextWindow, 0);
        verify(!row.vision);
        verify(!row.reasoning);
        compare(row.promptPrice, 0);
    }

    function test_filter() {
        const rows = [OR.rowFor(raw), OR.rowFor({ id: "openai/gpt-5", name: "GPT-5" })];
        compare(OR.filterRows(rows, "deep").length, 1);
        compare(OR.filterRows(rows, "OPENAI").length, 1);
        compare(OR.filterRows(rows, "").length, 2);
    }

    function test_import_entry_and_dedupe() {
        const entry = OR.importEntry(OR.rowFor(raw));
        compare(entry.model, "deepseek/deepseek-v4-flash");
        compare(entry.key_id, "openrouter");
        compare(entry.api_format, "openai");
        verify(entry.thinking);
        verify(entry.vision);
        compare(entry.endpoint, "https://openrouter.ai/api/v1/chat/completions");
        const one = OR.withImported([], entry);
        const two = OR.withImported(one, entry);
        compare(two.length, 1, "deduped by model id");
    }

    function test_price_label() {
        compare(OR.priceLabel(0, 0), "free");
        verify(OR.priceLabel(0.000000065, 0.00000018).indexOf("/M") !== -1);
    }
}
