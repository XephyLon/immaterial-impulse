.pragma library

// Google's REST shapes, turned into the shell's - pure, so
// tests/tst_google_api.qml pins them without a network. The services build
// the URLs here too, so an id with a slash or a space cannot break a path.

var API_BASE_DEFAULT = "https://www.googleapis.com";

function apiBase(env) {
    var b = env && env.length ? env : API_BASE_DEFAULT;
    return b.replace(/\/+$/, "");
}

// ---- Calendar ----

function calendarListUrl(base) {
    return apiBase(base) + "/calendar/v3/users/me/calendarList?minAccessRole=reader&showHidden=false";
}

// `singleEvents` expands recurrences server-side; the shell's ICS parser does
// not do recurrence, so this is what makes Google events match the sidebar.
function eventsUrl(base, calendarId, timeMin, timeMax) {
    return apiBase(base) + "/calendar/v3/calendars/" + encodeURIComponent(calendarId)
        + "/events?singleEvents=true&orderBy=startTime&maxResults=250"
        + "&timeMin=" + encodeURIComponent(timeMin) + "&timeMax=" + encodeURIComponent(timeMax);
}

// The calendars worth fetching: selected in Google's UI, not hidden.
function parseCalendarList(json) {
    var out = [];
    var items = (json && json.items) || [];
    for (var i = 0; i < items.length; i++) {
        var c = items[i];
        if (!c || !c.id || c.selected === false || c.hidden === true) continue;
        out.push({ id: String(c.id), name: String(c.summaryOverride || c.summary || c.id),
                   primary: c.primary === true, color: String(c.backgroundColor || "") });
    }
    return out;
}

// Year/month/day in local time, the way ics_parser.js stamps its events.
function localParts(date) {
    return { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate() };
}

// One events.list page → the IcsCalendar event shape
// ({ summary, start, end, allDay, year, month, day } plus `calendar` and `uid`).
function parseEvents(json, calendarName) {
    var out = [];
    var items = (json && json.items) || [];
    for (var i = 0; i < items.length; i++) {
        var e = items[i];
        if (!e || e.status === "cancelled" || !e.start) continue;
        var allDay = !!e.start.date;
        var start = allDay ? new Date(e.start.date + "T00:00:00") : new Date(e.start.dateTime);
        if (isNaN(start.getTime())) continue;
        var end = null;
        if (e.end) {
            end = allDay && e.end.date ? new Date(e.end.date + "T00:00:00") : new Date(e.end.dateTime || e.end.date);
            if (isNaN(end.getTime())) end = null;
        }
        var p = localParts(start);
        out.push({ summary: String(e.summary || ""), start: start, end: end, allDay: allDay,
                   year: p.year, month: p.month, day: p.day,
                   calendar: String(calendarName || ""), uid: String(e.id || "") });
    }
    return out;
}

// ---- Tasks ----

function taskListsUrl(base) {
    return apiBase(base) + "/tasks/v1/users/@me/lists?maxResults=100";
}

function tasksUrl(base, listId) {
    return apiBase(base) + "/tasks/v1/lists/" + encodeURIComponent(listId)
        + "/tasks?showCompleted=false&showHidden=false&maxResults=100";
}

function tasksCollectionUrl(base, listId) {
    return apiBase(base) + "/tasks/v1/lists/" + encodeURIComponent(listId) + "/tasks";
}

function taskUrl(base, listId, taskId) {
    return apiBase(base) + "/tasks/v1/lists/" + encodeURIComponent(listId) + "/tasks/" + encodeURIComponent(taskId);
}

function parseTaskLists(json) {
    var out = [];
    var items = (json && json.items) || [];
    for (var i = 0; i < items.length; i++) {
        var l = items[i];
        if (l && l.id) out.push({ id: String(l.id), title: String(l.title || "") });
    }
    return out;
}

// Open tasks in the list's own order (Google sorts by `position`).
function parseTasks(json, listId) {
    var out = [];
    var items = (json && json.items) || [];
    for (var i = 0; i < items.length; i++) {
        var t = items[i];
        if (!t || !t.id || t.deleted) continue;
        out.push({ id: String(t.id), listId: String(listId || ""), content: String(t.title || ""),
                   done: t.status === "completed", due: t.due ? String(t.due).slice(0, 10) : "",
                   notes: String(t.notes || ""), position: String(t.position || "") });
    }
    out.sort(function (a, b) { return a.position < b.position ? -1 : a.position > b.position ? 1 : 0; });
    return out;
}

// ---- Gmail ----

function inboxLabelUrl(base) {
    return apiBase(base) + "/gmail/v1/users/me/labels/INBOX";
}

function parseUnread(json) {
    var n = json && json.messagesUnread;
    n = Number(n);
    return isNaN(n) || n < 0 ? 0 : Math.floor(n);
}

// ---- errors ----

// Google's error envelope, or nothing.
function errorOf(json) {
    if (!json || !json.error) return "";
    var e = json.error;
    if (typeof e === "string") return e;
    return String(e.message || e.status || e.code || "error");
}
