.pragma library

.import "layout_ops.js" as LayoutOps

// What the Android quick toggle grid holds, in what order, and where each tile
// sits - as arithmetic, so the decisions are testable and the rendering does
// not have to be.
//
// Two answers live here and they are separate on purpose.
//
// `pack` is the grid: entries wrap into rows by size against the column count,
// and every entry gets a stable id and a slot. `syncPlan` is the DIFF: what a
// keyed `ListModel` must do to become that list. The second is why this file
// exists at all. A row entry that changes IDENTITY in place keeps the delegate
// it already had, and `DelegateChooser` picks a component when a delegate is
// created and never re-picks for one that survives - so the panel used to show,
// at each position, whatever toggle used to be there
// (81379796b ("fix(sidebar): choose a delegate for the toggle each row entry
// now holds")). That was answered by resetting the whole row, which is correct
// and costs the delegate: a reorder that rebuilds every tile cannot animate,
// because there is nothing left to move.
//
// The plan makes both true at once. A reorder comes out as a `move`, so the
// delegate survives and can travel to its new slot; and an id is permanently
// bound to one toggle TYPE, so the chooser can never be asked to re-pick for a
// surviving row. A payload change (a size, a slot) is emitted only where it is
// a real difference, so an edit that repacks nothing writes nothing.
//
// The list edits the plan is simulated against are `layout_ops.js`'s, not a
// second copy: a plan that reorders one way and a call site that reorders
// another is exactly the disagreement that module was extracted to end.

// A stored size is whatever is in `config.json`, which a human edits and a
// preset can carry. `ListModel` roles are typed from the first row inserted, so
// a missing or non-numeric size is not a cosmetic problem - it poisons the
// role. One place normalises it.
function sizeOf(entry) {
    var size = Math.round(Number(entry && entry.size));
    return (isFinite(size) && size >= 1) ? size : 1;
}

function columnsOf(columns) {
    var count = Math.floor(Number(columns));
    return (isFinite(count) && count >= 1) ? count : 1;
}

// The id is the toggle's type, because the panel holds one of each - and an
// occurrence counter behind it, because nothing enforces that. A hand-edited
// config or an imported preset naming `network` twice would otherwise collapse
// two rows onto one id: the second toggle would not disappear from the store,
// only from the screen, which is the quietest failure available here.
function idFor(type, occurrence) {
    return occurrence === 1 ? type : type + "#" + occurrence;
}

// Rows are packed by size, so nearly every edit reflows them - which is what
// made the delegate identity problem reach across row boundaries in the first
// place. `layoutSlot` counts CELLS consumed before the tile in its row rather
// than tiles, so a caller multiplies by one cell pitch and needs no running
// total of its own.
//
// `sourceIndex` is the entry's index in the list handed in, not its index here.
// The two differ whenever the source holds something unrenderable, and the call
// sites that delete, resize and reorder write to the SOURCE - a drag that
// committed a packed index would edit the wrong entry, silently, only in a
// config that already had a hole in it.
function pack(entries, columns) {
    var cols = columnsOf(columns);
    var packed = [];
    var occurrences = {};
    var row = 0;
    var used = 0;

    for (var i = 0; i < (entries ? entries.length : 0); i++) {
        var entry = entries[i];
        if (!entry || !entry.type) continue;

        var size = sizeOf(entry);
        // `used > 0` guards the row rather than the entry: an entry wider than
        // the whole grid still has to be placed, and wrapping before it when
        // nothing is in the row yet leaves an empty row above it.
        if (used > 0 && used + size > cols) {
            row++;
            used = 0;
        }

        var occurrence = (occurrences[entry.type] || 0) + 1;
        occurrences[entry.type] = occurrence;

        packed.push({
            itemId: idFor(entry.type, occurrence),
            type: entry.type,
            size: size,
            layoutRow: row,
            layoutSlot: used,
            sourceIndex: i
        });
        used += size;
    }

    return packed;
}

