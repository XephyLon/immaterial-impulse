import QtQuick
import QtTest
import "../services/ai/ai_tool_registry.js" as Reg

TestCase {
    name: "AiToolRegistryFold"

    readonly property var defs: [
        { name: "a", description: "A", dialects: ["openai", "gemini", "mistral"],
          parameters: { type: "object", properties: { x: { type: "string" } }, required: ["x"] } },
        { name: "b", description: "B", dialects: ["gemini"] },
        { name: "c", description: "C", dialects: ["openai"] },
    ]

    function test_dialect_filter_and_openai_shape() {
        const oa = Reg.toOpenAiTools(defs, "openai");
        compare(oa.length, 2);
        compare(oa[0].type, "function");
        compare(oa[0].function.name, "a");
        compare(oa[0].function.parameters.required[0], "x");
        compare(oa[1].function.name, "c");
        compare(oa[1].function.parameters !== undefined, true, "no params renders {}");
        compare(Reg.toOpenAiTools(defs, "mistral").length, 1);
    }

    function test_gemini_shape_omits_empty_parameters() {
        const g = Reg.toGeminiDeclarations(defs);
        compare(g.length, 2);
        compare(g[0].name, "a");
        verify(g[0].parameters !== undefined);
        compare(g[1].name, "b");
        verify(g[1].parameters === undefined, "a parameterless tool omits the key");
    }

    function test_anthropic_shape_always_carries_a_schema() {
        const defs2 = [
            { name: "a", description: "A", dialects: ["anthropic"],
              parameters: { type: "object", properties: { x: { type: "string" } } } },
            { name: "b", description: "B", dialects: ["anthropic"] },
        ];
        const at = Reg.toAnthropicTools(defs2);
        compare(at.length, 2);
        compare(at[0].input_schema.properties.x.type, "string");
        compare(at[1].input_schema.type, "object", "parameterless still schemas");
        verify(at[0].type === undefined, "no openai wrapper");
    }

    function test_names() {
        compare(Reg.namesFor(defs, "gemini").join(","), "a,b");
        compare(Reg.allNames(defs).join(","), "a,b,c");
    }
}
