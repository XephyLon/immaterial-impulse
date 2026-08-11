import QtTest
import "../modules/common/plugins/bundled/nandoroid-media/cookie_layout.js" as CookieLayout

// The 2x2 media tile is the cookie clock's shape with next/previous where the
// day and month badges are, so the arithmetic that places them is the clock's
// arithmetic and is pinned here.
//
// Nothing about the rendered tile is reachable from qmltestrunner - it cannot
// construct Quickshell types and the software scene graph draws no Canvas - so
// the placement is extracted precisely so this much *is* checkable. What the
// numbers have to hold up: the square frame never leaves the tile (a clipped
// cookie), and a badge overlaps the cookie's edge rather than floating beside
// it (three unrelated objects instead of one).
TestCase {
    name: "MediaCookieLayoutTest"

    readonly property real tileWidth: 276
    readonly property real tileHeight: 228

    function test_the_frame_is_square_and_centred_in_a_tile_that_is_not() {
        const frame = CookieLayout.frame(tileWidth, tileHeight, 12);
        compare(frame.size, 204);
        // The tile is 48px wider than it is tall, so the leftover width is
        // split rather than handed to one side.
        compare(frame.x, 36);
        compare(frame.y, 12);
    }

    function test_the_frame_never_exceeds_the_tile_s_smaller_dimension() {
        // A frame wider than the tile is short, so the cookie would be clipped
        // top and bottom with nothing reporting it.
        for (const inset of [0, 6, 12, 16, 24]) {
            const frame = CookieLayout.frame(tileWidth, tileHeight, inset);
            verify(frame.size <= Math.min(tileWidth, tileHeight));
            verify(frame.x >= 0);
            verify(frame.y >= 0);
            compare(frame.size, Math.min(tileWidth, tileHeight) - inset * 2);
        }
    }

    function test_an_inset_larger_than_the_tile_yields_no_frame_rather_than_a_negative_one() {
        const frame = CookieLayout.frame(tileWidth, tileHeight, 200);
        compare(frame.size, 0);
        verify(frame.x >= 0);
        verify(frame.y >= 0);
    }

    function test_the_badge_keeps_the_clock_s_own_proportion() {
        // The clock's two numbers, reproduced: 230px square, 64px badge. If
        // this stops holding, the badge has stopped being the clock's badge.
        fuzzyCompare(CookieLayout.badgeSize(CookieLayout.CLOCK_FRAME),
            CookieLayout.CLOCK_BADGE, 0.0001);
    }

    function test_the_badge_scales_with_the_frame() {
        fuzzyCompare(CookieLayout.badgeSize(204), 204 * 64 / 230, 0.0001);
        compare(CookieLayout.badgeSize(0), 0);
    }

    function test_a_corner_badge_overlaps_the_cookie_s_edge() {
        // The relationship being copied from the clock. A badge whose centre
        // sat further out than the lobes reach would read as a separate pill
        // parked near the cookie.
        verify(CookieLayout.badgeOverlap(204) > 0);
        // The clock's own overlap, so a changed ratio shows up as a number
        // rather than as "still positive".
        fuzzyCompare(CookieLayout.badgeOverlap(CookieLayout.CLOCK_FRAME), 29.62, 0.01);
    }

    function test_the_overlap_scales_with_the_frame() {
        // Every term is linear in the frame size, so a smaller tile shrinks the
        // bite rather than losing it.
        fuzzyCompare(CookieLayout.badgeOverlap(204) * 2,
            CookieLayout.badgeOverlap(408), 0.0001);
    }
}
