.pragma library

// Resolving which component-grid span a placed widget occupies.
//
// A manifest's `grid` used to be one constant span (docs/widget-grid.md). It
// may now also carry a `sizes` array - the spans the widget offers - with
// `cols`/`rows` staying as the default. Everything here is pure data so it can
// be driven from a TestCase; the host (PluginWidget) supplies the pixel
// measurements and does the persisting.
//
// The rules that are not obvious:
//   - a `sizes` list the manifest got wrong is rejected whole, never repaired.
//     Dropping the bad entry and keeping the rest would silently offer a
//     different set of spans than the author wrote, and the widget the user
//     already placed would change size on upgrade for reasons nothing reports.
//   - a stored span that the manifest no longer offers falls back to the
//     default rather than being honoured, for the same reason: a widget laid
//     out into a span its content no longer fills looks broken and is not
//     traceable to the manifest edit that caused it.

const MIN_CELLS = 1;
const MAX_CELLS = 12;

function isCellCount(value) {
    return typeof value === "number" && isFinite(value) && value === Math.floor(value)
        && value >= MIN_CELLS && value <= MAX_CELLS;
}

// A span entry, with each axis defaulting to 1 exactly as `grid` itself does.
// Returns null for anything that is not a usable span, so a caller never has to
// distinguish "absent" from "malformed" - both mean "do not offer this".
function normalizeSize(entry) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null;
    const cols = entry.cols === undefined ? 1 : entry.cols;
    const rows = entry.rows === undefined ? 1 : entry.rows;
    if (!isCellCount(cols) || !isCellCount(rows)) return null;
    return { cols: cols, rows: rows };
}

// The manifest's declared span. Null means the manifest declares no grid at
// all, which is the legacy content-sized path and not an error.
function defaultSize(grid) {
    return normalizeSize(grid);
}

// `sizes` as a plain JS array, or null when it is not a list at all.
//
// `Array.isArray` is not the test, and assuming it was made the whole `sizes`
// feature inert on the one path that matters. A JS array reaching a delegate
// through a `Repeater`'s `model` has crossed into QVariant and back: indices
// and `length` survive, `Array.isArray` does not - and `Background.qml` builds
// every desktop widget from exactly such a model, so a manifest declaring
// three spans arrived offering one, with no error anywhere. Measured against a
// real shell, because the synthetic manifests the harness declares inline
// never cross that boundary.
//
// Anything without a numeric `length` is still rejected, which is what keeps a
// malformed `sizes` from being read as an empty list of spans.
function asSizeList(value) {
    if (Array.isArray(value)) return value;
    if (!value || typeof value !== "object" || typeof value.length !== "number") return null;
    const out = [];
    for (let index = 0; index < value.length; index++) out.push(value[index]);
    return out;
}

function sameSize(a, b) {
    return !!a && !!b && a.cols === b.cols && a.rows === b.rows;
}

function containsSize(list, size) {
    for (const entry of list) {
        if (sameSize(entry, size)) return true;
    }
    return false;
}

// Every span this widget offers, in the manifest's order (which is the resize
// order). Always at least the default, so a caller can treat the result as the
// complete answer; a list of one means the widget has a single size and gets no
// resize handle.
function offeredSizes(grid) {
    const fallback = defaultSize(grid);
    if (!fallback) return [];

    const declared = asSizeList(grid.sizes);
    if (declared === null) return [fallback];

    const out = [];
    for (const entry of declared) {
        const size = normalizeSize(entry);
        if (!size) return [fallback];
        if (!containsSize(out, size)) out.push(size);
    }
    if (!containsSize(out, fallback)) return [fallback];
    return out;
}

function resizable(grid) {
    return offeredSizes(grid).length > 1;
}

// The persisted form, "<cols>x<rows>".
function formatSize(size) {
    const normalized = normalizeSize(size);
    return normalized ? normalized.cols + "x" + normalized.rows : "";
}

function parseSize(text) {
    if (typeof text !== "string") return null;
    const match = /^\s*(\d+)\s*x\s*(\d+)\s*$/.exec(text);
    if (!match) return null;
    return normalizeSize({ cols: parseInt(match[1], 10), rows: parseInt(match[2], 10) });
}

