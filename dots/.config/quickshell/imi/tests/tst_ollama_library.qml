import QtQuick
import QtTest
import "../services/ai/ollama_library.js" as Library

// The curated Ollama library and the pure helpers around it: the snapshot's
// shape, filtering by text and capability, the fit verdict, ref splitting,
// size labels and pull-progress fractions. The daemon side lives in
// OllamaCatalogRuntimeTest.qml against a fake daemon.
TestCase {
    name: "OllamaLibrary"

    function test_snapshot_shape() {
        verify(Library.MODELS.length >= 30, "a snapshot worth browsing");
        verify(/^\d{4}-\d{2}$/.test(Library.SNAPSHOT_DATE), "dated so the UI can say how stale it is");
        const names = {};
        for (const m of Library.MODELS) {
            verify(!(m.name in names), `duplicate ${m.name}`);
            names[m.name] = true;
            verify(m.tags.length > 0, `${m.name} has tags`);
            for (const t of m.tags)
                verify(t.gb > 0, `${m.name}:${t.tag} has a size`);
            compare(typeof m.tools, "boolean");
            compare(typeof m.vision, "boolean");
            compare(typeof m.embedding, "boolean");
        }
    }

    function test_filter_by_text_and_capability() {
        const all = Library.filterModels(Library.MODELS, "", "");
        compare(all.length, Library.MODELS.length);
        const embed = Library.filterModels(Library.MODELS, "", "embedding");
        verify(embed.length > 0 && embed.every(m => m.embedding));
        const qwenVision = Library.filterModels(Library.MODELS, "qwen", "vision");
        verify(qwenVision.length > 0 && qwenVision.every(m => m.vision && m.name.includes("qwen")));
        compare(Library.filterModels(Library.MODELS, "no-such-model-xyz", "").length, 0);
        // Family and description are searchable too.
        verify(Library.filterModels(Library.MODELS, "meta", "").length > 0);
    }

    function test_fit_verdict() {
        compare(Library.fit(4.7, 14, 60), "vram");
        compare(Library.fit(20, 14, 60), "ram");
        compare(Library.fit(90, 14, 60), "no");
        compare(Library.fit(4.7, 0, 0), "", "no data, no verdict");
        compare(Library.fit(4.7, 0, 8), "ram", "no GPU data but RAM known");
        compare(Library.fit(0, 14, 60), "");
        // Headroom: a model exactly the size of free VRAM does not fit it.
        compare(Library.fit(14, 14, 60), "ram");
    }

    function test_split_ref() {
        compare(Library.splitRef("llama3.2:3b").name, "llama3.2");
        compare(Library.splitRef("llama3.2:3b").tag, "3b");
        compare(Library.splitRef("mistral").tag, "latest");
        compare(Library.splitRef("hf.co/user/repo:Q4_K_M").name, "hf.co/user/repo");
    }

    function test_size_label() {
        compare(Library.sizeLabel(4_700_000_000), "4.7 GB");
        compare(Library.sizeLabel(43_000_000_000), "43 GB");
        compare(Library.sizeLabel(270_000_000), "270 MB");
        compare(Library.sizeLabel(0), "0 B");
    }

    function test_pull_fraction() {
        compare(Library.pullFraction({ status: "pulling manifest" }), -1);
        compare(Library.pullFraction({ status: "pulling abc", completed: 50, total: 200 }), 0.25);
        compare(Library.pullFraction({ status: "pulling abc", total: 200 }), 0);
        compare(Library.pullFraction({ status: "pulling abc", completed: 300, total: 200 }), 1);
        compare(Library.pullFraction(null), -1);
    }
}
