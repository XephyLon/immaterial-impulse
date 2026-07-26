.pragma library

// Pure, dependency-free iCalendar (RFC 5545) parser.
//
// Scope for v1: extracts VEVENT blocks and their DTSTART / DTEND / SUMMARY.
// Recurrence (RRULE / RDATE / EXDATE) is intentionally ignored - a recurring
// event surfaces only on its first occurrence. Named time zones (DTSTART with a
// TZID parameter) are treated as floating local time; only a trailing "Z"
// (UTC designator) is honoured. See parseIcs' return shape below.

// RFC 5545 line folding: a CRLF followed by a single space or tab continues the
// previous logical line. Unfold before parsing anything else.
function unfoldLines(text) {
    const rawLines = String(text).split(/\r\n|\r|\n/);
    const lines = [];
    for (let i = 0; i < rawLines.length; i++) {
        const line = rawLines[i];
        if (lines.length > 0 && line.length > 0 && (line[0] === " " || line[0] === "\t")) {
            lines[lines.length - 1] += line.slice(1);
        } else {
            lines.push(line);
        }
    }
    return lines;
}

// Split a content line "NAME;PARAM=VALUE:value" into its parts. Only the first
// colon separates name/params from the value, so URLs etc. in the value survive.
function parseContentLine(line) {
    const colonIdx = line.indexOf(":");
    if (colonIdx === -1)
        return null;
    const nameAndParams = line.slice(0, colonIdx);
    const value = line.slice(colonIdx + 1);
    const parts = nameAndParams.split(";");
    const name = parts[0].toUpperCase();
    const params = {};
    for (let i = 1; i < parts.length; i++) {
        const eq = parts[i].indexOf("=");
        if (eq === -1)
            continue;
        params[parts[i].slice(0, eq).toUpperCase()] = parts[i].slice(eq + 1);
    }
    return { name: name, params: params, value: value };
}

// Parse an iCalendar date/date-time value into a JS Date.
// Handles "YYYYMMDD" (all-day, VALUE=DATE), "YYYYMMDDTHHMMSS" (local/floating)
// and "YYYYMMDDTHHMMSSZ" (UTC). Returns { date, allDay } or null if malformed.
function parseIcsDate(value, params) {
    if (!value)
        return null;
    const m = String(value).match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?/);
    if (!m)
        return null;
    const year = parseInt(m[1], 10);
    const month = parseInt(m[2], 10); // 1-12
    const day = parseInt(m[3], 10);
    const dateOnly = (params && params.VALUE === "DATE") || m[4] === undefined;
    if (dateOnly)
        return { date: new Date(year, month - 1, day), allDay: true };
    const hh = parseInt(m[4], 10);
    const mm = parseInt(m[5], 10);
    const ss = parseInt(m[6], 10);
    if (m[7] === "Z")
        return { date: new Date(Date.UTC(year, month - 1, day, hh, mm, ss)), allDay: false };
    // Floating / TZID time: interpret in the local zone for v1.
    return { date: new Date(year, month - 1, day, hh, mm, ss), allDay: false };
}

// Undo RFC 5545 TEXT escaping for SUMMARY et al.
function unescapeText(value) {
    return String(value)
        .replace(/\\n/gi, "\n")
        .replace(/\\,/g, ",")
        .replace(/\\;/g, ";")
        .replace(/\\\\/g, "\\");
}

// parseIcs(text) -> [{ summary, start: Date, end: Date|null, allDay: bool,
//                      year, month (1-12), day }]
// Pure and defensive: never throws on malformed input, events without a valid
// DTSTART are dropped, and the year/month/day fields are the start's local-date
// components for O(1) day-indicator lookups.
function parseIcs(text) {
    if (!text)
        return [];
    const lines = unfoldLines(text);
    const events = [];
    let cur = null;
    for (let i = 0; i < lines.length; i++) {
        const parsed = parseContentLine(lines[i]);
        if (!parsed)
            continue;
        if (parsed.name === "BEGIN" && parsed.value.toUpperCase() === "VEVENT") {
            cur = { summary: "", start: null, end: null };
            continue;
        }
        if (parsed.name === "END" && parsed.value.toUpperCase() === "VEVENT") {
            if (cur && cur.start) {
                const s = cur.start;
                events.push({
                    summary: cur.summary,
                    start: s.date,
                    end: cur.end ? cur.end.date : null,
                    allDay: s.allDay,
                    year: s.date.getFullYear(),
                    month: s.date.getMonth() + 1,
                    day: s.date.getDate()
                });
            }
            cur = null;
            continue;
        }
        if (!cur)
            continue;
        switch (parsed.name) {
        case "DTSTART":
            cur.start = parseIcsDate(parsed.value, parsed.params);
            break;
        case "DTEND":
            cur.end = parseIcsDate(parsed.value, parsed.params);
            break;
        case "SUMMARY":
            cur.summary = unescapeText(parsed.value);
            break;
        }
    }
    return events;
}
