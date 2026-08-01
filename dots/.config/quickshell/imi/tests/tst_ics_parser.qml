import QtQuick
import QtTest
import "../services/ics_parser.js" as Ics

TestCase {
    name: "IcsParserTest"

    function test_timedEventUtc() {
        const events = Ics.parseIcs(
            "BEGIN:VCALENDAR\r\n" +
            "BEGIN:VEVENT\r\n" +
            "DTSTART:20260726T133000Z\r\n" +
            "DTEND:20260726T143000Z\r\n" +
            "SUMMARY:Standup\r\n" +
            "END:VEVENT\r\n" +
            "END:VCALENDAR\r\n");
        compare(events.length, 1);
        compare(events[0].summary, "Standup");
        compare(events[0].allDay, false);
        const expected = new Date(Date.UTC(2026, 6, 26, 13, 30, 0));
        compare(events[0].start.getTime(), expected.getTime());
        verify(events[0].end !== null);
    }

    function test_allDayEvent() {
        const events = Ics.parseIcs(
            "BEGIN:VEVENT\n" +
            "DTSTART;VALUE=DATE:20260101\n" +
            "SUMMARY:New Year\n" +
            "END:VEVENT\n");
        compare(events.length, 1);
        compare(events[0].allDay, true);
        compare(events[0].year, 2026);
        compare(events[0].month, 1);
        compare(events[0].day, 1);
    }

    function test_lineFolding() {
        // SUMMARY continues on a folded line beginning with a space.
        const events = Ics.parseIcs(
            "BEGIN:VEVENT\r\n" +
            "DTSTART:20260726T090000Z\r\n" +
            "SUMMARY:Very long meeting\r\n" +
            "  title continued\r\n" +
            "END:VEVENT\r\n");
        compare(events.length, 1);
        compare(events[0].summary, "Very long meeting title continued");
    }

    function test_multipleVEvents() {
        const events = Ics.parseIcs(
            "BEGIN:VEVENT\n" +
            "DTSTART:20260726T090000Z\n" +
            "SUMMARY:First\n" +
            "END:VEVENT\n" +
            "BEGIN:VEVENT\n" +
            "DTSTART;VALUE=DATE:20260727\n" +
            "SUMMARY:Second\n" +
            "END:VEVENT\n");
        compare(events.length, 2);
        compare(events[0].summary, "First");
        compare(events[1].summary, "Second");
        compare(events[1].allDay, true);
    }

    function test_escapedText() {
        const events = Ics.parseIcs(
            "BEGIN:VEVENT\n" +
            "DTSTART:20260726T090000Z\n" +
            "SUMMARY:Lunch\\, then\\; work\n" +
            "END:VEVENT\n");
        compare(events[0].summary, "Lunch, then; work");
    }

    function test_malformedInput() {
        // No VEVENTs, empty, garbage, and an event missing DTSTART -> no crash, no bogus events.
        compare(Ics.parseIcs("").length, 0);
        compare(Ics.parseIcs("not a calendar at all").length, 0);
        compare(Ics.parseIcs(
            "BEGIN:VEVENT\n" +
            "SUMMARY:No start date\n" +
            "END:VEVENT\n").length, 0);
    }
}
