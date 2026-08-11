.pragma library

// The motion a placed widget's span change is drawn with (docs/widget-grid.md).
//
// Resolving *which* span a widget is lives in gridSizes.js; this is the sibling
// question of how it gets there. Both are here rather than inline in
// PluginWidget for the same reason: everything else about the resize needs a
// real host, which `qmltestrunner` cannot construct, so the arithmetic is the
// part a test can reach at all.

// A span previewed mid-drag is answered on a shorter curve than one that has
// been committed.
//
// The grip previews live - the size on screen during the drag is the size a
// release commits - so the widget is chasing the pointer, and 500ms of
// expressive spatial motion between two spans reads as lag rather than as
// smoothness when a fast drag crosses two thresholds. A commit, a Size row
// change and an Escape are all destinations rather than tracking, and take the
// full curve. Nothing here picks the curve *shape*: the caller pairs each
// duration with the Appearance curve it belongs to (expressiveFastSpatial with
// the drag, expressiveDefaultSpatial with the commit).
function resizeDurationMs(previewing, dragMs, commitMs) {
    return previewing ? dragMs : commitMs;
}

// The content changes at the move's midpoint, under a fade out and back in.
//
// A widget offering several spans has a design per span (docs/widget-grid.md) -
// media loads a different layout FILE per span - so animating the box while the
// content swaps instantly pops at exactly the moment the motion is supposed to
// hide. Half the move each way makes the swap land where the content is least
// visible and puts the fade inside the resize rather than beside it, whichever
// duration the resize is running at.
function contentSwapHalfMs(durationMs) {
    if (typeof durationMs !== "number" || !isFinite(durationMs)) return 0;
    return Math.max(0, Math.round(durationMs / 2));
}

// Whether a span change is a swap to animate or a value to adopt in place.
//
// The empty string is "no span resolved yet", which every widget passes through
// once: the host answers with the manifest default and the stored choice
// arrives with plugin-state.json a moment later. Fading that would have every
// resized widget on the desktop dissolve on login for a size nobody just chose.
function animatesSpanSwap(shown, next) {
    return typeof shown === "string" && typeof next === "string"
        && shown !== "" && next !== "" && shown !== next;
}
