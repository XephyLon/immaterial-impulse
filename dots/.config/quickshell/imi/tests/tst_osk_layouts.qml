import QtTest
import "../modules/imi/onScreenKeyboard/layouts.js" as Layouts
import "../modules/imi/onScreenKeyboard/key_shapes.js" as KeyShapes
import "../modules/imi/onScreenKeyboard/osk_lattice.js" as Lattice

// The on-screen keyboard's layouts are plain data and osk_lattice.js turns
// them into cells without touching a pixel, which makes the pair the one part
// of that module a test can reach: nothing about a rendered key is reachable
// from qmltestrunner, and OskLayoutProbe.qml exists for the half that is a
// picture.
//
// What is worth pinning here is what breaks silently. A key with the wrong
// evdev keycode types the wrong character and nothing anywhere reports it. A
// row that does not cover the whole lattice puts that row's nav cluster and
// numpad somewhere the rows above and below do not, and the row is still a
// perfectly good row. A shape in one multiplier table and not the other falls
// back to one unit, which is a plausible size for most keys. A width that is
// not a whole number of columns is drawn at a rounded span, which moves every
// column after it. And a keycode that appears twice is a typo everywhere
// except the one place a keyboard draws a key that is not a rectangle.
TestCase {
    name: "OskLayoutsTest"

    // The full-size lattice every row is laid out on, in keyboard units.
    readonly property real mainBlock: 15
    readonly property real clusterGap: 0.5
    readonly property real navCluster: 3
    readonly property real numpad: 4
    readonly property real rowUnits: mainBlock + clusterGap + navCluster + clusterGap + numpad
    readonly property real numpadStart: mainBlock + clusterGap + navCluster + clusterGap

    // The numpad's + and its Enter are ONE key two rows tall.
    readonly property var tallKeys: ({
        78: "numpad +",
        96: "numpad Enter"
    })

    // The only key that is still two keys, because it is the only one that is
    // not a rectangle: an ISO Enter is 1.5u on the top row and 1.25u on the
    // bottom, so no cell of the lattice has that shape.
    readonly property int isoEnter: 28
    readonly property var isoEnterShapes: ["enterIsoBottom", "enterIsoTop"]

    // Everything outside a layout's own alphabet: the function row, the nav
    // cluster, the arrows, the numpad and the modifiers. A keyboard layout
    // decides what the main block spells and nothing about these, so every
    // layout has to offer all of them.
    readonly property var sharedKeycodes: [
        1, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88, // Esc, F1-F12
        99, 70, 119,                                       // PrtSc, ScrLk, Pause
        110, 102, 104, 111, 107, 109,                      // Ins Home PgUp Del End PgDn
        103, 105, 108, 106,                                // arrows
        69, 98, 55, 74, 78, 96,                            // numpad operators
        71, 72, 73, 75, 76, 77, 79, 80, 81, 82, 83,        // numpad digits and .
        14, 15, 58, 28, 42, 54, 29, 97, 56, 100, 125, 126, 127, 57
    ]

    // The one key an ISO main block has that an ANSI one does not.
    readonly property int isoExtraKey: 86

    function layoutNames() {
        return Object.keys(Layouts.byName);
    }

    // Every key of a layout, where the lattice puts it. The offset is in
    // keyboard units, which is what the clusters are described in; the lattice
    // counts in quarters of one.
    function keysOf(name) {
        const out = [];
        for (const placed of Lattice.place(Layouts.byName[name].keys)) {
            out.push({
                key: placed.key,
                row: placed.row,
                offset: placed.column / Lattice.COLUMNS_PER_UNIT,
                units: placed.columnSpan / Lattice.COLUMNS_PER_UNIT,
                rows: placed.rowSpan
            });
        }
        return out;
    }

    function placed(name, keycode) {
        return keysOf(name).filter(entry => entry.key.keycode === keycode);
    }

    function test_every_key_carries_a_keycode_and_a_label() {
        for (const name of layoutNames()) {
            for (const entry of keysOf(name)) {
                const key = entry.key;
                const where = `${name} row ${entry.row} "${key.label}"`;
                verify(key.shape !== undefined, `${where} has no shape`);
                if (key.keytype === "spacer") {
                    compare(key.keycode, undefined, `${where} is a spacer with a keycode`);
                    continue;
                }
                verify(typeof key.keycode === "number", `${where} has no keycode`);
                verify(Number.isInteger(key.keycode), `${where} keycode is not an integer`);
                // ydotool takes a raw evdev code; 0 is KEY_RESERVED and the
                // table ends at KEY_MAX for the keyboard page.
                verify(key.keycode > 0 && key.keycode < 249, `${where} keycode out of range`);
                verify(key.label.length > 0, `${where} has no label`);
            }
        }
    }

    function test_a_keycode_repeats_only_where_the_key_is_not_a_rectangle() {
        for (const name of layoutNames()) {
            const rowsFor = ({});
            for (const entry of keysOf(name)) {
                if (entry.key.keytype === "spacer")
                    continue;
                const code = entry.key.keycode;
                rowsFor[code] = (rowsFor[code] || []).concat(entry.row);
            }
            for (const code of Object.keys(rowsFor)) {
                const rows = rowsFor[code];
                if (rows.length === 1)
                    continue;
                // A key that spans rows is ONE key now. The ISO Enter is the
                // only thing left that two keys is the honest spelling of.
                compare(Number(code), isoEnter,
                    `${name} sends keycode ${code} from ${rows.length} keys`);
                compare(rows.length, 2, `${name}: the ISO Enter is not two keys`);
                compare(rows[1] - rows[0], 1,
                    `${name}: the ISO Enter's arms are not in adjacent rows`);
                const shapes = placed(name, isoEnter).map(entry => entry.key.shape).sort();
                compare(shapes.join(","), isoEnterShapes.join(","),
                    `${name}: the ISO Enter's arms are not the two ISO shapes`);
            }
            // ...and the two the numpad draws across two rows are ONE key
            // each, which is what stops the pad showing two Enters.
            for (const code of Object.keys(tallKeys))
                compare(placed(name, Number(code)).length, 1,
                    `${name}: ${tallKeys[code]} is more than one key`);
        }
    }

    function test_a_double_height_key_is_one_key_of_two_units() {
        for (const name of layoutNames()) {
            for (const code of Object.keys(tallKeys)) {
                const entries = placed(name, Number(code));
                compare(entries.length, 1, `${name}: ${tallKeys[code]} is not one key`);
                const entry = entries[0];
                // Two units tall AND reaching two rows, because a height table
                // saying 2 while the lattice hands out one row is a key drawn
                // over the row below it, and a rowSpan of 2 on a one-unit-tall
                // key is a key half the height of its own cell.
                compare(KeyShapes.heightUnits[entry.key.shape], 2,
                    `${name}: ${tallKeys[code]} is not two units tall`);
                compare(entry.rows, 2, `${name}: ${tallKeys[code]} does not span two rows`);
                compare(entry.units, 1, `${name}: ${tallKeys[code]} is not one unit wide`);
            }
        }
    }

    function test_every_width_is_a_whole_number_of_columns() {
        // The lattice's column is a quarter unit, so a shape whose width is
        // not a multiple of 0.25u is drawn at a rounded span - every column
        // after it moves, and nothing reports it.
        const offenders = Lattice.widthsAreWholeColumns();
        compare(offenders.join(","), "",
            `these shapes are not a whole number of quarter units: ${offenders.join(", ")}`);
    }

    function test_every_shape_a_layout_names_is_in_both_tables() {
        const declaredWidths = Object.keys(KeyShapes.widthUnits).sort();
        const declaredHeights = Object.keys(KeyShapes.heightUnits).sort();
        // A shape in one table and not the other silently falls back to a
        // single unit in the axis that is missing it.
        compare(declaredHeights.join(","), declaredWidths.join(","),
            "the width and height tables declare different shapes");

        const used = ({});
        for (const name of layoutNames()) {
            for (const entry of keysOf(name)) {
                used[entry.key.shape] = true;
                verify(typeof KeyShapes.widthUnits[entry.key.shape] === "number",
                    `${name} names shape "${entry.key.shape}", which has no width`);
                verify(typeof KeyShapes.heightUnits[entry.key.shape] === "number",
                    `${name} names shape "${entry.key.shape}", which has no height`);
            }
        }
        // The other direction: a shape nothing draws is one nobody rechecks.
        for (const shape of declaredWidths)
            verify(used[shape] === true, `shape "${shape}" is declared and never used`);
    }

    function test_every_row_covers_the_whole_keyboard() {
        for (const name of layoutNames()) {
            const rows = Layouts.byName[name].keys;
            compare(rows.length, 6, `${name} does not have six rows`);
            const placements = Lattice.place(rows);
            compare(Lattice.columnsIn(placements) / Lattice.COLUMNS_PER_UNIT, rowUnits,
                `${name} is not ${rowUnits} units wide`);
            for (let r = 0; r < rows.length; r++) {
                // Counted off the lattice rather than by summing the row's own
                // keys, because a row under a double-height key does not
                // declare the columns that key already took.
                const units = Lattice.columnsCovered(placements, r) / Lattice.COLUMNS_PER_UNIT;
                compare(units, rowUnits, `${name} row ${r} covers ${units} units`);
            }
        }
    }

    function test_the_arrow_cluster_is_an_inverted_T() {
        for (const name of layoutNames()) {
            const up = placed(name, 103)[0];
            const left = placed(name, 105)[0];
            const down = placed(name, 108)[0];
            const right = placed(name, 106)[0];
            compare(up.offset, down.offset, `${name}: up is not over down`);
            compare(up.row, down.row - 1, `${name}: up is not the row above down`);
            compare(left.row, down.row, `${name}: left is not beside down`);
            compare(right.row, down.row, `${name}: right is not beside down`);
            compare(left.offset, down.offset - 1, `${name}: left is not one unit left of down`);
            compare(right.offset, down.offset + 1, `${name}: right is not one unit right of down`);
        }
    }

    function test_the_numpad_stands_in_its_own_four_columns() {
        // One key per numpad column, read down the pad. The point is not that
        // they are at 19 units - it is that they are all at the SAME offset,
        // which is what a column is.
        const firstColumn = [69, 71, 75, 79, 82];
        const lastColumn = [74, 78, 96];
        for (const name of layoutNames()) {
            for (const code of firstColumn) {
                for (const entry of placed(name, code))
                    compare(entry.offset, numpadStart,
                        `${name}: keycode ${code} is not in the numpad's first column`);
            }
            for (const code of lastColumn) {
                for (const entry of placed(name, code))
                    compare(entry.offset, numpadStart + numpad - 1,
                        `${name}: keycode ${code} is not in the numpad's last column`);
            }
            // The wide zero spans two columns, so the decimal point sits in
            // the third rather than beside it.
            const zero = placed(name, 82)[0];
            compare(zero.units, 2, `${name}: the numpad's zero is not two units`);
            compare(placed(name, 83)[0].offset, numpadStart + 2,
                `${name}: the numpad's decimal point is not in the third column`);
        }
    }

    function test_the_layouts_agree_on_everything_but_their_alphabet() {
        const offered = ({});
        for (const name of layoutNames()) {
            const codes = ({});
            for (const entry of keysOf(name))
                if (entry.key.keytype !== "spacer")
                    codes[entry.key.keycode] = true;
            offered[name] = codes;
            for (const code of sharedKeycodes)
                verify(codes[code] === true, `${name} does not offer keycode ${code}`);
        }
        // Every difference between two layouts is a main-block difference, and
        // there is exactly one of those: the extra key an ISO board has.
        const names = layoutNames();
        for (const a of names) {
            for (const b of names) {
                for (const code of Object.keys(offered[a])) {
                    if (offered[b][code] === true)
                        continue;
                    compare(Number(code), isoExtraKey,
                        `${a} offers keycode ${code} and ${b} does not`);
                }
            }
        }
    }
}
