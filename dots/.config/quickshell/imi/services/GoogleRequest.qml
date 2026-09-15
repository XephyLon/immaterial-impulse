import QtQuick
import Quickshell.Io
import qs.services

/**
 * Authenticated calls to a Google API, one at a time: curl with
 * GoogleAccount's bearer token. The token, the method and the JSON body
 * travel to curl through a config document on stdin (`-K -`), never as
 * argv - argv is readable by every process on the machine.
 *
 * Calls queue behind one another (PhoneConnect's action queue shape): a
 * second `request()` while one is in flight waits its turn instead of
 * being dropped or re-pointing the one running. Each finishes with
 * (json, error, status, tag) - the tag is whatever the caller queued, so
 * a calendar's identity rides with its own request rather than sitting
 * on this object as mutable state.
 */
Process {
    id: req
    property var queue: []
    property var current: null
    readonly property bool busy: req.current !== null || req.queue.length > 0
    property int status: 0
    property var _parsed: null
    property string _error: ""
    signal finished(var json, string error, int status, var tag)

    // The one in flight; set by pump() before `running`.
    property string url: ""
    property string method: "GET"
    property string body: ""

    command: ["curl", "-sS", "-m", "20", "-K", "-", "-w", "\n%{http_code}", req.url]

    function escapeConfig(s) {
        return String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n");
    }

    function request(url, method, body, tag) {
        req.queue.push({ url: String(url), method: String(method ?? "GET"), body: String(body ?? ""), tag: tag ?? null });
        req.pump();
    }

    function clear() {
        req.queue = [];
    }

    // Never while the last process is still winding down: a `running = true`
    // on a Process that has not exited yet is a no-op, and the queued call
    // would sit there for ever.
    function pump() {
        if (req.current !== null || req.running || req.queue.length === 0) return;
        req.current = req.queue.shift();
        req.url = req.current.url;
        req.method = req.current.method;
        req.body = req.current.body;
        req.status = 0;
        req._parsed = null;
        req._error = "";
        // Re-open stdin for every run: it is closed after the config is
        // written, and a Process started with it disabled inherits the
        // shell's own stdin - curl then waits on that pipe for ever.
        req.stdinEnabled = true;
        req.running = true;
    }

    // Settled on exit, never on the stream's end: exit comes after stdout
    // closes, so by then the payload is parsed and the process can be
    // restarted for the next call.
    function settle() {
        const done = req.current;
        const parsed = req._parsed;
        const error = req._error.length > 0 ? req._error : (req.status === 0 ? "no answer" : "");
        req.current = null;
        if (done) req.finished(parsed, error, req.status, done.tag);
        req.pump();
    }

    onStarted: {
        let cfg = `header = "Authorization: Bearer ${GoogleAccount.accessToken}"\n`;
        if (req.method !== "GET")
            cfg += `request = "${req.method}"\n`;
        if (req.body.length > 0)
            cfg += `header = "Content-Type: application/json"\ndata = "${req.escapeConfig(req.body)}"\n`;
        req.write(cfg);
        req.stdinEnabled = false;
    }

    stdout: StdioCollector {
        onStreamFinished: {
            const cut = text.lastIndexOf("\n");
            const payload = cut === -1 ? "" : text.slice(0, cut);
            req.status = Number(text.slice(cut + 1).trim()) || 0;
            let parsed = null;
            let err = "";
            if (payload.trim().length > 0) {
                try { parsed = JSON.parse(payload); } catch (e) { err = "unreadable response"; }
            }
            if (req.status === 0) err = "no answer";
            else if (req.status >= 400) err = (parsed && parsed.error && (parsed.error.message || parsed.error)) || `HTTP ${req.status}`;
            req._parsed = parsed;
            req._error = String(err);
        }
    }
    stderr: StdioCollector {}
    onExited: (code, exitStatus) => req.settle()
    onRunningChanged: if (!req.running) req.pump()
}
