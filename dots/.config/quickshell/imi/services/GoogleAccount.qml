pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The user's Google account, for the calendar, tasks and mail services
 * (docs/proposals/accounts-integration.md).
 *
 * User OAuth 2.0 with the user's OWN OAuth client: the client ID and secret
 * are pasted once (Settings > Accounts > Google), `connect()` runs the
 * sign-in in the browser through scripts/accounts/google_oauth.py, and the
 * refresh token lands in the keyring under `google` - the one libsecret item
 * KeyringStorage owns, never a second one. Secrets reach the helper in its
 * environment, never on its command line. The access token lives here in
 * memory and is kept fresh while any Google feature is on; consumers read
 * `accessToken` through GoogleRequest and refetch on `tokenRefreshed`.
 */
Singleton {
    id: root

    readonly property var opts: Config.options.accounts?.google
    readonly property var creds: KeyringStorage.keyringData?.google ?? null
    readonly property string clientId: String(root.creds?.clientId ?? "")
    readonly property string clientSecret: String(root.creds?.clientSecret ?? "")
    readonly property string refreshToken: String(root.creds?.refreshToken ?? "")
    readonly property string email: String(root.creds?.email ?? "")
    readonly property bool configured: root.clientId.length > 0 && root.clientSecret.length > 0
    readonly property bool connected: root.configured && root.refreshToken.length > 0
    readonly property bool anyFeatureOn: (root.opts?.calendar ?? false) || (root.opts?.tasks ?? false) || (root.opts?.mail ?? false)

    property string accessToken: ""
    property real tokenExpiresAt: 0
    readonly property bool tokenValid: root.accessToken.length > 0 && Date.now() < root.tokenExpiresAt - 60000
    property bool connecting: false
    property bool refreshing: false
    property string lastError: ""
    signal tokenRefreshed()

    // The tests' fake endpoints; empty for the real ones.
    readonly property string apiBase: Quickshell.env("IMI_GOOGLE_API_BASE") ?? ""
    readonly property string helperPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/accounts/google_oauth.py`)

    function setClient(id, secret) {
        const next = Object.assign({}, root.creds ?? {});
        next.clientId = String(id ?? "").trim();
        next.clientSecret = String(secret ?? "").trim();
        KeyringStorage.setNestedField(["google"], next);
    }

    function connect() {
        if (!root.configured || root.connecting) return;
        root.lastError = "";
        root.connecting = true;
        authProc.running = true;
    }

    function disconnect() {
        const next = Object.assign({}, root.creds ?? {});
        next.refreshToken = "";
        next.email = "";
        KeyringStorage.setNestedField(["google"], next);
        root.accessToken = "";
        root.tokenExpiresAt = 0;
    }

    function refreshNow() {
        if (!root.connected || root.refreshing) return;
        root.refreshing = true;
        refreshProc.running = true;
    }

    // Secrets in the environment: the helper's argv is public.
    readonly property var helperEnv: ({
        GOOGLE_CLIENT_ID: root.clientId,
        GOOGLE_CLIENT_SECRET: root.clientSecret,
        GOOGLE_REFRESH_TOKEN: root.refreshToken,
    })

    Process {
        id: authProc
        command: ["python3", root.helperPath, "authorize"]
        environment: root.helperEnv
        stdout: StdioCollector { id: authOut }
        stderr: StdioCollector { id: authErr }
        onExited: (code, status) => {
            root.connecting = false;
            let parsed = null;
            try { parsed = JSON.parse(authOut.text.trim().split("\n").pop()); } catch (e) { parsed = null; }
            if (code !== 0 || !parsed || !parsed.refresh_token) {
                root.lastError = parsed?.error ?? (authErr.text.trim() || "sign-in failed");
                console.warn("[GoogleAccount] authorize:", root.lastError);
                return;
            }
            const next = Object.assign({}, root.creds ?? {});
            next.refreshToken = String(parsed.refresh_token);
            next.email = String(parsed.email ?? "");
            KeyringStorage.setNestedField(["google"], next);
        }
    }

    Process {
        id: refreshProc
        command: ["python3", root.helperPath, "refresh"]
        environment: root.helperEnv
        stdout: StdioCollector { id: refreshOut }
        onExited: (code, status) => {
            root.refreshing = false;
            let parsed = null;
            try { parsed = JSON.parse(refreshOut.text.trim().split("\n").pop()); } catch (e) { parsed = null; }
            if (code !== 0 || !parsed || !parsed.access_token) {
                root.lastError = parsed?.error ?? "token refresh failed";
                console.warn("[GoogleAccount] refresh:", root.lastError);
                return;
            }
            root.lastError = "";
            root.accessToken = String(parsed.access_token);
            root.tokenExpiresAt = Date.now() + (Number(parsed.expires_in) || 3600) * 1000;
            root.tokenRefreshed();
        }
    }

    // Keep the token fresh while something reads it: one check a minute, a
    // refresh only when the token is within a minute of expiring.
    Timer {
        running: root.connected && root.anyFeatureOn
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.tokenValid) root.refreshNow()
    }
    onConnectedChanged: if (root.connected && root.anyFeatureOn) root.refreshNow()

    Component.onCompleted: if (!KeyringStorage.loaded) KeyringStorage.fetchKeyringData()
}
