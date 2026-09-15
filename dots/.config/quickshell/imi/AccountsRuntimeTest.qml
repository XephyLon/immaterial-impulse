import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * The Google account's services inside a real (nested) shell, against
 * tests/fake_google_api.py: the token refreshes through the helper, the
 * selected calendar's events land in IcsCalendar as an external source, the
 * task list and its open tasks arrive, an added task and a completed one
 * round-trip, the inbox unread count lands, and disconnecting clears the
 * lot. Launched by tests/test_accounts_runtime.py with `secret-tool`
 * shadowed by a file-backed stub (IMI_FAKE_SECRET_FILE), so KeyringStorage
 * runs its real path against a throwaway blob and no real item is touched.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    readonly property var keep: [GoogleCalendar, GoogleTasks, Gmail]

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[AccountsRt] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[AccountsRt] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    function googleEvents() {
        return IcsCalendar.events.filter(e => e.calendar === "Probe");
    }

    Timer {
        id: driver
        interval: 250; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 60000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready || !KeyringStorage.loaded) return;
            switch (harness.step) {
            case 0:
                harness.check("nothing is connected at start", !GoogleAccount.connected && !GoogleCalendar.enabled);
                GoogleAccount.setClient("cid-fake", "sec-fake");
                harness.step = 1;
                break;
            case 1:
                if (!GoogleAccount.configured) return;
                // The sign-in's outcome, written the way authorize's exit handler writes it.
                KeyringStorage.setNestedField(["google"], Object.assign({}, GoogleAccount.creds, { refreshToken: "rt-fake", email: "probe@example.com" }));
                harness.step = 2;
                break;
            case 2:
                if (!GoogleAccount.tokenValid) return;
                harness.check("the refresh token becomes an access token through the helper",
                    GoogleAccount.connected && GoogleAccount.accessToken === "at-fake" && GoogleAccount.email === "probe@example.com");
                harness.check("every Google feature is on by default", GoogleCalendar.enabled && GoogleTasks.enabled && Gmail.enabled);
                harness.step = 3;
                break;
            case 3:
                if (harness.googleEvents().length === 0 || GoogleTasks.tasks.length === 0 || !Gmail.synced) return;
                harness.check("the selected calendar is listed and the hidden one is not",
                    GoogleCalendar.calendars.length === 1 && GoogleCalendar.calendars[0].name === "Probe");
                harness.check("its events are in IcsCalendar with the calendar's name and the cancelled one dropped",
                    harness.googleEvents().length === 2 && harness.googleEvents().some(e => e.summary === "Standup" && !e.allDay)
                    && harness.googleEvents().some(e => e.summary === "Day off" && e.allDay)
                    && IcsCalendar.hasEventsOn(harness.googleEvents()[0].year, harness.googleEvents()[0].month, harness.googleEvents()[0].day));
                harness.check("the task list and its open tasks arrive in position order",
                    GoogleTasks.lists.length === 1 && GoogleTasks.currentListId === "L1"
                    && GoogleTasks.tasks.map(t => t.content).join("|") === "Buy milk|Call the bank" && GoogleTasks.tasks[1].due === "2026-09-20");
                harness.check("the inbox unread count lands", Gmail.unread === 4);
                GoogleTasks.addTask("Water the plants");
                harness.step = 4;
                break;
            case 4:
                if (GoogleTasks.tasks.length !== 3) return;
                harness.check("an added task round-trips", GoogleTasks.tasks[2].content === "Water the plants");
                // Two writes in one turn: the queue, not a dropped second click.
                GoogleTasks.completeTask("t1");
                GoogleTasks.completeTask("t2");
                harness.step = 5;
                break;
            case 5:
                if (GoogleTasks.tasks.length !== 1) return;
                harness.check("two tasks completed in one turn both leave the open list",
                    !GoogleTasks.tasks.some(t => t.id === "t1" || t.id === "t2") && GoogleTasks.tasks[0].content === "Water the plants");
                GoogleAccount.disconnect();
                harness.step = 6;
                break;
            case 6:
                if (GoogleAccount.connected || GoogleCalendar.enabled) return;
                harness.check("disconnecting clears the calendars, tasks and count",
                    harness.googleEvents().length === 0 && GoogleTasks.tasks.length === 0 && Gmail.unread === 0 && !Gmail.synced
                    && GoogleAccount.accessToken.length === 0);
                harness.finish();
                break;
            }
        }
    }
}
