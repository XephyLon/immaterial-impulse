.pragma library

// The spans the media widget offers, as one table.
//
// This used to also name a layout file per span - the dispatch the one-tree
// Widget.qml replaced. What survives is the half the tree still needs: the
// manifest's spans as cell counts, with the 3x2 as the fallback for a span
// the host has not resolved yet (or a probe never resolves).
var SPANS = [
    { size: "3x2", cols: 3, rows: 2 },
    { size: "2x2", cols: 2, rows: 2 },
    { size: "2x1", cols: 2, rows: 1 }
];

function entryFor(gridSize) {
    for (var i = 0; i < SPANS.length; i++)
        if (SPANS[i].size === gridSize) return SPANS[i];
    return SPANS[0];
}

// The span as cell counts, for the widget's own implicit size. It is a
// fallback only - the host sizes a grid widget to the span it resolved - but
// it has to be the same span the tree draws for, or a probe renders one size
// into another size's box.
function spanFor(gridSize) {
    var entry = entryFor(gridSize);
    return { cols: entry.cols, rows: entry.rows };
}
