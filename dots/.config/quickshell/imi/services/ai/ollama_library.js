.pragma library

// A curated snapshot of the Ollama library, refreshed by hand at release
// time (docs/proposals/ollama-catalog.md: ollama.com has no public JSON
// catalog, and a scrape is churn we would own). Sizes are the download
// sizes of the default quantization per tag, in GB, approximate - the daemon
// reports the exact size once a model is installed. Anything not here can
// still be pulled by typing its name:tag.
var SNAPSHOT_DATE = "2026-09";

var MODELS = [
    { name: "llama3.3", family: "Meta", description: "Llama 3.3, the 70B generalist", tools: true, vision: false, embedding: false,
      tags: [{ tag: "70b", gb: 43 }] },
    { name: "llama3.2", family: "Meta", description: "Small Llama for laptops and quick replies", tools: true, vision: false, embedding: false,
      tags: [{ tag: "1b", gb: 1.3 }, { tag: "3b", gb: 2.0 }] },
    { name: "llama3.2-vision", family: "Meta", description: "Llama with image input", tools: false, vision: true, embedding: false,
      tags: [{ tag: "11b", gb: 7.9 }, { tag: "90b", gb: 55 }] },
    { name: "llama3.1", family: "Meta", description: "Llama 3.1, long context, tool use", tools: true, vision: false, embedding: false,
      tags: [{ tag: "8b", gb: 4.9 }, { tag: "70b", gb: 43 }] },
    { name: "llama4", family: "Meta", description: "Llama 4 mixture-of-experts, multimodal", tools: true, vision: true, embedding: false,
      tags: [{ tag: "scout", gb: 67 }, { tag: "maverick", gb: 245 }] },
    { name: "qwen3", family: "Alibaba", description: "Qwen 3, thinking mode, strong at code and math", tools: true, vision: false, embedding: false,
      tags: [{ tag: "0.6b", gb: 0.5 }, { tag: "1.7b", gb: 1.4 }, { tag: "4b", gb: 2.6 }, { tag: "8b", gb: 5.2 }, { tag: "14b", gb: 9.3 }, { tag: "30b", gb: 19 }, { tag: "32b", gb: 20 }] },
    { name: "qwen2.5", family: "Alibaba", description: "Qwen 2.5 generalist, many sizes", tools: true, vision: false, embedding: false,
      tags: [{ tag: "0.5b", gb: 0.4 }, { tag: "1.5b", gb: 1.0 }, { tag: "3b", gb: 1.9 }, { tag: "7b", gb: 4.7 }, { tag: "14b", gb: 9.0 }, { tag: "32b", gb: 20 }, { tag: "72b", gb: 47 }] },
    { name: "qwen2.5-coder", family: "Alibaba", description: "Qwen 2.5 tuned for code", tools: true, vision: false, embedding: false,
      tags: [{ tag: "1.5b", gb: 1.0 }, { tag: "7b", gb: 4.7 }, { tag: "14b", gb: 9.0 }, { tag: "32b", gb: 20 }] },
    { name: "qwen2.5vl", family: "Alibaba", description: "Qwen 2.5 with image input", tools: false, vision: true, embedding: false,
      tags: [{ tag: "3b", gb: 3.2 }, { tag: "7b", gb: 6.0 }, { tag: "32b", gb: 21 }, { tag: "72b", gb: 49 }] },
    { name: "gemma3", family: "Google", description: "Gemma 3, image input from 4b up", tools: false, vision: true, embedding: false,
      tags: [{ tag: "1b", gb: 0.8 }, { tag: "4b", gb: 3.3 }, { tag: "12b", gb: 8.1 }, { tag: "27b", gb: 17 }] },
    { name: "gemma3n", family: "Google", description: "Gemma 3n, built for on-device use", tools: false, vision: false, embedding: false,
      tags: [{ tag: "e2b", gb: 5.6 }, { tag: "e4b", gb: 7.5 }] },
    { name: "gemma2", family: "Google", description: "Gemma 2", tools: false, vision: false, embedding: false,
      tags: [{ tag: "2b", gb: 1.6 }, { tag: "9b", gb: 5.4 }, { tag: "27b", gb: 16 }] },
    { name: "gpt-oss", family: "OpenAI", description: "OpenAI's open-weight reasoning models", tools: true, vision: false, embedding: false,
      tags: [{ tag: "20b", gb: 14 }, { tag: "120b", gb: 65 }] },
    { name: "phi4", family: "Microsoft", description: "Phi-4, 14B reasoning-heavy", tools: false, vision: false, embedding: false,
      tags: [{ tag: "14b", gb: 9.1 }] },
    { name: "phi4-mini", family: "Microsoft", description: "Phi-4 mini, tool use", tools: true, vision: false, embedding: false,
      tags: [{ tag: "3.8b", gb: 2.5 }] },
    { name: "phi3", family: "Microsoft", description: "Phi-3", tools: false, vision: false, embedding: false,
      tags: [{ tag: "3.8b", gb: 2.2 }, { tag: "14b", gb: 7.9 }] },
    { name: "mistral", family: "Mistral", description: "Mistral 7B", tools: true, vision: false, embedding: false,
      tags: [{ tag: "7b", gb: 4.1 }] },
    { name: "mistral-nemo", family: "Mistral", description: "Mistral NeMo 12B, 128k context", tools: true, vision: false, embedding: false,
      tags: [{ tag: "12b", gb: 7.1 }] },
    { name: "mistral-small3.2", family: "Mistral", description: "Mistral Small 3.2, image input", tools: true, vision: true, embedding: false,
      tags: [{ tag: "24b", gb: 15 }] },
    { name: "magistral", family: "Mistral", description: "Magistral, Mistral's reasoning model", tools: true, vision: false, embedding: false,
      tags: [{ tag: "24b", gb: 14 }] },
    { name: "devstral", family: "Mistral", description: "Devstral, agentic coding", tools: true, vision: false, embedding: false,
      tags: [{ tag: "24b", gb: 14 }] },
    { name: "mixtral", family: "Mistral", description: "Mixtral 8x7B mixture-of-experts", tools: true, vision: false, embedding: false,
      tags: [{ tag: "8x7b", gb: 26 }] },
    { name: "deepseek-r1", family: "DeepSeek", description: "DeepSeek R1 reasoning, distilled sizes", tools: false, vision: false, embedding: false,
      tags: [{ tag: "1.5b", gb: 1.1 }, { tag: "7b", gb: 4.7 }, { tag: "8b", gb: 4.9 }, { tag: "14b", gb: 9.0 }, { tag: "32b", gb: 20 }, { tag: "70b", gb: 43 }] },
    { name: "deepseek-coder-v2", family: "DeepSeek", description: "DeepSeek Coder V2", tools: false, vision: false, embedding: false,
      tags: [{ tag: "16b", gb: 8.9 }] },
    { name: "codellama", family: "Meta", description: "Code Llama", tools: false, vision: false, embedding: false,
      tags: [{ tag: "7b", gb: 3.8 }, { tag: "13b", gb: 7.4 }, { tag: "34b", gb: 19 }] },
    { name: "starcoder2", family: "BigCode", description: "StarCoder 2, code completion", tools: false, vision: false, embedding: false,
      tags: [{ tag: "3b", gb: 1.7 }, { tag: "7b", gb: 4.0 }, { tag: "15b", gb: 9.1 }] },
    { name: "llava", family: "LLaVA", description: "LLaVA, image input", tools: false, vision: true, embedding: false,
      tags: [{ tag: "7b", gb: 4.7 }, { tag: "13b", gb: 8.0 }, { tag: "34b", gb: 20 }] },
    { name: "moondream", family: "Moondream", description: "Tiny vision model", tools: false, vision: true, embedding: false,
      tags: [{ tag: "1.8b", gb: 1.7 }] },
    { name: "command-r", family: "Cohere", description: "Command R, retrieval and tool use", tools: true, vision: false, embedding: false,
      tags: [{ tag: "35b", gb: 20 }] },
    { name: "granite3.3", family: "IBM", description: "Granite 3.3", tools: true, vision: false, embedding: false,
      tags: [{ tag: "2b", gb: 1.5 }, { tag: "8b", gb: 4.9 }] },
    { name: "smollm2", family: "Hugging Face", description: "SmolLM2, very small", tools: true, vision: false, embedding: false,
      tags: [{ tag: "135m", gb: 0.27 }, { tag: "360m", gb: 0.73 }, { tag: "1.7b", gb: 1.8 }] },
    { name: "tinyllama", family: "TinyLlama", description: "TinyLlama 1.1B", tools: false, vision: false, embedding: false,
      tags: [{ tag: "1.1b", gb: 0.64 }] },
    { name: "nomic-embed-text", family: "Nomic", description: "Text embeddings (for retrieval)", tools: false, vision: false, embedding: true,
      tags: [{ tag: "latest", gb: 0.27 }] },
    { name: "mxbai-embed-large", family: "Mixedbread", description: "Text embeddings, larger", tools: false, vision: false, embedding: true,
      tags: [{ tag: "latest", gb: 0.67 }] },
    { name: "bge-m3", family: "BAAI", description: "Multilingual text embeddings", tools: false, vision: false, embedding: true,
      tags: [{ tag: "latest", gb: 1.2 }] },
    { name: "all-minilm", family: "Sentence Transformers", description: "Small sentence embeddings", tools: false, vision: false, embedding: true,
      tags: [{ tag: "latest", gb: 0.05 }] },
];

