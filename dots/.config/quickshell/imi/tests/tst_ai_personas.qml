import QtQuick
import QtTest
import "../services/ai/ai_personas.js" as Personas

TestCase {
    name: "AiPersonasFold"

    readonly property var builtIns: [
        { id: "shell", name: "Shell", systemPrompt: "S", temperature: 0.3 },
        { id: "plain", name: "Plain", systemPrompt: "P", temperature: 0.5 },
    ]

    function test_user_persona_shadows_builtin_by_id() {
        const rows = Personas.resolved(builtIns, [{ id: "shell", name: "Mine", systemPrompt: "M" }]);
        compare(rows.length, 2);
        compare(rows[0].name, "Mine", "the user's copy shadows in place");
        compare(rows[1].id, "plain");
    }

    function test_user_only_personas_append() {
        const rows = Personas.resolved(builtIns, [{ id: "extra", name: "X", systemPrompt: "E" }]);
        compare(rows.length, 3);
        compare(rows[2].id, "extra");
    }

    function test_junk_user_rows_are_dropped() {
        const rows = Personas.resolved(builtIns, [null, {}, { id: "" }]);
        compare(rows.length, 2);
    }

    function test_lookup_and_effective_prompt() {
        const rows = Personas.resolved(builtIns, []);
        compare(Personas.personaById(rows, "plain").systemPrompt, "P");
        compare(Personas.personaById(rows, ""), null);
        compare(Personas.personaById(rows, "nope"), null);
        compare(Personas.effectivePrompt(rows[0], "custom"), "S", "an active persona wins");
        compare(Personas.effectivePrompt(null, "custom"), "custom", "no persona = the free-text card");
        compare(Personas.effectivePrompt({ id: "x", systemPrompt: "" }, "custom"), "custom", "an empty persona prompt falls through");
    }
}
