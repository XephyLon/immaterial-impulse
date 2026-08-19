import QtTest
import "../modules/common/functions/quick_toggle_layout.js" as QuickToggleLayout

// The Android quick toggle grid, as the two decisions behind it: where a tile
// sits, and what a keyed model must DO to become the list it is handed.
//
// The second is the one worth testing hardest. A reorder that comes out as a
// remove and an insert is a correct list and a destroyed delegate, which is
// indistinguishable from a move in every assertion about the model's contents -
// so most of what is checked here is the ops themselves, not the answer they
// produce.
TestCase {
    name: "QuickToggleLayoutTest"

    function entries(spec) {
        return spec.map(pair => ({ type: pair[0], size: pair[1] }));
    }

    function ids(packed) {
        return packed.map(entry => entry.itemId).join(",");
    }

    function opNames(ops) {
        return ops.map(op => op.op).join(",");
    }

    // What a ListModel would hold after applying the plan, so a plan can be
    // scored against the list it claims to produce rather than only against the
    // ops someone expected to see.
    function applied(current, ops) {
        let rows = current.slice();
        for (const op of ops) {
            if (op.op === "remove") rows.splice(op.index, 1);
            else if (op.op === "insert") rows.splice(op.index, 0, op.entry);
            else if (op.op === "move") rows.splice(op.to, 0, rows.splice(op.from, 1)[0]);
            else if (op.op === "update") rows[op.index] = op.entry;
        }
        return rows;
    }

    function compareRows(rows, expected, message) {
        compare(rows.length, expected.length, message + " (length)");
        for (let i = 0; i < expected.length; i++) {
            for (const role of ["itemId", "type", "size", "layoutRow", "layoutSlot", "sourceIndex"])
                compare(rows[i][role], expected[i][role],
                        message + " (row " + i + " " + role + ")");
        }
    }

    function test_a_row_takes_as_many_cells_as_the_column_count() {
        const packed = QuickToggleLayout.pack(
            entries([["network", 2], ["idleInhibitor", 1], ["bluetooth", 2],
                     ["audio", 2], ["mic", 1], ["nightLight", 2]]), 5);
        compare(packed.map(entry => entry.layoutRow).join(","), "0,0,0,1,1,1");
        // A slot counts CELLS consumed before the tile, not tiles: the third
        // entry of a row that already holds a double and a single starts at 3.
        compare(packed.map(entry => entry.layoutSlot).join(","), "0,2,3,0,2,3");
        compare(QuickToggleLayout.rowCount(packed), 2);
    }

    function test_a_full_row_of_cells_fills_the_grid_exactly() {
        // There is one fewer gap than there are columns. Dividing by the column
        // count's worth of gaps leaves a row one gap short of the panel, which
        // is invisible under a RowLayout - `Layout.fillWidth` hands the
        // shortfall to whichever tile is first - and is a gap at the right-hand
        // edge once tiles are placed by arithmetic.
        const contentWidth = 484;
        const spacing = 8;
        for (const columns of [1, 2, 5, 8]) {
            const cell = QuickToggleLayout.cellWidth(contentWidth, spacing, columns);
            fuzzyCompare(cell * columns + spacing * (columns - 1), contentWidth, 0.0001,
                         "a full row of " + columns + " cells does not fill the grid");
        }
    }

    function test_an_entry_wider_than_the_grid_leaves_no_empty_row_above_it() {
        // Wrapping is a question about the ROW, not about the entry: an entry
        // that cannot fit anywhere still has to be placed, and wrapping before
        // it while the row is empty puts a row of nothing above it.
        const packed = QuickToggleLayout.pack(
            entries([["network", 3], ["mic", 1]]), 2);
        compare(packed[0].layoutRow, 0);
        compare(packed[0].layoutSlot, 0);
        compare(packed[1].layoutRow, 1);
        compare(QuickToggleLayout.rowCount(packed), 2);
    }

    function test_an_unusable_entry_is_skipped_and_the_stored_index_survives_it() {
        // The call sites that delete, resize and reorder write to the stored
        // list, so a packed entry has to carry where it came from - a hole in
        // the source is the case where the two framings come apart, and it is
        // reachable from a hand-edited config.
        const packed = QuickToggleLayout.pack(
            [{ type: "network", size: 1 }, null, { type: "mic", size: 1 }], 4);
        compare(packed.length, 2);
        compare(packed.map(entry => entry.sourceIndex).join(","), "0,2");
    }

    function test_a_size_that_is_not_a_size_becomes_one() {
        // A ListModel types its roles from the first row inserted, so a missing
        // or non-numeric size does not merely render oddly - it poisons the
        // role for every row after it.
        const packed = QuickToggleLayout.pack(
            [{ type: "network" }, { type: "mic", size: "2" },
             { type: "audio", size: 0 }, { type: "vpn", size: -3 }], 8);
        compare(packed.map(entry => entry.size).join(","), "1,2,1,1");
    }

    function test_one_type_named_twice_is_two_rows() {
        // Nothing enforces one toggle per type - a hand-edited config or an
        // imported preset can name one twice - and collapsing them onto one id
        // would drop the second from the screen while leaving it in the store.
        const packed = QuickToggleLayout.pack(
            entries([["network", 1], ["mic", 1], ["network", 1]]), 4);
        compare(ids(packed), "network,mic,network#2");
        compare(packed[2].type, "network");
    }

    function test_a_reorder_is_a_move_and_not_a_rebuild() {
        // The whole point. A remove-and-insert produces the same list and
        // destroys the delegate, which is what made an animated reorder
        // impossible: there is nothing left to travel.
        const before = QuickToggleLayout.pack(
            entries([["network", 1], ["mic", 1], ["audio", 1], ["vpn", 1]]), 4);
        const after = QuickToggleLayout.pack(
            entries([["vpn", 1], ["network", 1], ["mic", 1], ["audio", 1]]), 4);
        const ops = QuickToggleLayout.syncPlan(before, after);
        verify(ops.some(op => op.op === "move"), "no move was planned: " + opNames(ops));
        verify(!ops.some(op => op.op === "remove" || op.op === "insert"),
               "a reorder was planned as a rebuild: " + opNames(ops));
        compareRows(applied(before, ops), after, "the plan did not produce the wanted list");
    }

    function test_a_move_across_a_row_boundary_is_still_a_move() {
        // The case a per-row model cannot express at all, and the reason the
        // grid is one flat model: an entry crossing a row boundary leaves one
        // row's model and lands in another's, at an index some other toggle
        // held, which is not a move in either of them.
        const before = QuickToggleLayout.pack(
            entries([["network", 2], ["mic", 2], ["audio", 2], ["vpn", 2]]), 4);
        const after = QuickToggleLayout.pack(
            entries([["network", 2], ["vpn", 2], ["mic", 2], ["audio", 2]]), 4);
        compare(before[3].layoutRow, 1);
        compare(after[1].layoutRow, 0, "the fixture must move an entry between rows");
        const ops = QuickToggleLayout.syncPlan(before, after);
        verify(!ops.some(op => op.op === "remove" || op.op === "insert"),
               "a cross-row move was planned as a rebuild: " + opNames(ops));
        compareRows(applied(before, ops), after, "the plan did not produce the wanted list");
    }

    function test_the_indices_in_a_plan_are_valid_as_the_plan_runs() {
        // Every index is read by the model at the moment its own op runs, not
        // against either input list - removals from the end, then one forward
        // pass - so an unapplyable plan is the failure to look for here rather
        // than a wrong final list.
        const before = QuickToggleLayout.pack(
            entries([["network", 1], ["mic", 1], ["audio", 1], ["vpn", 1], ["darkMode", 1]]), 5);
        const after = QuickToggleLayout.pack(
            entries([["gameMode", 1], ["vpn", 1], ["network", 1], ["screenSnip", 1]]), 5);
        const ops = QuickToggleLayout.syncPlan(before, after);
        let length = before.length;
        for (const op of ops) {
            if (op.op === "remove") {
                verify(op.index >= 0 && op.index < length, "remove index out of range: " + op.index);
                length--;
            } else if (op.op === "insert") {
                verify(op.index >= 0 && op.index <= length, "insert index out of range: " + op.index);
                length++;
            } else if (op.op === "move") {
                verify(op.from >= 0 && op.from < length && op.to >= 0 && op.to < length,
                       "move out of range: " + op.from + " -> " + op.to);
            } else {
                verify(op.index >= 0 && op.index < length, "update index out of range: " + op.index);
            }
        }
        compareRows(applied(before, ops), after, "the plan did not produce the wanted list");
    }

    function test_an_unchanged_list_plans_nothing() {
        // The gate that makes observing generously free: a re-evaluation that
        // produces the same grid must not write to the model, or every
        // unrelated config change repaints the panel.
        const packed = QuickToggleLayout.pack(
            entries([["network", 2], ["mic", 1]]), 4);
        compare(QuickToggleLayout.syncPlan(packed, packed).length, 0);
        compare(QuickToggleLayout.syncPlan(
            packed, QuickToggleLayout.pack(entries([["network", 2], ["mic", 1]]), 4)).length, 0);
    }

    function test_a_payload_change_never_touches_a_row_identity() {
        // A resize repacks the grid and must reach the delegates as data. The
        // roles an update may write are the payload ones; `itemId` and `type`
        // are not among them, because a delegate handed a new type keeps the
        // component it was built with.
        const before = QuickToggleLayout.pack(entries([["network", 1], ["mic", 1]]), 4);
        const after = QuickToggleLayout.pack(entries([["network", 2], ["mic", 1]]), 4);
        const ops = QuickToggleLayout.syncPlan(before, after);
        compare(opNames(ops), "update,update");
        verify(QuickToggleLayout.PAYLOAD_ROLES.indexOf("type") === -1,
               "the type is writable as a payload role");
        verify(QuickToggleLayout.PAYLOAD_ROLES.indexOf("itemId") === -1,
               "the id is writable as a payload role");
        compareRows(applied(before, ops), after, "the plan did not produce the wanted list");
    }

    function test_an_id_that_changes_type_rebuilds_that_row_alone() {
        // Unreachable from the panel, where the id is derived from the type, so
        // reaching it means the input broke the contract. The answer is to
        // rebuild the one row rather than retype a live one - that is the
        // original bug, contained to a row instead of a panel - and the rows
        // either side must not be disturbed.
        const before = QuickToggleLayout.pack(entries([["network", 1], ["mic", 1], ["audio", 1]]), 4);
        const after = before.map(entry => ({
            itemId: entry.itemId,
            type: entry.itemId === "mic" ? "vpn" : entry.type,
            size: entry.size,
            layoutRow: entry.layoutRow,
            layoutSlot: entry.layoutSlot,
            sourceIndex: entry.sourceIndex
        }));
        const ops = QuickToggleLayout.syncPlan(before, after);
        compare(opNames(ops), "remove,insert");
        compare(ops[0].index, 1);
        compare(ops[1].index, 1);
        compareRows(applied(before, ops), after, "the plan did not produce the wanted list");
    }

    function test_the_signature_changes_exactly_when_the_plan_would_do_something() {
        // The panel observes the signature instead of the list, because a list
        // mutated in place is the same object before and after. That is only a
        // safe trade while the two agree, in BOTH directions: a signature that
        // misses a change stops the panel updating, and one that changes for
        // nothing syncs on every unrelated re-evaluation.
        const lists = [
            entries([["network", 2], ["mic", 1]]),
            entries([["network", 2], ["mic", 1]]),
            entries([["mic", 1], ["network", 2]]),
            entries([["network", 1], ["mic", 1]]),
            entries([["network", 2], ["mic", 1], ["audio", 1]]),
            entries([["network", 2]]),
            []
        ];
        for (const a of lists) {
            for (const b of lists) {
                const sameSignature = QuickToggleLayout.signatureOf(a, 4)
                    === QuickToggleLayout.signatureOf(b, 4);
                const planIsEmpty = QuickToggleLayout.syncPlan(
                    QuickToggleLayout.pack(a, 4), QuickToggleLayout.pack(b, 4)).length === 0;
                compare(sameSignature, planIsEmpty,
                        "signature and plan disagree for [" + a.map(e => e.type + e.size)
                        + "] -> [" + b.map(e => e.type + e.size) + "]");
            }
        }
        // The column count is an input to the pack, so it belongs in the
        // signature too - the entries are identical here and the grid is not.
        const one = entries([["network", 2], ["mic", 1]]);
        verify(QuickToggleLayout.signatureOf(one, 4) !== QuickToggleLayout.signatureOf(one, 2));
    }
}
