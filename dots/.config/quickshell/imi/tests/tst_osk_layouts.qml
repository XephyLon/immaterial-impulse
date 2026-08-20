import QtTest
import "../modules/imi/onScreenKeyboard/layouts.js" as Layouts
import "../modules/imi/onScreenKeyboard/key_shapes.js" as KeyShapes

// The on-screen keyboard's layouts are plain data, which makes them the one
// part of that module a test can reach: nothing about a rendered key is
// reachable from qmltestrunner, and OskLayoutProbe.qml exists for the half
// that is a picture.
//
// What is worth pinning here is what breaks silently. A key with the wrong
// evdev keycode types the wrong character and nothing anywhere reports it. A
// row that spans anything other than the full width puts that row's nav
// cluster and numpad somewhere the rows above and below do not, and the row is
// still a perfectly good row. A shape in one multiplier table and not the
// other falls back to one unit, which is a plausible size for most keys. And a
// keycode that appears twice is a typo everywhere except the three places a
// real keyboard draws one key across two rows.
TestCase {
    name: "OskLayoutsTest"

    // The full-size lattice every row is laid out on, in keyboard units.
    readonly property real mainBlock: 15
    readonly property real clusterGap: 0.5
    readonly property real navCluster: 3
    readonly property real numpad: 4
    readonly property real rowUnits: mainBlock + clusterGap + navCluster + clusterGap + numpad
    readonly property real numpadStart: mainBlock + clusterGap + navCluster + clusterGap

    // The keys a real keyboard draws as ONE key spanning two rows, which a row
    // of keys cannot say - each is two keys carrying the one keycode.
    readonly property var splitKeys: ({
        78: "numpad +",
        96: "numpad Enter",
        28: "ISO Enter"
    })

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

    function keysOf(name) {
        const rows = Layouts.byName[name].keys;
        const out = [];
        for (let r = 0; r < rows.length; r++) {
            let offset = 0;
            for (let c = 0; c < rows[r].length; c++) {
                const key = rows[r][c];
                const units = KeyShapes.widthUnits[key.shape];
                out.push({ key: key, row: r, offset: offset, units: units });
                offset += units;
            }
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

    function test_a_keycode_repeats_only_where_one_key_spans_two_rows() {
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
                verify(splitKeys.hasOwnProperty(code),
                    `${name} sends keycode ${code} from ${rows.length} keys`);
                compare(rows.length, 2, `${name}: ${splitKeys[code]} is not two keys`);
                // The halves of a key that is two rows tall are in those two
                // rows. Two halves anywhere else is a keycode typed twice.
                compare(rows[1] - rows[0], 1,
                    `${name}: ${splitKeys[code]}'s halves are not in adjacent rows`);
            }
            // ...and the two the numpad always has are always there: a half
            // deleted by hand leaves a keyboard that still lays out.
            compare(placed(name, 78).length, 2, `${name} numpad + is not two keys`);
            compare(placed(name, 96).length, 2, `${name} numpad Enter is not two keys`);
        }
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

    function test_every_row_spans_the_whole_keyboard() {
        for (const name of layoutNames()) {
            const rows = Layouts.byName[name].keys;
            compare(rows.length, 6, `${name} does not have six rows`);
            for (let r = 0; r < rows.length; r++) {
                let units = 0;
                for (const key of rows[r])
                    units += KeyShapes.widthUnits[key.shape];
                compare(units, rowUnits, `${name} row ${r} spans ${units} units`);
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
