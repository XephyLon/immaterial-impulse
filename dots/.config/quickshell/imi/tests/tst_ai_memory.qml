import QtQuick
import QtTest
import "../services/ai/ai_memory.js" as Mem

TestCase {
    name: "AiMemoryFold"

    function test_facts_append_dedupe_and_cap() {
        let f = Mem.withFact([], "Uses Arch", "a", 1, "user", 3);
        f = Mem.withFact(f, "uses arch", "b", 2, "model", 3);
        compare(f.length, 1, "case-insensitive dedupe");
        f = Mem.withFact(f, "Edits in nvim", "c", 3, "user", 3);
        f = Mem.withFact(f, "Prefers terse reviews", "d", 4, "user", 3);
        f = Mem.withFact(f, "Runs Hyprland", "e", 5, "user", 3);
        compare(f.length, 3, "capped");
        compare(f[0].text, "Edits in nvim", "oldest falls off");
        compare(Mem.withFact(f, "   ", "f", 6, "user", 3).length, 3, "blank is nothing");
    }

    function test_forget_by_id() {
        let f = Mem.withFact([], "One", "a", 1, "user", 10);
        f = Mem.withFact(f, "Two", "b", 2, "user", 10);
        compare(Mem.withoutFact(f, "a").length, 1);
        compare(Mem.withoutFact(f, "zzz").length, 2);
    }

    function test_prompt_block_shapes_and_gates() {
        const f = Mem.withFact([], "Uses Arch", "a", 1, "user", 10);
        verify(Mem.promptBlock(f, true).indexOf("## What you already know") === 0);
        verify(Mem.promptBlock(f, true).indexOf("- Uses Arch") > 0);
        compare(Mem.promptBlock(f, false), "", "disabled is silence");
        compare(Mem.promptBlock([], true), "", "empty is silence");
    }
}