// Stored -> manifest default -> content-sized (null), which is the order
// PluginWidget applies.
function resolveSize(grid, stored) {
    const fallback = defaultSize(grid);
    if (!fallback) return null;

    const wanted = parseSize(stored);
    if (wanted && containsSize(offeredSizes(grid), wanted)) return wanted;
    return fallback;
}

// The span one step along the offered order from wherever the widget is
// drawn, or null when there is nowhere to step. The menu's Size stepper is
// built on this - "the neighbouring offered span" gets one spelling, beside
// the resolution it starts from, where qmltestrunner can reach it (the walk
// used to live in the menu's QML, where only the weston harness could).
//
// It starts from resolveSize's answer rather than from the stored string, so
// a stale stored span - one the manifest no longer offers - steps from the
// fallback the widget is actually drawn at. Off either end it answers null
// rather than clamping, because the caller's chevron reads "is there a next
// span" straight off this, and a clamp would leave a live-looking button that
// writes the span the widget already has.
function steppedSize(grid, stored, direction) {
    const offered = offeredSizes(grid);
    if (offered.length < 2) return null;
    const current = resolveSize(grid, stored);
    if (!current) return null;
    for (let index = 0; index < offered.length; index++) {
        if (!sameSize(offered[index], current)) continue;
        const next = index + direction;
        if (next < 0 || next >= offered.length) return null;
        return offered[next];
    }
    return null;
}

// Folding a legacy `sizeMode` option into the host's `__gridSize`.
//
// `sizeMode` was a plugin-*declared* choice option on two bundled widgets, in
// this module's own "<cols>x<rows>" format: a second mechanism for the concept
// `__gridSize` owns, which is why it is retired rather than kept in step.
// Takes a plugin's stored options and its manifest grid; returns the options
// with the old key gone, or null when there is nothing to change.
//
// Deleting the old key rather than merely shadowing it is what makes this
// idempotent - a second pass finds no `sizeMode` and answers null. Four rules
// beyond the obvious mapping, each one a refusal to invent or destroy a size:
//   - **a manifest that does not offer several spans is left alone entirely.**
//     `sizeMode` is not only a retired manifest option: `world-clock` and
//     `calendar` declare no `grid` and manage a `sizeMode` of their own through
//     their own toggles, so it is a live setting for them. Migrating on the key
//     name alone deletes it and resets both widgets - the exact loss this
//     function exists to prevent, aimed at the wrong widgets.
//   - a stored mode the manifest does not offer is dropped without being
//     written, exactly as resolveSize refuses to honour a stored span that is
//     no longer offered. The widget falls back to its default rather than
//     being laid out into a size its content does not fill.
//   - an existing `__gridSize` wins. It can only have come from the resize
//     grip, which is the more recent choice.
//   - a plugin with no stored options at all is left alone, so the migration
//     never creates state for a widget the user has never placed.
function migrateSizeMode(options, grid) {
    if (!options || typeof options !== "object" || Array.isArray(options)) return null;
    if (options.sizeMode === undefined) return null;
    if (offeredSizes(grid).length <= 1) return null;

    const next = {};
    for (const key in options) {
        if (key !== "sizeMode") next[key] = options[key];
    }
    if (next.__gridSize === undefined) {
        const wanted = parseSize(options.sizeMode);
        if (wanted && containsSize(offeredSizes(grid), wanted))
            next.__gridSize = formatSize(wanted);
    }
    return next;
}

// The drag snap. `candidates` carry their own pixel measurements because the
// span-to-pixel conversion is Appearance's (widgetGridSpanX/Y, which also
// applies effectiveScale) and copying that formula here would be a second one
// to keep in step: [{ cols, rows, width, height }].
//
// Nearest by plain distance in pixels, so both axes count. A tie goes to the
// earlier candidate, which makes the widget under a pointer sitting exactly
// between two spans stable rather than flickering between them. A target that
// is not a real number yields null - the caller keeps whatever it had.
function nearestSize(candidates, targetWidth, targetHeight) {
    const list = asSizeList(candidates);
    if (list === null) return null;

    let best = null;
    let bestDistance = Infinity;
    for (const candidate of list) {
        const dx = candidate.width - targetWidth;
        const dy = candidate.height - targetHeight;
        const distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
            bestDistance = distance;
            best = candidate;
        }
    }
    return best;
}