// A cell is what is left of the grid once the gaps BETWEEN the columns are
// taken out, and there are one fewer of those than there are columns. The panel
// used to divide by the column count's worth of gaps and come up one gap short,
// which never showed because each row was a `RowLayout` and the first tile in
// it carried `Layout.fillWidth`: the leftover was silently absorbed by whichever
// tile happened to be first, so the row filled the panel and one tile in it was
// 8px wider than the pitch said. Placing tiles by arithmetic makes the shortfall
// visible as a gap at the right-hand edge instead, so the pitch has to be right.
function cellWidth(contentWidth, spacing, columns) {
    var cols = columnsOf(columns);
    return (contentWidth - spacing * (cols - 1)) / cols;
}

function rowCount(packed) {
    if (!packed || packed.length === 0) return 0;
    return packed[packed.length - 1].layoutRow + 1;
}

// Everything a row carries that is NOT its identity. The two lists are the
// whole contract between the plan and the model: the payload is what an
// `update` may write, and what is missing from it - `itemId` and `type` - is
// what a surviving row may never be given.
var PAYLOAD_ROLES = ["size", "layoutRow", "layoutSlot", "sourceIndex"];
var IDENTITY_ROLES = ["itemId", "type"];

function indexOfId(rows, itemId) {
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].itemId === itemId) return i;
    }
    return -1;
}

function payloadDiffers(row, wanted) {
    for (var i = 0; i < PAYLOAD_ROLES.length; i++) {
        var role = PAYLOAD_ROLES[i];
        if (row[role] !== wanted[role]) return true;
    }
    return false;
}

// The ops that turn `current` into `desired`, in the order a `ListModel` must
// apply them - each index is valid at the moment its own op runs, which is why
// the plan is built against a mirror of the model rather than against the
// indices of either list.
//
// Removals go first and from the end, so an index behind one is still the index
// the model will see. Then one pass forwards: a row that is present travels to
// where it belongs and a row that is not is inserted there, so every index at
// or below the cursor is settled before the cursor moves past it.
function syncPlan(current, desired) {
    var ops = [];
    var mirror = (current || []).map(function (row) {
        var copy = {};
        IDENTITY_ROLES.concat(PAYLOAD_ROLES).forEach(function (role) {
            copy[role] = row[role];
        });
        return copy;
    });
    var wantedList = desired || [];

    var wanted = {};
    for (var w = 0; w < wantedList.length; w++) wanted[wantedList[w].itemId] = true;

    for (var i = mirror.length - 1; i >= 0; i--) {
        if (wanted[mirror[i].itemId]) continue;
        ops.push({ op: "remove", index: i });
        mirror = LayoutOps.remove(mirror, i);
    }

    for (var target = 0; target < wantedList.length; target++) {
        var entry = wantedList[target];
        var at = indexOfId(mirror, entry.itemId);

        // An id is bound to one type for the life of the row. Nothing in the
        // panel can break that - the id is derived from the type - so reaching
        // here means the input did, and the answer is to rebuild THIS row
        // rather than to retype a live one: a delegate handed a new type keeps
        // the component it was built with, which is the bug this file exists
        // for, one row at a time instead of a whole panel.
        if (at !== -1 && mirror[at].type !== entry.type) {
            ops.push({ op: "remove", index: at });
            mirror = LayoutOps.remove(mirror, at);
            at = -1;
        }

        if (at === -1) {
            ops.push({ op: "insert", index: target, entry: entry });
            mirror = LayoutOps.insert(mirror, entry, target);
            continue;
        }

        if (at !== target) {
            ops.push({ op: "move", from: at, to: target });
            mirror = LayoutOps.move(mirror, at, target);
        }

        if (payloadDiffers(mirror[target], entry)) {
            ops.push({ op: "update", index: target, entry: entry });
            mirror[target] = entry;
        }
    }

    return ops;
}

// What the model would be after a sync, as a string. A panel observes this
// rather than the array it came from: the quick toggles mutate the live
// `Config` array in place (26b625905 ("Revert \"fix(sidebar): make quick toggle
// edits actually notify\" and follow-ups")), so the identity of that array is
// not evidence of anything, and firing on a value that changes exactly when the
// plan would be non-empty is what makes observing it free.
function signatureOf(entries, columns) {
    return pack(entries, columns).map(function (entry) {
        return entry.itemId + ":" + entry.type + ":" + entry.size + ":"
            + entry.layoutRow + ":" + entry.layoutSlot + ":" + entry.sourceIndex;
    }).join(",");
}
