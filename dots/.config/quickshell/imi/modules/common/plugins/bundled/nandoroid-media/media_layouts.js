.pragma library

// Which file draws which span, in one table.
//
// The host owns *which* size a widget is - it resolves the stored `__gridSize`
// against the manifest and hands the answer down as `hostGridSize`
// (docs/widget-grid.md) - and the widget owns what that size looks like. This
// is the whole of the widget's half: span in, layout file out.
//
// The entries are in the manifest's `sizes` order, which is the resize order,
// and `tests/test_media_layouts_contract.py` fails if the two lists drift: a
// span the manifest offers with no layout of its own would silently draw the
// default one, squeezed into a box it was never designed for.
var SIZES = [
    { size: "3x2", cols: 3, rows: 2, layout: "LayoutLarge.qml" },
    { size: "2x2", cols: 2, rows: 2, layout: "LayoutCookie.qml" }
];

// Anything unrecognised resolves to the first entry rather than to nothing:
// `hostGridSize` is empty until the host answers (and stays empty for a bare
// `qs -p` probe of Widget.qml), and a span a future manifest stops offering
// would otherwise load no layout at all - which on screen is indistinguishable
// from a widget that failed to compile.
function entryFor(gridSize) {
    for (let i = 0; i < SIZES.length; i++) {
        if (SIZES[i].size === gridSize)
            return SIZES[i];
    }
    return SIZES[0];
}

function layoutFor(gridSize) {
    return entryFor(gridSize).layout;
}

// The span as cell counts, for the widget's own implicit size. It is a fallback
// only - the host sizes a grid widget to the span it resolved - but it has to
// be the same span the layout is drawn for, or a probe renders one size into
// another's box.
function spanFor(gridSize) {
    const entry = entryFor(gridSize);
    return { cols: entry.cols, rows: entry.rows };
}
