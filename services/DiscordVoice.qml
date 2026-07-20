pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property string status: "starting"
    property string errorMessage: ""
    property var currentUser: ({})
    property var channel: null
    property var participants: []
    property bool muted: false
    property bool deafened: false
    property int restartAttempts: 0
    readonly property bool authenticated: status === "authenticated" || channel !== null
    readonly property bool inVoice: channel !== null
    readonly property int maxRestartAttempts: 5

    function avatarUrl(user, size) {
        if (!user?.id || !user?.avatar) return "";
        return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png?size=${size || 64}`;
    }

    function send(message) {
        if (!bridge.running) {
            start(true);
            return;
        }
        bridge.write(JSON.stringify(message) + "\n");
    }

    function connect() {
        errorMessage = "";
        send({cmd: "connect"});
    }

    function authorize() { send({cmd: "authorize"}); }
    function authorizeAfterFocusRelease() { focusReleaseDelay.restart(); }
    function setMuted(value) { send({cmd: "set_voice_settings", mute: value}); }
    function setDeafened(value) { send({cmd: "set_voice_settings", deaf: value}); }

    function start(manual) {
        if (bridge.running) return;
        if (manual) restartAttempts = 0;
        status = "starting";
        bridge.running = true;
    }

    function handleLine(line) {
        let message;
        try { message = JSON.parse(line); } catch (error) { return; }
        switch (message.type) {
        case "ready": connect(); break;
        case "connected": status = "connected"; break;
        case "auth_required": status = "auth_required"; break;
        case "authorizing":
            status = "authorizing";
            authorizationTimeout.restart();
            break;
        case "authenticated":
            authorizationTimeout.stop();
            status = "authenticated";
            currentUser = message.user || {};
            restartAttempts = 0;
            break;
        case "voice_channel":
            channel = message.channel || null;
            participants = message.users || [];
            break;
        case "voice_state": participants = message.users || []; break;
        case "voice_settings":
            muted = message.mute === true;
            deafened = message.deaf === true;
            break;
        case "unavailable": status = "unavailable"; errorMessage = message.message || ""; break;
        case "disconnected": status = "disconnected"; channel = null; participants = []; break;
        case "error":
            authorizationTimeout.stop();
            status = "auth_required";
            errorMessage = message.message || "Discord RPC error";
            break;
        }
    }

    Component.onCompleted: start(false)

    Timer {
        id: restartTimer
        onTriggered: root.start(false)
    }

    Timer {
        id: authorizationTimeout
        interval: 30000
        onTriggered: {
            root.status = "auth_required";
            root.errorMessage = "Discord did not complete authorization";
        }
    }

    Timer {
        id: focusReleaseDelay
        interval: 220
        onTriggered: root.authorize()
    }

    Process {
        id: bridge
        command: ["python3", `${Directories.scriptPath}/discordVoice/discord_voice_bridge.py`]
        stdinEnabled: true
        // process-lifecycle: restart-safe -- capped exponential backoff; no running binding.
        stdout: SplitParser { onRead: data => root.handleLine(data) }
        stderr: SplitParser { onRead: data => console.warn("[DiscordVoice]", data) }
        onExited: (code, status) => {
            root.channel = null;
            root.participants = [];
            if (root.restartAttempts >= root.maxRestartAttempts) {
                root.status = "stopped";
                root.errorMessage = "Discord bridge stopped after repeated failures";
                return;
            }
            root.restartAttempts++;
            root.status = "restarting";
            restartTimer.interval = Math.min(30000, 1000 * Math.pow(2, root.restartAttempts - 1));
            restartTimer.restart();
        }
    }
}
