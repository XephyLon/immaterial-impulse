.pragma library

// Cava is shared through a refcount and produces more bands than a cookie has
// lobes, so a consumer folds the bands it is given rather than asking for a
// different bar count - which would change every other visualizer on screen.
// Groups are contiguous and cover every band, so lobe 0 stays bass and the last
// lobe stays treble however many bands arrive.
function toLobes(values, lobes, maxValue) {
    const result = [];
    if (lobes <= 0)
        return result;

    const scale = maxValue > 0 ? maxValue : 1;
    const count = values ? values.length : 0;
    for (let lobe = 0; lobe < lobes; lobe++) {
        if (count === 0) {
            result.push(0);
            continue;
        }
        const start = Math.floor(lobe * count / lobes);
        const end = Math.floor((lobe + 1) * count / lobes);
        let sum = 0;
        let samples = 0;
        for (let i = start; i < end && i < count; i++) {
            sum += values[i];
            samples++;
        }
        // Fewer bands than lobes: neighbouring lobes share a band rather than
        // leaving a lobe with no group at all, which would read as a dead notch.
        const value = samples > 0 ? sum / samples : values[Math.min(start, count - 1)];
        result.push(clamp01(value / scale));
    }
    return result;
}

// Fast attack so a beat reads on the frame it lands, slower decay so the
// outline settles instead of boiling at cava's frame rate.
function envelope(current, target, attack, decay) {
    const from = isFinite(current) ? current : 0;
    const to = isFinite(target) ? target : 0;
    return from + (to - from) * (to > from ? attack : decay);
}

function clamp01(value) {
    if (!isFinite(value))
        return 0;
    return Math.max(0, Math.min(1, value));
}
