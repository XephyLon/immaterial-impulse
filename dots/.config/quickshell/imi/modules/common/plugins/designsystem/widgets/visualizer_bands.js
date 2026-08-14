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
// The envelope's tuning, and the threshold at which a lobe has arrived.
//
// These were VisualizerCookie's named properties. That component is gone - it
// had no instantiation, and the one consumer that needs this pipeline paints
// its own body (one painter owns the face, which is the whole reason it did
// not reuse the component) - so the numbers live beside the maths they tune
// rather than as bare literals at the call site.
//
// ATTACK is how fast a lobe rises toward a louder band, DECAY how slowly it
// falls back; rising faster than it falls is what makes a beat read as a beat
// instead of a wobble. SETTLE_EPSILON is when a lobe is close enough to be
// snapped to its target, which is what lets the 16ms envelope timer stop
// instead of chasing an asymptote forever.
var ATTACK = 0.55;
var DECAY = 0.12;
var SETTLE_EPSILON = 0.001;
var LOBES = 12;

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
