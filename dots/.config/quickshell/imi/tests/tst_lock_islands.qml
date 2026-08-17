import QtTest
import "../modules/common/functions/lock_islands.js" as LockIslands

// The lock islands' order, resolved and written back - the only part of the
// island rewrite qmltestrunner can reach. The version-skew rules are the whole
// point: a list written by one shell version and read by another is where a
// silent removal happens, so both directions (a known id the store lacks, an
// unknown id the store carries) are pinned here.
TestCase {
    name: "LockIslandsTest"

    function test_the_defaults_are_the_hand_placed_order() {
        compare(LockIslands.MAIN_DEFAULT, ["fingerprint", "password", "confirm"]);
        compare(LockIslands.LEFT_DEFAULT, ["username", "media", "keyboardLayout", "fcitx"]);
        compare(LockIslands.RIGHT_DEFAULT, ["battery", "sleep", "power", "reboot"]);
    }

    function test_a_stored_order_wins_for_the_ids_it_names() {
        compare(LockIslands.orderedItems(["media", "username", "keyboardLayout", "fcitx"],
                                         LockIslands.LEFT_DEFAULT),
                ["media", "username", "keyboardLayout", "fcitx"]);
    }

    function test_no_stored_list_renders_the_defaults() {
        compare(LockIslands.orderedItems(undefined, LockIslands.LEFT_DEFAULT),
                LockIslands.LEFT_DEFAULT);
        compare(LockIslands.orderedItems([], LockIslands.RIGHT_DEFAULT),
                LockIslands.RIGHT_DEFAULT);
    }

    function test_a_known_id_missing_from_the_store_renders_at_its_default_position() {
        // A list written by an older version: fcitx did not exist when it was
        // stored. It renders anyway, after keyboardLayout - its default
        // neighbour - rather than disappearing.
        compare(LockIslands.orderedItems(["media", "username", "keyboardLayout"],
                                         LockIslands.LEFT_DEFAULT),
                ["media", "username", "keyboardLayout", "fcitx"]);
        // ...and one missing from the MIDDLE lands between its default
        // neighbours, not at either end.
        compare(LockIslands.orderedItems(["reboot", "battery", "sleep"],
                                         LockIslands.RIGHT_DEFAULT),
                ["reboot", "battery", "sleep", "power"]);
    }

    function test_a_missing_leading_id_lands_at_the_front() {
        compare(LockIslands.orderedItems(["media", "keyboardLayout", "fcitx"],
                                         LockIslands.LEFT_DEFAULT),
                ["username", "media", "keyboardLayout", "fcitx"]);
    }

    function test_an_unknown_stored_id_is_skipped_without_eating_its_neighbours() {
        // A list written by a NEWER version: nothing to draw for the unknown
        // id, and the neighbours keep their stored order around the gap.
        compare(LockIslands.orderedItems(["media", "someFutureItem", "username",
                                          "keyboardLayout", "fcitx"],
                                         LockIslands.LEFT_DEFAULT),
                ["media", "username", "keyboardLayout", "fcitx"]);
    }

    function test_a_duplicated_stored_id_renders_once() {
        compare(LockIslands.orderedItems(["media", "media", "username",
                                          "keyboardLayout", "fcitx"],
                                         LockIslands.LEFT_DEFAULT),
                ["media", "username", "keyboardLayout", "fcitx"]);
    }

    function test_the_password_field_is_the_one_item_that_cannot_move() {
        verify(!LockIslands.reorderable("main", "password"));
        verify(LockIslands.reorderable("main", "fingerprint"));
        verify(LockIslands.reorderable("main", "confirm"));
        verify(LockIslands.reorderable("left", "media"));
        verify(LockIslands.reorderable("right", "power"));
    }

    function test_a_write_back_keeps_an_unknown_id_instead_of_deleting_it() {
        // The committed order is the moved rendered list plus every unknown
        // stored id appended: its position is lost, its PRESENCE is not - a
        // newer version reading the list back still renders its item, where
        // dropping it here would be the silent removal the module exists to
        // prevent.
        const stored = ["username", "someFutureItem", "media", "keyboardLayout", "fcitx"];
        const moved = ["media", "username", "keyboardLayout", "fcitx"];
        compare(LockIslands.storedOrder(moved, stored, LockIslands.LEFT_DEFAULT),
                ["media", "username", "keyboardLayout", "fcitx", "someFutureItem"]);
    }

    function test_a_write_back_with_no_unknowns_is_the_moved_order_itself() {
        const moved = ["sleep", "battery", "power", "reboot"];
        compare(LockIslands.storedOrder(moved,
                                        ["battery", "sleep", "power", "reboot"],
                                        LockIslands.RIGHT_DEFAULT),
                moved);
    }
}
