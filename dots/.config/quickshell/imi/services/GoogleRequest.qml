import QtQuick
import Quickshell.Io
import qs.services

/**
 * One authenticated call to a Google API: curl with GoogleAccount's bearer
 * token. The token, the method and the JSON body travel to curl through a
 * config document on stdin (`-K -`), never as argv - argv is readable by
 * every process on the machine. Finishes with (json, error, status).
 */
Process {
    id: req
    property string url: ""
    property string method: "GET"
    property string body: ""
    property var json: null
    property string error: ""
    property int status: 0
    signal finished(var json, string error, int status)

    command: ["curl", "-sS", "-m", "20", "-K", "-", "-w", "\n%{http_code}", req.url]
    stdinEnabled: true

    function escapeConfig(s) {
        return String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n");
    }

    function start() {
        if (req.running) return;
        // Re-open stdin for every run: it is closed after the config is
        // written, and a Process started with it disabled inherits the
        // shell's own stdin - curl then waits on that pipe for ever (the
        // second request on any instance hung until this line).
        req.stdinEnabled = true;
        req.running = true;
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
            req.json = parsed;
            req.error = String(err);
            req.finished(parsed, req.error, req.status);
        }
    }
    stderr: StdioCollector {}
    onExited: (code, status) => {
        // curl itself failed before answering (no network, bad URL).
        if (code !== 0 && req.status === 0 && req.error.length === 0) {
            req.error = "no answer";
            req.finished(null, req.error, 0);
        }
    }
}
