.pragma library

function normalizeRates(values) {
    const normalized = {};
    for (const key in (values ?? {})) {
        const value = Number(values[key]);
        normalized[key.toUpperCase()] = Number.isFinite(value) && value > 0 ? value : 0;
    }
    return normalized;
}

// The API table is `1 target = value quote`. The card displays how many units
// of the target one unit of each quote buys, so convert the direction once
// after the single API response arrives.
function ratesIntoTarget(values, quotes) {
    const result = {};
    for (const quote of (quotes ?? [])) {
        const code = String(quote || "").toLowerCase();
        const value = Number(values?.[code]);
        if (Number.isFinite(value) && value > 0)
            result[code.toUpperCase()] = 1 / value;
    }
    return result;
}

function fractionDigits(value) {
    const magnitude = Math.abs(Number(value) || 0);
    if (magnitude < 0.01) return 6;
    if (magnitude < 1) return 4;
    if (magnitude < 1000) return 2;
    return 0;
}
