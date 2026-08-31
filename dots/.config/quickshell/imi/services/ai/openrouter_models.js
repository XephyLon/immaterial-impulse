.pragma library

// OpenRouter's /models entries as the shell's rows and imports - pure, so
// the mapping decisions live under a test instead of inside a view.

function rowFor(raw) {
    var id = String(raw?.id ?? "");
    var params = raw?.supported_parameters ?? [];
    var modalities = raw?.architecture?.input_modalities ?? [];
    return {
        id: id,
        name: String(raw?.name ?? id),
        provider: id.indexOf("/") > 0 ? id.slice(0, id.indexOf("/")) : id,
        contextWindow: Number(raw?.context_length ?? 0) || 0,
        promptPrice: Number(raw?.pricing?.prompt ?? 0) || 0,
        completionPrice: Number(raw?.pricing?.completion ?? 0) || 0,
        vision: modalities.indexOf("image") !== -1,
        reasoning: params.indexOf("reasoning") !== -1 || params.indexOf("include_reasoning") !== -1
    };
}

function filterRows(rows, query) {
    var needle = String(query ?? "").toLowerCase().trim();
    if (needle.length === 0) return rows || [];
    return (rows || []).filter(function (row) {
        return row.name.toLowerCase().indexOf(needle) !== -1
            || row.id.toLowerCase().indexOf(needle) !== -1
            || row.provider.toLowerCase().indexOf(needle) !== -1;
    });
}

function importEntry(row) {
    return {
        name: row.name,
        icon: "",
        description: "OpenRouter | " + row.id,
        endpoint: "https://openrouter.ai/api/v1/chat/completions",
        model: row.id,
        requires_key: true,
        key_id: "openrouter",
        key_get_link: "https://openrouter.ai/settings/keys",
        api_format: "openai",
        thinking: !!row.reasoning,
        vision: !!row.vision,
        contextWindow: row.contextWindow
    };
}

function withImported(extraModels, entry) {
    var next = (extraModels || []).slice();
    if (next.some(function (m) { return m.model === entry.model; })) return next;
    next.push(entry);
    return next;
}

// Per-token to per-million, the unit people quote.
function priceLabel(prompt, completion) {
    if (!prompt && !completion) return "free";
    function m(v) { return "$" + (v * 1e6).toFixed(2); }
    return m(prompt) + "/" + m(completion) + " /M";
}
