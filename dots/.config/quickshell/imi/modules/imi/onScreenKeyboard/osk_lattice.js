.pragma library
.import "key_shapes.js" as KeyShapes

// Where every key of a layout sits, as GRID CELLS.
//
// A keyboard is a lattice rather than a stack of rows: the numpad's + and its
// Enter are one key two rows tall, and a row of keys cannot say so - which is
// why they used to be two keys carrying one keycode each. Saying it needs a
// GridLayout, and a GridLayout spans whole columns, so the lattice's column is
// the QUARTER UNIT: every width in key_shapes.js is a multiple of 0.25u, so 1u
// is four columns, 1.25u is five and the 6.25u spacebar is twenty-five.
// `widthsAreWholeColumns()` is what says that assumption still holds, and
// tst_osk_layouts.qml fails on a shape that breaks it.
//
// The layouts stay row-major and carry no coordinates. This is the walk: a key
// takes the next free cells in its row, a key taller than one unit CLAIMS the
// cells under it as well, and the row below steps over whatever was claimed.
// That claim is the whole of the bookkeeping the data does not carry.
const COLUMNS_PER_UNIT = 4;

function columnSpan(shape) {
    return Math.round((KeyShapes.widthUnits[shape] ?? 1) * COLUMNS_PER_UNIT);
}

// Only a key at least a whole unit tall claims rows. The two shapes shorter
// than a unit - the function row's short cap and the spacer with no height at
// all - are a cap drawn inside its own row, not a span.
function rowSpan(shape) {
    const units = KeyShapes.heightUnits[shape] ?? 1;
    return units > 1 ? Math.round(units) : 1;
}

// The lattice rests on every width being a whole number of columns. A shape
// that is not - a 1.1u key, say - would be drawn at a rounded span and put
// every column after it somewhere the row above does not have one.
function widthsAreWholeColumns() {
    const offenders = [];
    for (const shape of Object.keys(KeyShapes.widthUnits)) {
        const columns = KeyShapes.widthUnits[shape] * COLUMNS_PER_UNIT;
        if (columns !== Math.round(columns))
            offenders.push(shape);
    }
    return offenders;
}

function place(rows) {
    const claimed = ({});
    const placements = [];
    for (let row = 0; row < rows.length; row++) {
        let column = 0;
        for (const key of rows[row]) {
            const columns = columnSpan(key.shape);
            const height = rowSpan(key.shape);
            column = nextFreeColumn(claimed, row, column, columns);
            for (let r = 0; r < height; r++)
                for (let c = 0; c < columns; c++)
                    claimed[(row + r) + "," + (column + c)] = true;
            placements.push({
                key: key,
                row: row,
                column: column,
                columnSpan: columns,
                rowSpan: height
            });
            column += columns;
        }
    }
    return placements;
}

// Terminates because `claimed` holds finitely many cells: past the last one
// every column is free.
function nextFreeColumn(claimed, row, from, span) {
    let column = from;
    for (;;) {
        let free = true;
        for (let c = 0; c < span; c++) {
            if (claimed[row + "," + (column + c)]) {
                free = false;
                break;
            }
        }
        if (free)
            return column;
        column++;
    }
}

function columnsIn(placements) {
    let columns = 0;
    for (const placed of placements)
        columns = Math.max(columns, placed.column + placed.columnSpan);
    return columns;
}

// How many of a row's columns are covered, counting the ones a taller key in
// an earlier row claimed. Every row of a full-size keyboard covers all of
// them; a row that does not is a row whose nav cluster and numpad sit
// somewhere the rows above and below do not.
function columnsCovered(placements, row) {
    let covered = 0;
    for (const placed of placements)
        if (row >= placed.row && row < placed.row + placed.rowSpan)
            covered += placed.columnSpan;
    return covered;
}

// A GridLayout column is the pitch's quarter minus the spacing that follows
// it, so that a key spanning n columns - which covers the n-1 gaps inside its
// span - comes out at exactly the width its units buy.
function columnWidth(baseWidth, keyGap) {
    return (baseWidth + keyGap) / COLUMNS_PER_UNIT - keyGap;
}
