.pragma library

// The network-speed widget's logic, out of its visual root (the first
// extraction of docs/proposals/headless-widgets.md's backlog): parse
// /proc/net/dev, advance a sample state into rates, format a rate. Pure
// functions over their arguments; NetworkSpeed.qml owns the FileView, the
// timer and the state object.

// Sum of received and transmitted bytes across every interface but the
// loopback. A malformed line is skipped, never a NaN in the total.
function parseProcNetDev(contents) {
    var rx = 0, tx = 0;
    var lines = String(contents || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var sep = line.indexOf(":");
        if (sep < 0) continue;
        var name = line.slice(0, sep).trim();
        if (!name || name === "lo") continue;
        var fields = line.slice(sep + 1).trim().split(/\s+/);
        if (fields.length < 9) continue;
        var r = Number(fields[0]), t = Number(fields[8]);
        if (!isFinite(r) || !isFinite(t)) continue;
        rx += r;
        tx += t;
    }
    return { rx: rx, tx: tx };
}

// The state the widget keeps between samples.
function initialState() {
    return { previousRx: -1, previousTx: -1, previousTime: 0,
             downloadBytesPerSecond: 0, uploadBytesPerSecond: 0,
             downloadedBytes: 0, uploadedBytes: 0 };
}

// A new sample: rates from the deltas over the elapsed time, totals
// accumulated. A counter that went backwards (interface reset) counts as no
// traffic rather than a negative burst; the first sample sets a baseline
// and reports nothing.
function advance(state, rx, tx, now) {
    var next = {
        previousRx: rx, previousTx: tx, previousTime: now,
        downloadBytesPerSecond: state.downloadBytesPerSecond,
        uploadBytesPerSecond: state.uploadBytesPerSecond,
        downloadedBytes: state.downloadedBytes, uploadedBytes: state.uploadedBytes
    };
    if (state.previousTime > 0 && now > state.previousTime) {
        var elapsedMs = now - state.previousTime;
        var rxDelta = rx >= state.previousRx ? rx - state.previousRx : 0;
        var txDelta = tx >= state.previousTx ? tx - state.previousTx : 0;
        next.downloadBytesPerSecond = rxDelta * 1000 / elapsedMs;
        next.uploadBytesPerSecond = txDelta * 1000 / elapsedMs;
        next.downloadedBytes = state.downloadedBytes + rxDelta;
        next.uploadedBytes = state.uploadedBytes + txDelta;
    }
    return next;
}

// "1.5 MB/s" or, compact, "1.5M". One decimal below 100 in any unit above
// bytes, none otherwise.
function formatRate(rate, compact) {
    var units = compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"];
    var value = Math.max(0, Number(rate) || 0);
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
        value /= 1024;
        unitIndex++;
    }
    var precision = unitIndex > 0 && value < 100 ? 1 : 0;
    return value.toFixed(precision) + (compact ? "" : " ") + units[unitIndex];
}
