.pragma library

// Reshaping the cava spectrum for a consumer that wants a different number of
// bars, or a 0..1 level instead of the raw range.
//
// The band count and the value range are the producer's, not a preference:
// CavaService launches cava with scripts/cava/raw_output_config.txt, which asks
// for a fixed number of bars in a fixed ascii range. A widget that wants 20
// dots or one bar per 12 pixels of monitor resamples that array - it does not
// redeclare the count and hope the two numbers stay equal, which is exactly how
// CavaService's own `barCount: 32` ended up disagreeing with the 50 bars the
// process emits.
//
// Everything here is pure so it can be tested without a compositor, an audio
// server, or a cava binary.

function _zeros(count) {
    const out = [];
    for (let i = 0; i < count; i++) out.push(0);
    return out;
}

// `values` mapped onto exactly `targetCount` bands.
//
// Upsampling interpolates between neighbouring bands so a wide bar row reads as
// a curve rather than a staircase. Downsampling averages every source band that
// falls in an output band instead of picking one index out of the range: a
// nearest-index pick silently drops a peak sitting between two picked indices,
// which is the difference between a spectrum that moves and one that looks
// half-dead at low bar counts.
//
// A missing or empty source yields zeros rather than a short array, so a
// consumer's bar model keeps its length while cava is not running.
function resample(values, targetCount) {
    const target = Math.floor(targetCount);
    if (!(target > 0)) return [];

    const src = values || [];
    const n = src.length;
    if (n === 0) return _zeros(target);
    if (n === target) return src.slice();

    const out = [];
    if (n === 1 || target === 1) {
        // One band in or one band out: there is nothing to interpolate across,
        // so average the whole source into every output band.
        let total = 0;
        for (let i = 0; i < n; i++) total += src[i];
        const mean = total / n;
        for (let i = 0; i < target; i++) out.push(n === 1 ? src[0] : mean);
        return out;
    }

    if (target > n) {
        for (let i = 0; i < target; i++) {
            const pos = (i * (n - 1)) / (target - 1);
            const low = Math.floor(pos);
            const high = Math.min(n - 1, low + 1);
            const mix = pos - low;
            out.push((src[low] * (1 - mix)) + (src[high] * mix));
        }
        return out;
    }

    for (let i = 0; i < target; i++) {
        const from = Math.floor((i * n) / target);
        const to = Math.max(from + 1, Math.floor(((i + 1) * n) / target));
        let sum = 0;
        for (let j = from; j < to; j++) sum += src[j];
        out.push(sum / (to - from));
    }
    return out;
}

// `values` as levels in 0..1 against the producer's range, clamped: cava's
// autosens can overshoot its own maximum, and a bar taller than its container
// draws outside it.
function normalize(values, maxValue) {
    const src = values || [];
    if (!(maxValue > 0)) return _zeros(src.length);

    const out = [];
    for (let i = 0; i < src.length; i++) {
        const level = src[i] / maxValue;
        out.push(level < 0 ? 0 : (level > 1 ? 1 : level));
    }
    return out;
}

// The whole job in one call: the raw spectrum as `targetCount` levels in 0..1.
function bands(values, targetCount, maxValue) {
    return normalize(resample(values, targetCount), maxValue);
}
