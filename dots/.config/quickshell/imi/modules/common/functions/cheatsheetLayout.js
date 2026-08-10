.pragma library

// Turning the parsed keybind tree into cheatsheet columns.
//
// Two jobs, and the first one is a bug fix. The renderer used to draw only a
// group's `children`, so any group holding keybinds at its OWN level drew
// nothing at all - on this machine that silently dropped 48 keybinds
// (Utilities, Screen, Media, plus the tree root's own). `sections()` flattens
// the tree into every node that actually has keybinds, so a group is rendered
// for what it holds rather than for where it sits.
//
// The second is layout. Columns used to come from the tree's top-level
// children, which is an authoring detail of keybinds.lua, not a layout
// decision: it produced one tall column beside three-quarters of empty screen.
// `balance()` packs the flattened sections into a chosen number of columns,
// shortest-column-first, so the card grows sideways instead of downwards.

// Every node carrying keybinds, depth-first, with its display name.
//
// A node with keybinds AND children yields its own section first, then its
// children - that is the order they were authored in. Unnamed nodes (the tree
// root, and the anonymous groups keybinds.lua uses purely for grouping) keep
// their keybinds but contribute no heading, since inventing one would be
// worse than the blank the author chose.
function sections(node) {
    const out = [];
    if (!node) return out;

    const keybinds = node.keybinds || [];
    if (keybinds.length > 0) {
        out.push({
            name: node.name || "",
            keybinds: keybinds,
            // What the column packer measures. Rows plus a heading if there is
            // one; the caller scales it by real row height.
            weight: keybinds.length + (node.name ? 1 : 0)
        });
    }
    for (const child of (node.children || [])) {
        for (const section of sections(child)) out.push(section);
    }
    return out;
}

// Pack sections into `count` columns, keeping author order within a column.
//
// Shortest-column-first rather than an even split by index: sections vary from
// 2 to 15 rows, so splitting by count alone leaves one column twice the height
// of its neighbour. Greedy is not optimal packing, but it is stable - the same
// input always produces the same layout, which matters more here than a
// perfect balance nobody can perceive.
function balance(sectionList, count) {
    const columns = [];
    const heights = [];
    for (let i = 0; i < Math.max(1, count); i++) {
        columns.push([]);
        heights.push(0);
    }
    for (const section of (sectionList || [])) {
        let target = 0;
        for (let i = 1; i < heights.length; i++) {
            if (heights[i] < heights[target]) target = i;
        }
        columns[target].push(section);
        heights[target] += section.weight;
    }
    return columns;
}

// How many columns to ask for, given how much vertical room there is.
//
// Derived from the content rather than fixed: the point is to stop growing
// downwards past the screen. Start at one column and add columns until the
// tallest would fit, capped so a short keybind list does not fan out into
// slivers.
function columnCount(sectionList, availableRows, maxColumns) {
    const list = sectionList || [];
    if (list.length === 0) return 1;
    const total = list.reduce((sum, section) => sum + section.weight, 0);
    const rows = Math.max(1, availableRows || 1);
    const cap = Math.max(1, Math.min(maxColumns || 4, list.length));
    return Math.max(1, Math.min(cap, Math.ceil(total / rows)));
}
