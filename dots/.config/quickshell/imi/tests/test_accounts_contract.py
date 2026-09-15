#!/usr/bin/env python3
"""Accounts (docs/proposals/accounts-integration.md): the wiring pinned.

Credentials live under one key of the keyring blob and reach the helpers in
their environment, never argv; the Google services read one account and one
overridable API base; the calendar lands in IcsCalendar as an external source;
the Proton VPN service is two-staged like Tailscale and its toggle is in both
panels; the settings page and the search index agree; the bar's mail widget
is a catalogue id.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT = ROOT / "services/GoogleAccount.qml"
REQUEST = ROOT / "services/GoogleRequest.qml"
CALENDAR = ROOT / "services/GoogleCalendar.qml"
TASKS = ROOT / "services/GoogleTasks.qml"
GMAIL = ROOT / "services/Gmail.qml"
ICS = ROOT / "services/IcsCalendar.qml"
PROTON = ROOT / "services/ProtonVpn.qml"
OAUTH = ROOT / "scripts/accounts/google_oauth.py"
PROTON_CTL = ROOT / "scripts/accounts/protonvpn_ctl.py"
CONFIG = ROOT / "modules/common/Config.qml"
PAGE = ROOT / "modules/imi/settings/pages/AccountsConfig.qml"
INDEX = ROOT / "modules/imi/settings/SettingsContent.qml"
CATALOGUE = ROOT / "modules/common/plugins/BarWidgets.qml"
MAIL_WIDGET = ROOT / "modules/imi/bar/MailIndicator.qml"
TODO_WIDGET = ROOT / "modules/imi/sidebarRight/todo/TodoWidget.qml"
TASK_LIST = ROOT / "modules/imi/sidebarRight/todo/TaskList.qml"
CLASSIC = ROOT / "modules/imi/sidebarRight/quickToggles/ClassicQuickPanel.qml"
ANDROID = ROOT / "modules/imi/sidebarRight/quickToggles/AndroidQuickPanel.qml"
CHOOSER = ROOT / "modules/imi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class AccountsContract(unittest.TestCase):
    def test_secrets_stay_in_the_keyring_blob_and_the_environment(self):
        acc = _strip(ACCOUNT.read_text())
        self.assertIn('KeyringStorage.setNestedField(["google"], next)', acc, "one key of the one keyring item")
        self.assertIn("environment: root.helperEnv", acc)
        self.assertNotRegex(acc, r'"--client-secret"|"--refresh-token"', "secrets never in argv")
        self.assertIn('command: ["python3", root.helperPath, "authorize"]', acc)
        self.assertIn('command: ["python3", root.helperPath, "refresh"]', acc)
        req = _strip(REQUEST.read_text())
        self.assertIn('"-K", "-"', req, "the bearer header travels to curl on stdin, not argv")
        self.assertNotIn('"-H"', req)
        self.assertIn("function request(url, method, body, tag)", req, "calls queue; a second one is never dropped")
        self.assertIn("req.stdinEnabled = true;", req)
        self.assertIn("signal finished(var json, string error, int status, var tag)", req)
        oauth = OAUTH.read_text()
        self.assertIn('os.environ.get("GOOGLE_CLIENT_SECRET"', oauth)
        self.assertIn('"code_challenge_method": "S256"', oauth, "PKCE")
        self.assertIn('"access_type": "offline"', oauth)
        self.assertIn("IMI_GOOGLE_OAUTH_BASE", oauth, "the tests' fake endpoint")

    def test_the_services_read_one_account_and_land_where_the_shell_reads(self):
        for path, flag in ((CALENDAR, "calendar"), (TASKS, "tasks"), (GMAIL, "mail")):
            src = _strip(path.read_text())
            self.assertIn(f"(Config.options.accounts?.google?.{flag} ?? false) && GoogleAccount.connected", src, path.name)
            self.assertIn("GoogleRequest {", src, path.name)
            self.assertIn("if (!root.enabled) return;", src, f"{path.name}: a result after disconnect is dropped")
            self.assertIn("req.clear()", src, f"{path.name}: disconnect empties the queue")
            self.assertIn("function onTokenRefreshed() { root.refresh(); }", src, path.name)
            self.assertIn("GoogleAccount.apiBase", src, f"{path.name} takes the overridable base")
        cal = _strip(CALENDAR.read_text())
        self.assertIn('IcsCalendar.setExternalEvents("google:" + tag.calendarId, events)', cal, "the calendar's identity rides in the request's tag")
        self.assertNotIn("IcsCalendar._externalEvents", cal, "no reach into another singleton's private map")
        tasks = _strip(TASKS.read_text())
        self.assertIn("G.tasksCollectionUrl(GoogleAccount.apiBase, root.currentListId)", tasks)
        self.assertIn("root.currentListId.length === 0) return;", tasks, "writes need a list")
        acc = _strip(ACCOUNT.read_text())
        self.assertIn("function backOff()", acc, "a failing refresh backs off with a ceiling")
        self.assertIn("singleEvents", (ROOT / "services/google_api.js").read_text(), "recurrences expand server-side")
        ics = _strip(ICS.read_text())
        self.assertIn("function setExternalEvents(sourceId, events)", ics)
        self.assertIn("for (const k in root._externalEvents)", ics, "external sources merge into the one list")
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject accounts: JsonObject {"):]
        for key in ("property bool calendar: true", "property bool tasks: true", "property bool mail: true",
                    "property int refreshMinutes: 5", "property int calendarDays: 14",
                    "property JsonObject proton: JsonObject {", "property int pollInterval: 60000"):
            self.assertIn(key, block[:1200], key)

    def test_the_todo_widget_keeps_the_lists_apart(self):
        widget = _strip(TODO_WIDGET.read_text())
        self.assertIn("readonly property bool googleAvailable: GoogleTasks.enabled && GoogleTasks.lists.length > 0", widget)
        self.assertIn("FilterChip {", widget)
        self.assertIn("Revealer {\n            Layout.fillWidth: true\n            reveal: root.googleAvailable", widget, "the row unrolls; no bare visible")
        self.assertIn('source: root.googleSource ? "google" : "local"', widget)
        self.assertIn("GoogleTasks.addTask(todoInput.text)", widget)
        tl = _strip(TASK_LIST.read_text())
        self.assertIn('property string source: "local"', tl)
        self.assertIn("GoogleTasks.completeTask(todoItem.modelData.id)", tl)
        self.assertIn("GoogleTasks.deleteTask(todoItem.modelData.id)", tl)

    def test_proton_vpn_is_two_staged_and_in_both_panels(self):
        proton = _strip(PROTON.read_text())
        self.assertIn("readonly property bool available: root.installed && root.loggedIn", proton)
        self.assertIn('command: ["python3", root.helperPath, "status"]', proton)
        # Presence is a file check that starts on its own; the Python read runs
        # only while someone is looking, started imperatively (never a
        # `running:` binding beside an assignment).
        self.assertIn("id: presenceProc\n        running: root.enableService", proton)
        self.assertIn("running: root.enableService && root.installed && root.watched", proton)
        self.assertNotRegex(proton, r"id: statusProc\n\s*running:", "the status process has no running binding")
        self.assertIn("readonly property bool watched: root.watchers > 0 || GlobalStates.sidebarRightOpen", proton)
        self.assertIn("function onMonitorEvent()", proton, "reconciles on NetworkManager's events like Vpn.qml")
        self.assertNotIn("onOpenMenu: root.openTailscaleDialog()", CHOOSER.read_text().split('roleValue: "protonVpn"')[1].split("DelegateChoice")[0])
        self.assertIn("ProtonVpn.acquire()", _strip(PAGE.read_text()), "the page is a watcher while shown")
        self.assertIn("proton-vpn-gtk-app", (ROOT.parents[3] / "sdata/deps-info.md").read_text(), "the optional dependency is documented")
        self.assertNotIn("password", proton.lower(), "the shell never sees the Proton password")
        ctl = PROTON_CTL.read_text()
        self.assertIn("api.is_user_logged_in()", ctl)
        self.assertNotIn("login(", ctl.replace("is_user_logged_in(", ""), "the helper never logs in; the app's session is the session")
        self.assertIn("QuickToggleButton { toggleModel: ProtonVpnToggle {} }", _strip(CLASSIC.read_text()))
        self.assertIn('"protonVpn"', ANDROID.read_text())
        self.assertIn('roleValue: "protonVpn"', CHOOSER.read_text())

    def test_settings_page_bar_widget_and_index(self):
        page = _strip(PAGE.read_text())
        self.assertIn("forceWidth: true", page)
        self.assertIn("GoogleAccount.setClient(page.clientIdDraft, page.clientSecretDraft)", page)
        self.assertIn("password: true", page, "the secret field is masked")
        self.assertIn('text: Translation.tr("OAuth client ID")', page, "the credential fields carry labels")
        self.assertNotRegex(page, r"opacity: enabled \?", "no opacity written over a self-dimming control")
        self.assertIn("GoogleAccount.connected ? GoogleAccount.disconnect() : GoogleAccount.connect()", page)
        self.assertIn("Config.options.calendar.ics.urls", page, "the ICS feeds finally have rows")
        self.assertNotIn("StyledToolTip { text: Translation.tr(\"Off:", page)
        index = INDEX.read_text()
        self.assertIn('id: "accounts", icon: "account_circle", component: Qt.resolvedUrl("pages/AccountsConfig.qml")', index)
        self.assertIn('{ id: "mailIndicator",', CATALOGUE.read_text())
        mail = _strip(MAIL_WIDGET.read_text())
        self.assertIn("readonly property bool shown: Gmail.enabled && Gmail.synced", mail)
        self.assertIn("visible: implicitWidth > 0", mail)
        self.assertIn("Behavior on implicitWidth {\n        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)", mail)


if __name__ == "__main__":
    unittest.main()
