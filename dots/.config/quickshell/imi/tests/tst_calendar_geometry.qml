import QtTest
import "../modules/common/plugins/bundled/calendar/calendar_geometry.js" as Geometry

// The calendar widget's shared-element geometry: where each element sits at
// each of the three spans, and which spans have no home for it.
//
// Spans at scale 1: 1x1 = 132x108, 2x1 = 276x108, 2x2 = 276x228.
// The card's radius is 30 at that scale (WidgetCard's own default).
TestCase {
    name: "CalendarGeometryTest"

    readonly property real cardRadius: 30
    readonly property real pillLabel: 84   // a plausible "August 2026"

    function widthOf(span) { return span === "1x1" ? 132 : span === "3x2" ? 420 : 276; }
    function heightOf(span) { return span === "2x2" || span === "3x2" ? 228 : 108; }

    function surface(span) {
        return Geometry.monthSurfaceRect(span, widthOf(span), heightOf(span), 1,
            pillLabel, cardRadius);
    }
    function label(span) {
        return Geometry.monthTextRect(span, widthOf(span), heightOf(span), 1);
    }
    function hero(span) {
        return Geometry.heroDayRect(span, widthOf(span), heightOf(span), 1, 2, 20);
    }
    function nav(index, span) {
        return Geometry.navButtonRect(index, span, widthOf(span), heightOf(span), 1);
    }
    function weekday(index, span) {
        return Geometry.weekdayHeaderRect(index, span, widthOf(span), heightOf(span), 1);
    }
    function grid(span) {
        return Geometry.dayGridSurfaceRect(span, widthOf(span), heightOf(span), 1, cardRadius);
    }
    // Today is the 16th of a month starting on a Saturday, so it is cell 20 -
    // row 2, column 6 - which is the case the probe renders.
    function day(index, span) {
        return Geometry.dayCellRect(index, span, widthOf(span), heightOf(span), 1, 2, 20);
    }

    function test_the_month_surface_is_a_band_a_pill_and_then_nothing() {
        const band = surface("1x1");
        compare(band.x, 0, "full bleed");
        compare(band.width, 132);
        compare(band.radiusTop, cardRadius, "its top corners are the card's own");
        compare(band.radiusBottom, 0, "and its bottom edge is square");

        const pill = surface("2x1");
        compare(pill.x, 12, "on the card inset");
        compare(pill.radiusTop, pill.height / 2, "a stadium");
        compare(pill.radiusTop, pill.radiusBottom);
        compare(pill.width, pillLabel + 24, "it hugs its label");

        compare(surface("2x2"), null,
                "the 2x2 month is a plain title, so the surface fades");
    }

    function test_the_month_text_is_one_element_with_a_home_at_every_span() {
        // The maintainer's rule: never hidden and replaced by a same-purpose
        // twin. One element, four homes, and its FORM follows the span.
        compare(label("1x1").form, "short", "AUG in the band");
        compare(label("2x1").form, "long", "August 2026 in the pill");
        compare(label("2x2").form, "long", "August 2026 as the title");
        compare(label("3x2").form, "hero", "AUGUST atop the hero column");
        const inPill = label("2x1");
        const asTitle = label("2x2");
        verify(inPill.x > asTitle.x,
               "out of the pill's padding and back onto the card inset");
        verify(asTitle.size > inPill.size, "and a step larger as a title");
        compare(asTitle.x, 12);
        const inHero = label("3x2");
        compare(inHero.x, 16, "on the hero column's own inset");
        const weekdayText = Geometry.weekdayTextRect("3x2", 420, 228, 1);
        verify(inHero.y + inHero.height <= weekdayText.y,
               "month above the weekday");
        compare(Geometry.weekdayTextRect("2x2", 276, 228, 1), null,
                "the weekday name fades at the spans with no home for it");
    }

    function test_the_month_name_starts_inside_its_pill() {
        const pill = surface("2x1");
        const inPill = label("2x1");
        verify(inPill.x > pill.x, "the label is inset in the pill");
        verify(inPill.x + pillLabel <= pill.x + pill.width + 0.01,
               "and the pill is wide enough for it");
        compare(inPill.y, pill.y, "one line");
        compare(inPill.height, pill.height);
    }

    function test_the_month_steppers_live_at_both_whole_month_spans() {
        compare(nav(0, "1x1"), null, "the small spans are about today");
        compare(nav(0, "2x1"), null);
        const prev = nav(0, "2x2");
        const next = nav(1, "2x2");
        verify(prev.x < next.x, "previous, then next");
        compare(next.x + next.width, 276 - 12, "flush with the card inset");
        verify(prev.x + prev.width < next.x, "and they do not overlap");
        // The SAME pair travels to the foot of the hero column at 3x2.
        const heroPrev = nav(0, "3x2");
        const heroNext = nav(1, "3x2");
        compare(heroPrev.x, 16, "on the hero column's own inset");
        verify(heroPrev.x < heroNext.x);
        compare(heroPrev.y + heroPrev.height, 228 - 12, "at the column's foot");
        verify(heroNext.x + heroNext.width <= Geometry.dayGridSurfaceRect(
            "3x2", 420, 228, 1, cardRadius).x + 0.01, "clear of the grid surface");
        const dayRect = hero("3x2");
        verify(dayRect.y + dayRect.height <= heroPrev.y + 0.01,
               "the hero date stops above the steppers");
    }

    function test_the_weekday_letters_divide_their_own_content_width() {
        compare(weekday(0, "1x1"), null, "no strip on the 1x1 card");
        const short0 = weekday(0, "2x1");
        const short6 = weekday(6, "2x1");
        compare(short0.x, 12);
        compare(short0.x + 7 * short0.width, 276 - 12,
                "seven columns across the card's content width");
        compare(short6.x + short6.width, 276 - 12);

        // 2x2 divides the day-grid SURFACE's width, inset one step further, so
        // the letters sit over the columns inside it rather than on a pitch of
        // their own - which is what the destroyed layout's dayGridInset was for.
        const wide0 = weekday(0, "2x2");
        verify(wide0.x > short0.x);
        verify(wide0.width < short0.width);
        compare(wide0.x + 7 * wide0.width, 276 - 16);
    }

    function test_the_day_grid_surface_exists_only_at_2x2() {
        compare(grid("1x1"), null);
        compare(grid("2x1"), null);
        const surfaceRect = grid("2x2");
        compare(surfaceRect.x, 12);
        compare(surfaceRect.width, 252);
        compare(surfaceRect.y + surfaceRect.height, 228 - 12,
                "down to the card inset");
        compare(surfaceRect.radius, cardRadius - 12,
                "concentric with the card's own corners");
    }

    function test_every_cell_has_a_home_at_2x2() {
        for (let i = 0; i < Geometry.CELLS; i++)
            verify(day(i, "2x2") !== null, "cell " + i);
        compare(day(-1, "2x2"), null);
        compare(day(Geometry.CELLS, "2x2"), null);
    }

    function test_the_2x1_keeps_one_week_and_the_1x1_keeps_one_day() {
        for (let i = 0; i < Geometry.CELLS; i++) {
            const inWeek = Math.floor(i / Geometry.COLUMNS) === 2;
            compare(day(i, "2x1") !== null, inWeek,
                    "cell " + i + " at 2x1 - null is a fade, never a morph");
            compare(day(i, "1x1"), null,
                    "cell " + i + " at 1x1: the hero date element is the "
                    + "card there, and a cell that also carried it would be "
                    + "a same-purpose twin");
        }
    }

    function test_the_surviving_week_travels_up_into_one_row() {
        const rows = [];
        for (let column = 0; column < Geometry.COLUMNS; column++) {
            const inGrid = day(14 + column, "2x2");
            // Not `short`: it is a future-reserved word that this Qt's QML
            // parser accepts and the CI runner's rejects, with an error that
            // names the file and not the line.
            const inRow = day(14 + column, "2x1");
            rows.push(inRow.y);
            verify(inRow.y < inGrid.y, "column " + column + " travels up");
            compare(inRow.width, inGrid.width, "and keeps its size");
        }
        for (const y of rows)
            compare(y, rows[0], "the seven land on one line");
    }

    function test_the_grid_rows_fit_inside_the_surface_they_are_drawn_on() {
        const surfaceRect = grid("2x2");
        const first = day(0, "2x2");
        const last = day(Geometry.CELLS - 1, "2x2");
        verify(first.y >= surfaceRect.y, "the first row is on the surface");
        verify(last.y + last.height <= surfaceRect.y + surfaceRect.height + 0.01,
               "and so is the last");
        // Centred: the slack above the first row equals the slack below the last.
        fuzzyCompare(first.y - surfaceRect.y,
                     surfaceRect.y + surfaceRect.height - (last.y + last.height), 0.01);
    }

    function test_the_cells_stay_inside_the_card_at_both_wide_spans() {
        for (const span of ["2x1", "2x2"]) {
            for (let column = 0; column < Geometry.COLUMNS; column++) {
                const cell = day(14 + column, span);
                verify(cell.x >= 12, span + " column " + column + " off the left edge");
                verify(cell.x + cell.width <= widthOf(span) - 12 + 0.01,
                       span + " column " + column + " off the right edge");
            }
        }
    }

    function test_the_3x2_surface_hugs_the_right_edge_at_the_2x2s_width() {
        const wide = grid("3x2");
        compare(wide.width, 252, "the 2x2's surface, moved");
        compare(wide.x + wide.width, 420 - 12, "flush with the card inset");
        compare(wide.y, 12);
        compare(wide.y + wide.height, 228 - 12);
        compare(wide.radius, cardRadius - 12);
    }

    function test_the_3x2_strip_and_cells_live_inside_the_surface() {
        const surfaceRect = grid("3x2");
        const strip0 = weekday(0, "3x2");
        verify(strip0.x >= surfaceRect.x, "the strip moved onto the surface");
        compare(strip0.x, surfaceRect.x + 4);
        for (let i = 0; i < Geometry.CELLS; i++) {
            const cell = day(i, "3x2");
            verify(cell !== null, "every cell has a home at 3x2");
            verify(cell.x >= surfaceRect.x, "cell " + i + " on the surface");
            verify(cell.x + cell.width <= surfaceRect.x + surfaceRect.width + 0.01);
            verify(cell.y >= strip0.y + strip0.height, "under the strip");
            verify(cell.y + cell.height <= surfaceRect.y + surfaceRect.height + 0.01);
        }
    }

    function test_the_3x2_hero_column_owns_the_left_and_only_the_left() {
        const surfaceRect = grid("3x2");
        const chip = Geometry.heroRect("chip", "3x2", 420, 228, 1);
        verify(chip !== null);
        verify(chip.x + chip.width <= surfaceRect.x + 0.01,
               "the chip stays clear of the grid surface");
        compare(Geometry.heroRect("chip", "2x2", 276, 228, 1), null,
                "the chip exists only at 3x2 - it has no twin anywhere");
        const month = label("3x2");
        const weekdayRow = Geometry.weekdayTextRect("3x2", 420, 228, 1);
        const dayRect = hero("3x2");
        verify(month.y < weekdayRow.y && weekdayRow.y < dayRect.y,
               "month, weekday, date, top to bottom");
        verify(dayRect.size > month.size * 3, "the date is the hero");
        for (const slot of [month, weekdayRow, dayRect])
            verify(slot.x + slot.width <= surfaceRect.x + 0.01,
                   "the hero column stays clear of the grid surface");
        compare(surface("3x2"), null, "no band and no pill");
    }

    function test_the_hero_date_is_one_element_from_1x1_to_3x2() {
        const at1x1 = hero("1x1");
        verify(at1x1.present);
        compare(at1x1.x, 0);
        compare(at1x1.width, 132, "centred across the whole card");
        compare(at1x1.y + at1x1.height, 108, "under the band, down to the card edge");
        const at3x2 = hero("3x2");
        verify(at3x2.present);
        compare(at3x2.size, at1x1.size, "the same hero, the same size");
        verify(at3x2.x + at3x2.width <= Geometry.dayGridSurfaceRect(
            "3x2", 420, 228, 1, cardRadius).x + 0.01, "left of the grid surface");
    }

    function test_the_hero_fades_over_todays_own_cell_between_its_homes() {
        // Leaving 1x1 for 2x2 must still read as the big date shrinking into
        // its circle - so the hero's fade-home IS today's cell, not a corner.
        const at2x2 = hero("2x2");
        const cell = day(20, "2x2");
        verify(!at2x2.present, "no hero at 2x2 - it fades");
        compare(at2x2.x, cell.x);
        compare(at2x2.y, cell.y);
        compare(at2x2.size, cell.size, "shrunk to the cell's own caption size");
        const at2x1 = hero("2x1");
        verify(!at2x1.present);
        compare(at2x1.y, day(20, "2x1").y, "on the week strip's row at 2x1");
        // A shifted month with today nowhere on the card fades dead centre.
        const nowhere = Geometry.heroDayRect("2x2", 276, 228, 1, 2, -1);
        verify(!nowhere.present);
        compare(nowhere.width, 0);
    }
}
