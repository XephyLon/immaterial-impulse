.pragma library

// What the Updates service reports after an upgrade run, decided from the
// count re-read afterwards. Kept as data so tests/tst_updates_outcome.qml can
// drive it without the service (whose imports need the whole shell):
//   count 0 -> "up to date", no urgency flag (the daemon's default);
//   otherwise -> "cancelled, N pending", `-u normal`.
// Both are the bar widget's old notify-send commands byte for byte.
function outcome(countAfter) {
    return countAfter === 0
        ? { upToDate: true, urgency: "" }
        : { upToDate: false, urgency: "normal" };
}

// The notify-send argv for a decided outcome; `summary` and `body` are the
// translated strings the caller picked from `outcome().upToDate`.
function command(countAfter, summary, body) {
    var o = outcome(countAfter);
    var argv = ["notify-send", summary, body, "-a", "Shell"];
    return o.urgency.length > 0 ? argv.concat(["-u", o.urgency]) : argv;
}
