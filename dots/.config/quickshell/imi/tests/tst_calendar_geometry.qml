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

    function widthOf(span) { return span === "1x1" ? 132 : 276; }
    function heightOf(span) { return span === "2x2" ? 228 : 108; }

    function surface(span) {
        return Geometry.monthSurfaceRect(span, widthOf(span), heightOf(span), 1,
            pillLabel, cardRadius);
    }
    function label(span) {
        return Geometry.monthLabelRect(span, widthOf(span), heightOf(span), 1);
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

    function test_the_month_name_travels_between_the_two_wide_spans() {
        compare(label("1x1"), null, "the 1x1 band says the month in short form");
        const inPill = label("2x1");
        const asTitle = label("2x2");
        verify(inPill.x > asTitle.x,
               "out of the pill's padding and back onto the card inset");
        verify(asTitle.size > inPill.size, "and a step larger as a title");
        compare(asTitle.x, 12);
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

    function test_the_month_steppers_exist_only_at_2x2_and_in_order() {
        compare(nav(0, "1x1"), null);
        compare(nav(0, "2x1"), null);
        const prev = nav(0, "2x2");
        const next = nav(1, "2x2");
        verify(prev.x < next.x, "previous, then next");
        compare(next.x + next.width, 276 - 12, "flush with the card inset");
        verify(prev.x + prev.width < next.x, "and they do not overlap");
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
            compare(day(i, "1x1") !== null, i === 20, "cell " + i + " at 1x1");
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

    function test_today_grows_into_the_hero_and_loses_its_highlight() {
        const inGrid = day(20, "2x2");
        const hero = day(20, "1x1");
        verify(hero.size > inGrid.size * 4, "a caption becomes the whole card");
        compare(inGrid.pill, 28, "a highlight in the grid");
        compare(hero.pill, 0,
                "and no highlight at 1x1 - a fill of zero size has finished leaving");
        compare(hero.x, 0);
        compare(hero.width, 132, "centred across the whole card");
        compare(hero.y + hero.height, 108, "under the band, down to the card edge");
    }
}
