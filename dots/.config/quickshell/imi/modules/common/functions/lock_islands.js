.pragma library

// The lock islands' order as arithmetic (spec §14, answered "reorder" by the
// maintainer on 2026-08-17): three ordered lists in `Config.options.lock.
// islands`, one per island, and this module is the only place that turns a
// stored list into the order the surface draws.
//
// Kept beside `edit_mode.js` for the reason everything else here is: nothing
// about the rendered islands is reachable from `qmltestrunner`, so the
// decisions - what renders, in what order, and what survives a version skew -
// have to be arithmetic a test can hold still.

// The default order of each island is the hand-placed order LockSurface has
// always drawn, so a config that has never stored a list renders exactly what
// it rendered before the lists existed. Config.qml's schema defaults must
// equal these lists - tests/test_lock_islands_contract.py pins the two
// against each other, because two copies of a default that must agree is the
// drift AGENT.md keeps recording.
var MAIN_DEFAULT = ["fingerprint", "password", "confirm"];
var LEFT_DEFAULT = ["username", "media", "keyboardLayout", "fcitx"];
var RIGHT_DEFAULT = ["battery", "sleep", "power", "reboot"];

// The password field is rendered from the main list like everything else and
// is NOT a reorderable item (spec §14: the main island's rewrite is a
// different job because of it). Its neighbours may move around it; it takes
// no drag of its own.
function reorderable(island, id) {
    return !(island === "main" && id === "password");
}

// The order the island DRAWS, resolved from the stored list against the
// island's defaults. Two rules, both about version skew, both the
// `gridSizes.resolveSize` rule applied to a list:
//
// - a known id MISSING from the stored list (a list written by an older
//   version) renders at its default position rather than disappearing -
//   silent removal is exactly what a list written by one version and read by
//   another produces otherwise;
// - an UNKNOWN stored id (a list written by a newer version) is skipped for
//   rendering - there is nothing to draw for it - but the store is not
//   rewritten here: resolving is a read, and destroying a newer version's
//   entry on read is the other half of the same defect.
//
// Index-walked rather than filtered/mapped because the stored list arrives as
// a QML list property: indices and `length` survive the QVariant crossing,
// the Array brand does not (the boundary gridSizes.js documents).
function orderedItems(stored, defaults) {
    var order = [];
    var count = stored && typeof stored.length === "number" ? stored.length : 0;
    for (var i = 0; i < count; i++) {
        var id = stored[i];
        if (defaults.indexOf(id) !== -1 && order.indexOf(id) === -1)
            order.push(id);
    }
    for (var d = 0; d < defaults.length; d++) {
        if (order.indexOf(defaults[d]) !== -1)
            continue;
        var at = 0;
        for (var p = d - 1; p >= 0; p--) {
            var prev = order.indexOf(defaults[p]);
            if (prev !== -1) {
                at = prev + 1;
                break;
            }
        }
        order.splice(at, 0, defaults[d]);
    }
    return order;
}

// What a committed reorder writes: the rendered order with the move applied,
// plus every unknown stored id appended in its stored order. Appending loses
// an unknown id's position but never its presence - a newer version reading
// the list back still renders its item (and its own resolver decides where),
// where dropping it would be the silent removal this module exists to
// prevent. The move itself is layout_ops' move semantics, applied by the
// caller before this merge; this function only answers what reaches the
// store.
function storedOrder(moved, stored, defaults) {
    var result = moved.slice();
    var count = stored && typeof stored.length === "number" ? stored.length : 0;
    for (var i = 0; i < count; i++) {
        if (defaults.indexOf(stored[i]) === -1 && result.indexOf(stored[i]) === -1)
            result.push(stored[i]);
    }
    return result;
}
