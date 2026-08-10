import QtTest
import "../modules/common/functions/cheatsheetLayout.js" as Layout

// Flattening the keybind tree into cheatsheet sections, and packing those into
// columns. Both used to be implicit in the renderer's structure, which is how
// 48 keybinds went missing: it drew a group's `children` and never the group's
// own `keybinds`, so any node holding binds directly rendered nothing.
TestCase {
    name: "CheatsheetLayoutTest"

    function tree() {
        // The real shape on this machine: the root holds binds AND groups, two
        // anonymous groups exist purely for grouping, and one named section is
        // empty.
        return {
            name: "",
            keybinds: new Array(20).fill({}),
            children: [
                { name: "Utilities", keybinds: new Array(14).fill({}), children: [] },
                { name: "Screen", keybinds: new Array(2).fill({}), children: [] },
                { name: "Media", keybinds: new Array(12).fill({}), children: [] },
                { name: "", keybinds: [], children: [
                    { name: "Window", keybinds: new Array(15).fill({}), children: [] },
                    { name: "Workspace", keybinds: new Array(5).fill({}), children: [] },
                    { name: "Virtual machines", keybinds: [], children: [] }
                ]},
                { name: "", keybinds: [], children: [
                    { name: "Session", keybinds: new Array(2).fill({}), children: [] },
                    { name: "Apps", keybinds: new Array(11).fill({}), children: [] }
                ]}
            ]
        };
    }

    // --- flattening --------------------------------------------------------

    function test_a_group_with_its_own_keybinds_becomes_a_section() {
        // The bug. Utilities/Screen/Media hold binds at their own level and
        // have no children, so the old renderer drew nothing for them.
        const names = Layout.sections(tree()).map(s => s.name);
        verify(names.indexOf("Utilities") >= 0);
        verify(names.indexOf("Screen") >= 0);
        verify(names.indexOf("Media") >= 0);
    }

    function test_no_keybind_is_dropped() {
        const total = Layout.sections(tree())
            .reduce((sum, s) => sum + s.keybinds.length, 0);
        compare(total, 20 + 14 + 2 + 12 + 15 + 5 + 2 + 11);
    }

    function test_the_roots_own_keybinds_survive_without_inventing_a_heading() {
        const root = Layout.sections(tree())[0];
        compare(root.name, "");
        compare(root.keybinds.length, 20);
    }

    function test_an_empty_named_section_is_not_rendered() {
        // "Virtual machines" has no binds; a bare heading over nothing is what
        // the screenshot showed and it reads as a broken section.
        const names = Layout.sections(tree()).map(s => s.name);
        compare(names.indexOf("Virtual machines"), -1);
    }

    function test_author_order_is_preserved() {
        const names = Layout.sections(tree()).map(s => s.name).filter(n => n.length > 0);
        compare(names, ["Utilities", "Screen", "Media", "Window",
                        "Workspace", "Session", "Apps"]);
    }

    function test_an_empty_tree_is_no_sections_not_a_crash() {
        compare(Layout.sections(null).length, 0);
        compare(Layout.sections({}).length, 0);
    }

    // --- packing -----------------------------------------------------------

    function test_every_section_lands_in_exactly_one_column() {
        const list = Layout.sections(tree());
        const columns = Layout.balance(list, 3);
        let packed = 0;
        for (const column of columns) packed += column.length;
        compare(packed, list.length);
    }

    function test_columns_are_balanced_by_height_not_by_count() {
        // Splitting by index would put the 20-row root and the 15-row Window
        // section together and leave a stub column beside them.
        const columns = Layout.balance(Layout.sections(tree()), 3);
        const heights = columns.map(c => c.reduce((sum, s) => sum + s.weight, 0));
        const tallest = Math.max.apply(null, heights);
        const shortest = Math.min.apply(null, heights);
        verify(tallest - shortest <= 20); // no column is double another
    }

    function test_packing_is_stable() {
        const a = Layout.balance(Layout.sections(tree()), 3).map(c => c.map(s => s.name).join(","));
        const b = Layout.balance(Layout.sections(tree()), 3).map(c => c.map(s => s.name).join(","));
        compare(a, b);
    }

    function test_one_column_is_the_floor() {
        compare(Layout.balance(Layout.sections(tree()), 0).length, 1);
        compare(Layout.balance(Layout.sections(tree()), -3).length, 1);
    }

    // --- choosing the column count ----------------------------------------

    function test_more_content_than_height_asks_for_more_columns() {
        const list = Layout.sections(tree()); // 88 rows of weight
        verify(Layout.columnCount(list, 30, 4) > 1);
        compare(Layout.columnCount(list, 1000, 4), 1); // all of it fits in one
    }

    function test_the_cap_is_respected() {
        compare(Layout.columnCount(Layout.sections(tree()), 5, 3), 3);
    }

    function test_a_short_list_never_fans_out_into_slivers() {
        // Two sections cannot become four columns, however little room there is.
        const two = [{name: "a", keybinds: [], weight: 3},
                     {name: "b", keybinds: [], weight: 3}];
        compare(Layout.columnCount(two, 1, 4), 2);
    }

    function test_no_sections_is_one_column() {
        compare(Layout.columnCount([], 10, 4), 1);
    }
}