// Rows for the view: one per model, tags kept together. `capability` is
// "" (all), "tools", "vision" or "embedding".
function filterModels(models, query, capability) {
    var q = String(query || "").trim().toLowerCase();
    return (models || []).filter(function (m) {
        if (capability && !m[capability]) return false;
        if (!q) return true;
        return (m.name + " " + m.family + " " + m.description).toLowerCase().indexOf(q) !== -1;
    });
}

// Does a download of `gb` fit? "vram" (fits free VRAM with headroom), "ram"
// (spills to system memory), "no" (exceeds both), "" (unknown - no GPU data).
// All inputs in GB; a total <= 0 means unknown.
function fit(gb, freeVramGb, totalRamGb) {
    if (!(gb > 0)) return "";
    if (freeVramGb > 0 && gb * 1.1 <= freeVramGb) return "vram";
    if (totalRamGb > 0 && gb * 1.1 <= totalRamGb) return "ram";
    if (totalRamGb > 0 || freeVramGb > 0) return "no";
    return "";
}

// "llama3.2:3b" -> { name: "llama3.2", tag: "3b" }; a bare name gets "latest".
function splitRef(ref) {
    var s = String(ref || "").trim();
    var i = s.lastIndexOf(":");
    if (i <= 0) return { name: s, tag: "latest" };
    return { name: s.slice(0, i), tag: s.slice(i + 1) };
}

// Bytes from the daemon (/api/tags `size`) to a short label.
function sizeLabel(bytes) {
    var b = Number(bytes) || 0;
    if (b >= 1e9) return (b / 1e9).toFixed(b >= 1e10 ? 0 : 1) + " GB";
    if (b >= 1e6) return Math.round(b / 1e6) + " MB";
    return b + " B";
}

// A pull's progress line -> 0..1, or -1 when the line carries no byte counts
// (the "pulling manifest" / "verifying" / "success" statuses).
function pullFraction(event) {
    if (!event || !(event.total > 0)) return -1;
    return Math.max(0, Math.min(1, (Number(event.completed) || 0) / Number(event.total)));
}
