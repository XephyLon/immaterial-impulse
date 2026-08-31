.pragma library

function guessModelName(model) {
    const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
    let words = replaced.split(' ');
    words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
    words = words.map((word) => {
        return (word.charAt(0).toUpperCase() + word.slice(1))
    });
    if (words[words.length - 1] === "Latest") words.pop();
    else words[words.length - 1] = `(${words[words.length - 1]})`;
    const result = words.join(' ');
    return result;
}

// The base of an OpenAI-compatible API, from whatever the user typed. The
// fetch appends `/models` and the models' endpoints append
// `/chat/completions`, so a base that already ends in either - pasted from
// the browser bar, which is how one gets `http://host/v1/models` into a
// field labelled Base URL - produced `/v1/models/models`, a 404 with an empty
// body, and a fetch that "gave nothing".
function normalizeBaseUrl(url) {
    let base = `${url ?? ""}`.trim();
    base = base.replace(/\/+$/, "");
    base = base.replace(/\/(models|chat\/completions)$/i, "");
    return base.replace(/\/+$/, "");
}

function parseCustomProviderModels(responseJsonString, baseUrl, providerName, keyId) {
    try {
        if (!responseJsonString || responseJsonString.trim() === "") return [];
        const data = JSON.parse(responseJsonString);
        if (!data || !Array.isArray(data.data)) return [];
        let result = [];
        const sanitizedBaseUrl = normalizeBaseUrl(baseUrl);
        data.data.forEach(model => {
            if (!model.id) return;
            result.push({
                // "<ProviderName>: <Model>" (spec 2026-08-31): applied HERE
                // so the picker, the message headers and the browse rows all
                // agree without any of them re-deriving it.
                name: providerName + ": " + guessModelName(model.id),
                providerName: providerName,
                model: model.id,
                // Generators are named like generators; no /models listing
                // says which endpoint a model wants, so the id has to.
                imageGeneration: /image|dall-e|flux|diffusion/i.test(model.id),
                description: `Online | Custom (${providerName}) | ${model.id}`,
                endpoint: sanitizedBaseUrl + "/chat/completions",
                requires_key: true,
                key_id: keyId,
                api_format: "openai"
            });
        });
        return result;
    } catch (e) {
        return [];
    }
}
