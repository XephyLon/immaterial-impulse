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
    readonly property bool busy: req.current !== null
    property int status: 0
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

    function pump() {
        if (req.current !== null || req.queue.length === 0) return;
        req.current = req.queue.shift();
        req.url = req.current.url;
        req.method = req.current.method;
        req.body = req.current.body;
        req.status = 0;
        // Re-open stdin for every run: it is closed after the config is
        // written, and a Process started with it disabled inherits the
        // shell's own stdin - curl then waits on that pipe for ever.
        req.stdinEnabled = true;
        req.running = true;
    }

    function settle(parsed, error) {
        const done = req.current;
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
            req.settle(parsed, String(err));
        }
    }
    stderr: StdioCollector {}
    onExited: (code, exitStatus) => {
        // curl itself failed before answering (no network, bad URL): the
        // stream never finished, so settle here.
        if (req.current !== null && req.status === 0) req.settle(null, "no answer");
    }
}
