.pragma library

// `warp-cli status`, read into the toggle's state. Kept out of the toggle
// so the reading is testable without warp-cli: the CLI's wording is the
// contract here ("Status update: Connected", "Status update: Disconnected",
// "Unable to connect to the CloudflareWARP daemon" / registration missing).
//
// Returns { available, state } with state one of
// "connected" | "disconnected" | "unregistered" | "unknown".
// available: the CLI answered at all (any output).
function parse(text) {
    var s = String(text === undefined || text === null ? "" : text);
    if (s.trim().length === 0) return { available: false, state: "unknown" };
    if (s.indexOf("Unable") !== -1) return { available: true, state: "unregistered" };
    if (s.indexOf("Connected") !== -1 && s.indexOf("Disconnected") === -1) return { available: true, state: "connected" };
    if (s.indexOf("Disconnected") !== -1) return { available: true, state: "disconnected" };
    return { available: true, state: "unknown" };
}
