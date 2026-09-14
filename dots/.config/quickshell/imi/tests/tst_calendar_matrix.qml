import QtQuick
import QtTest
import "../modules/common/plugins/bundled/calendar/calendar_matrix.js" as Cal

// The calendar widget's month grid, without the widget.
TestCase {
    name: "CalendarMatrix"

    function test_monday_first_padding_and_length() {
        // September 2026 starts on a Tuesday: one cell of August (31) first.
        const cells = Cal.monthMatrix(2026, 8, 42, null);
        compare(cells.length, 42);
        compare(cells[0].day, 31); verify(!cells[0].currentMonth);
        compare(cells[1].day, 1); verify(cells[1].currentMonth);
        compare(cells[30].day, 30); verify(cells[30].currentMonth);
        compare(cells[31].day, 1); verify(!cells[31].currentMonth, "October's head pads the tail");
    }

    function test_a_month_starting_on_monday_has_no_leading_pad() {
        // June 2026 starts on a Monday.
        const cells = Cal.monthMatrix(2026, 5, 42, null);
        compare(cells[0].day, 1); verify(cells[0].currentMonth);
    }

    function test_leap_february() {
        const cells = Cal.monthMatrix(2028, 1, 42, null).filter(c => c.currentMonth);
        compare(cells.length, 29);
        compare(Cal.monthMatrix(2027, 1, 42, null).filter(c => c.currentMonth).length, 28);
    }

    function test_today_is_flagged_only_in_its_own_month() {
        const today = new Date(2026, 8, 15);
        const sept = Cal.monthMatrix(2026, 8, 42, today);
        compare(sept.filter(c => c.isToday).length, 1);
        verify(sept.find(c => c.isToday).currentMonth && sept.find(c => c.isToday).day === 15);
        compare(Cal.monthMatrix(2026, 9, 42, today).filter(c => c.isToday).length, 0, "October shows a 15 that is not today");
        compare(Cal.monthMatrix(2026, 8, 42, null).filter(c => c.isToday).length, 0);
    }

    function test_viewing_date_shifts_whole_months_from_the_first() {
        const now = new Date(2026, 0, 31); // Jan 31: a naive month shift would land in March
        const next = Cal.viewingDate(now, 1);
        compare(next.getMonth(), 1); compare(next.getDate(), 1);
        compare(Cal.viewingDate(now, -1).getMonth(), 11);
        compare(Cal.viewingDate(now, -1).getFullYear(), 2025);
    }
}
