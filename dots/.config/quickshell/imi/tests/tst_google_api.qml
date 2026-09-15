import QtQuick
import QtTest
import "../services/google_api.js" as G

// Google's REST shapes into the shell's, without a network.
TestCase {
    name: "GoogleApi"

    function test_urls_escape_ids_and_take_a_base() {
        compare(G.apiBase(""), "https://www.googleapis.com");
        compare(G.apiBase("http://127.0.0.1:8088/"), "http://127.0.0.1:8088");
        const u = G.eventsUrl("http://x", "a b@group.calendar.google.com", "2026-09-15T00:00:00Z", "2026-09-29T00:00:00Z");
        verify(u.indexOf("/calendar/v3/calendars/a%20b%40group.calendar.google.com/events?") !== -1, u);
        verify(u.indexOf("singleEvents=true") !== -1, "recurrences expand server-side");
        verify(u.indexOf("timeMin=2026-09-15T00%3A00%3A00Z") !== -1, u);
        compare(G.taskUrl("http://x", "l/1", "t 2"), "http://x/tasks/v1/lists/l%2F1/tasks/t%202");
        verify(G.tasksUrl("http://x", "l").indexOf("showCompleted=false") !== -1);
    }

    function test_calendar_list_keeps_selected_visible_calendars() {
        const list = G.parseCalendarList({ items: [
            { id: "me@x", summary: "Me", primary: true, selected: true, backgroundColor: "#fff" },
            { id: "hidden", summary: "H", hidden: true },
            { id: "unselected", summary: "U", selected: false },
            { id: "team", summaryOverride: "Team (mine)", summary: "Team" },
        ] });
        compare(list.map(c => c.id), ["me@x", "team"]);
        compare(list[1].name, "Team (mine)");
        verify(list[0].primary);
        compare(G.parseCalendarList(null), []);
    }

    function test_events_become_ics_shaped_with_local_day_parts() {
        const ev = G.parseEvents({ items: [
            { id: "1", summary: "Standup", start: { dateTime: "2026-09-16T09:30:00+02:00" }, end: { dateTime: "2026-09-16T09:45:00+02:00" } },
            { id: "2", summary: "Holiday", start: { date: "2026-09-20" }, end: { date: "2026-09-21" } },
            { id: "3", summary: "Gone", status: "cancelled", start: { date: "2026-09-20" } },
            { id: "4", summary: "Bad", start: { dateTime: "not a date" } },
        ] }, "Work");
        compare(ev.length, 2);
        compare(ev[0].summary, "Standup");
        verify(!ev[0].allDay);
        compare(ev[0].calendar, "Work");
        compare(ev[0].uid, "1");
        verify(ev[0].end instanceof Date);
        compare(ev[0].year, ev[0].start.getFullYear());
        compare(ev[0].month, ev[0].start.getMonth() + 1);
        compare(ev[0].day, ev[0].start.getDate());
        verify(ev[1].allDay);
        compare([ev[1].year, ev[1].month, ev[1].day], [2026, 9, 20], "an all-day date is that calendar day, not the UTC midnight before it");
    }

    function test_tasks_are_open_ones_in_position_order() {
        compare(G.parseTaskLists({ items: [{ id: "L1", title: "My Tasks" }, { title: "no id" }] }), [{ id: "L1", title: "My Tasks" }]);
        const tasks = G.parseTasks({ items: [
            { id: "b", title: "Second", status: "needsAction", position: "00000000000000000002", due: "2026-09-20T00:00:00.000Z" },
            { id: "a", title: "First", status: "needsAction", position: "00000000000000000001" },
            { id: "z", title: "Deleted", deleted: true, position: "0" },
        ] }, "L1");
        compare(tasks.map(t => t.content), ["First", "Second"]);
        compare(tasks[1].due, "2026-09-20");
        compare(tasks[0].listId, "L1");
        verify(!tasks[0].done);
    }

    function test_unread_and_errors() {
        compare(G.parseUnread({ messagesUnread: 7 }), 7);
        compare(G.parseUnread({ messagesUnread: "3" }), 3);
        compare(G.parseUnread({}), 0);
        compare(G.parseUnread(null), 0);
        compare(G.errorOf({ error: { code: 401, message: "Invalid Credentials" } }), "Invalid Credentials");
        compare(G.errorOf({ items: [] }), "");
    }
}
