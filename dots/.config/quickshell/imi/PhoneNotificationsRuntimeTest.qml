import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * services/PhoneNotifications.qml against the real services/PhoneConnect.qml
 * in a real Quickshell process, fed by a fake `busctl` on PATH.
 *
 * Driven by tests/test_phone_notifications_runtime.py, which reads the fake's
 * recorded invocations back afterwards. The fake daemon exposes one paired,
 * reachable phone with ONE active notification; its `monitor` verb then adds
 * a second to its own state and prints a notificationPosted signal. The
 * second notification reaching the model is the oracle for the whole trigger
 * chain - the signal on PhoneConnect's allowlist, its settle, its
 * deviceChangeSettled(), this service's refetch - because the reconcile is
 * a minute out and PhoneConnect's poll ten minutes out, so nothing else can
 * deliver it inside the harness's lifetime.
 *
 * What is scored here: the sweep's model (fields, package, groups), the
 * dedupe gate, the local effect of dismiss/reply/sendAction/dismissAll, and
 * the cache reaching Persistent. What is scored driver-side: which argv
 * reached the daemon - dismiss on the LEAF path, sendReply/sendAction as the
 * device-level two-string calls, and the refetch landing after the declared
 * delay.
 *
 *   PATH=<dir with fake busctl>:$PATH qs -p PhoneNotificationsRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    readonly property string phoneId: Quickshell.env("PHONE_ID") ?? ""
    readonly property string phoneName: Quickshell.env("PHONE_NAME") ?? ""

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[PhoneNotifications] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[PhoneNotifications] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    function ids() {
        return PhoneNotifications.notifications.map(n => n.publicId).sort();
    }

    Component.onCompleted: {
        // A singleton is constructed on first use; these reads start
        // PhoneConnect's presence probe and this service's triggers.
        console.log(`[PhoneNotifications] services constructed, installed=${PhoneConnect.installed} count=${PhoneNotifications.count}`);
    }

    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            if (!Config.ready || !Persistent.ready || !PhoneConnect.installed || PhoneNotifications.count !== 1) {
                if (harness.elapsed >= 30000) {
                    harness.check(`Config and Persistent ready, busctl found and the first sweep landed (got ${PhoneNotifications.count})`, false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            steps.running = true;
        }
    }

    property var stepList: [
        // ---- the sweep: one notification, read off the leaf ---------------
        () => {
            const n = PhoneNotifications.notifications[0];
            harness.check(`the sweep read the one active notification, got ${harness.ids()}`,
                          PhoneNotifications.count === 1 && n.publicId === "70");
            harness.check("the leaf's fields are on the model",
                          n.appName === "Truecaller" && n.title === "Stay protected 24/7"
                          && n.deviceId === harness.phoneId && n.dismissable === true && n.replyId === "");
            harness.check("the package is read out of the internalId", n.package === "com.truecaller");
            harness.check("the groups follow the desktop list's derivation",
                          PhoneNotifications.appNameList.length === 1 && PhoneNotifications.appNameList[0] === "Truecaller"
                          && PhoneNotifications.groupsByAppName["Truecaller"].notifications.length === 1);
            harness.check("the active device is the paired phone", PhoneNotifications.activeDeviceId === harness.phoneId);
        },

        // ---- the dedupe gate ----------------------------------------------
        () => {
            harness.check("the mirror is active for a reachable phone with the tab on", PhoneNotifications.mirrorActive);
            harness.check("the daemon's own desktop notifications are mirrored",
                          PhoneNotifications.mirrorsDesktopNotification("KDE Connect")
                          && PhoneNotifications.mirrorsDesktopNotification("kdeconnect"));
            harness.check(`a notification posted as the paired phone (${harness.phoneName}) is mirrored`,
                          PhoneNotifications.mirrorsDesktopNotification(harness.phoneName));
            harness.check("any other app's notification is not", !PhoneNotifications.mirrorsDesktopNotification("Firefox"));
        },

        // ---- the second notification arrives from the SIGNAL --------------
        // The fake's monitor prints notificationPosted about a second later
        // than the sweep; wait for it rather than assuming the schedule.
        () => harness.waitFor(() => PhoneNotifications.count === 2, 8000, "signal"),
        () => {
            harness.check(`the notificationPosted signal fetched the new notification, got ${harness.ids()}`,
                          PhoneNotifications.count === 2 && harness.ids().join(",") === "70,71");
            const wa = PhoneNotifications.notifications.find(n => n.publicId === "71");
            harness.check("the new one carries its reply id", wa !== undefined && wa.replyId === "r1" && wa.appName === "WhatsApp");
            harness.check("the app that arrived last sorts first",
                          PhoneNotifications.appNameList.join(",") === "WhatsApp,Truecaller");
        },

        // ---- the cache reaches Persistent -----------------------------------
        () => harness.waitFor(() => (Persistent.states.phone.cachedNotificationsJson ?? "").indexOf('"71"') !== -1,
                              PhoneNotifications.cacheSaveDelay + 3000, "cache"),
        () => {
            const cached = PhoneNotifications.cachedNotificationsFor(Persistent.states.phone.cachedNotificationsJson, harness.phoneId);
            harness.check(`the list is cached per device in Persistent, got ${cached.map(n => n.publicId)}`,
                          cached.length === 2 && cached.some(n => n.publicId === "70") && cached.some(n => n.publicId === "71"));
        },

        // ---- writes, scored driver-side off the fake's log -----------------
        () => {
            PhoneNotifications.dismiss("70");
            harness.check(`dismiss takes the card off the list at once, got ${harness.ids()}`,
                          PhoneNotifications.count === 1 && harness.ids()[0] === "71");
        },
        () => {
            PhoneNotifications.reply("71", "hi there");
            PhoneNotifications.sendAction("71", "Mark as read");
            // A reply to a notification without a reply id, or an empty one,
            // must reach nothing - the driver counts sendReply calls.
            PhoneNotifications.reply("71", "");
            harness.replyRefetchArmedAt = Date.now();
        },
        // The reply's refetch lands replyRefetchDelay later and finds the
        // fake still answering 71: the count holds, the sweep ran (scored
        // driver-side off the timestamps).
        () => harness.waitFor(() => Date.now() - harness.replyRefetchArmedAt > PhoneNotifications.replyRefetchDelay + 600, 3000, "refetch"),
        () => {
            harness.check(`the refetch after the reply keeps the remaining notification, got ${harness.ids()}`,
                          PhoneNotifications.count === 1 && harness.ids()[0] === "71");
            PhoneNotifications.dismissAll();
            harness.check("dismissAll empties the list", PhoneNotifications.count === 0);
        },

        () => harness.finish()
    ]

    property real replyRefetchArmedAt: 0

    // Holds the step list until `predicate` is true or `timeoutMs` passes;
    // a timeout is a failed check, not a hang.
    property var pendingPredicate: null
    property int pendingDeadline: 0
    property string pendingLabel: ""
    function waitFor(predicate, timeoutMs, label) {
        harness.pendingPredicate = predicate;
        harness.pendingDeadline = harness.elapsed + timeoutMs;
        harness.pendingLabel = label;
    }

    property int stepIndex: 0
    Timer {
        id: steps
        interval: 250
        repeat: true
        onTriggered: {
            harness.elapsed += steps.interval;
            if (harness.pendingPredicate !== null) {
                if (harness.pendingPredicate()) {
                    harness.pendingPredicate = null;
                } else if (harness.elapsed >= harness.pendingDeadline) {
                    harness.check(`waited for ${harness.pendingLabel}`, false);
                    harness.pendingPredicate = null;
                } else {
                    return;
                }
            }
            if (harness.stepIndex >= harness.stepList.length)
                return;
            harness.stepList[harness.stepIndex++]();
        }
    }
}
