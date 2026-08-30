.pragma library

// Custom AI providers keep their API keys in the keyring under
// `custom_provider_<index>` - the provider's position in the list. Removing
// a provider used to blank that one slot and leave every provider below it
// reading the slot above: the next provider inherited its neighbour's key
// and fetched with it, which the server answered with a 401 the UI turned
// into "Failed to fetch". Measured on a real keyring: the proxy's key sat
// under custom_provider_1 while the proxy's provider had become index 0.
//
// Pure, so the shift can be tested without a keyring: returns the
// `apiKeys` map as it should read after the provider at `removedIndex` is
// gone from a list that had `count` providers.
function apiKeysAfterRemoval(apiKeys, removedIndex, count) {
    const out = Object.assign({}, apiKeys ?? {});
    for (let i = removedIndex; i < count - 1; i++)
        out[`custom_provider_${i}`] = out[`custom_provider_${i + 1}`] ?? "";
    out[`custom_provider_${count - 1}`] = "";
    return out;
}

// The ids whose value changed between two maps - what the caller has to
// write back, and nothing else.
function changedIds(before, after) {
    const ids = new Set([...Object.keys(before ?? {}), ...Object.keys(after ?? {})]);
    return [...ids].filter(id => (before?.[id] ?? "") !== (after?.[id] ?? ""));
}
