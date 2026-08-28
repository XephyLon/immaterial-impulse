import QtQuick
import QtTest
import testservices

// Behavioral tests for the parsing/normalization logic of
// services/PhoneNotifications.qml, exercised through the logic-only double in
// tests/imports/testservices. The two fixtures are verbatim `busctl
// --json=short` replies captured from a live KDE Connect daemon (2026-08-27):
// the device's activeNotifications list and one notification leaf's GetAll.
TestCase {
    name: "PhoneNotificationsTest"

    readonly property string deviceId: "6131a746_571a_4176_a007_95625ff8e08e"

    // busctl --user --json=short call org.kde.kdeconnect.daemon
    //   /modules/kdeconnect/devices/<id>/notifications
    //   org.kde.kdeconnect.device.notifications activeNotifications
    readonly property string activeReply: '{"type":"as","data":[["70"]]}'

    // busctl --user --json=short call org.kde.kdeconnect.daemon
    //   /modules/kdeconnect/devices/<id>/notifications/70
    //   org.freedesktop.DBus.Properties GetAll s
    //   org.kde.kdeconnect.device.notifications.notification
    readonly property string leafReply: '{"type":"a{sv}","data":[{"appName":{"type":"s","data":"Truecaller"},"dismissable":{"type":"b","data":true},"groupName":{"type":"s","data":""},"hasIcon":{"type":"b","data":true},"iconPath":{"type":"s","data":"/tmp/kdeconnect_xephy/eb39605216ceabbbd952b1ab18d00267"},"internalId":{"type":"s","data":"0|com.truecaller|2131366136|null|10553"},"isConversation":{"type":"b","data":false},"isGroupConversation":{"type":"b","data":false},"replyId":{"type":"s","data":""},"silent":{"type":"b","data":false},"text":{"type":"s","data":"Allow Truecaller to run in the background to identify and block calls while you are not using the app"},"ticker":{"type":"s","data":"Stay protected 24/7: Allow Truecaller to run in the background to identify and block calls while you are not using the app"},"title":{"type":"s","data":"Stay protected 24/7"}}]}'

    function init() {
        PhoneNotifications.activeDeviceId = deviceId
        PhoneNotifications.mirrorActive = false
        PhoneNotifications.notifications = []
    }

    function leaf(publicId, overrides) {
        const props = JSON.parse(leafReply).data[0]
        for (const key in (overrides ?? {}))
            props[key] = overrides[key]
        return PhoneNotifications.normalizeNotification(publicId, deviceId, props, 1000)
    }

    // ---- the activeNotifications reply ----

    function test_active_notifications_reply_is_a_list_of_public_ids() {
        const data = PhoneConnect.parseBusctlReply(activeReply)
        compare(data.length, 1)
        compare(data[0], ["70"])
        verify(PhoneNotifications.validPublicId("70"))
    }

    function test_public_ids_are_kept_boring_before_they_reach_a_path() {
        verify(PhoneNotifications.validPublicId("70"))
        verify(PhoneNotifications.validPublicId("abc_9"))
        verify(!PhoneNotifications.validPublicId(""))
        verify(!PhoneNotifications.validPublicId("70/../battery"))
        verify(!PhoneNotifications.validPublicId("70 71"))
        verify(!PhoneNotifications.validPublicId(70))
        verify(!PhoneNotifications.validPublicId(null))
    }

    // ---- packageFromInternalId ----

    function test_package_is_the_second_field_of_a_zero_prefixed_internal_id() {
        compare(PhoneNotifications.packageFromInternalId("0|com.truecaller|2131366136|null|10553"), "com.truecaller")
        compare(PhoneNotifications.packageFromInternalId("0|com.whatsapp|1|N3JGW5Lg6vbO|10466"), "com.whatsapp")
        compare(PhoneNotifications.packageFromInternalId("0| com.spaced |x"), "com.spaced")
    }

    function test_package_is_empty_when_the_internal_id_has_another_shape() {
        compare(PhoneNotifications.packageFromInternalId(""), "")
        compare(PhoneNotifications.packageFromInternalId(null), "")
        compare(PhoneNotifications.packageFromInternalId("0"), "")
        compare(PhoneNotifications.packageFromInternalId("1|com.other|x"), "")
        compare(PhoneNotifications.packageFromInternalId("com.other"), "")
    }

    // ---- normalizeNotification ----

    function test_normalize_reads_the_captured_leaf_onto_the_model() {
        const raw = PhoneConnect.parseBusctlReply(leafReply)[0]
        const n = PhoneNotifications.normalizeNotification("70", deviceId, raw, 1234)
        compare(n.publicId, "70")
        compare(n.deviceId, deviceId)
        compare(n.internalId, "0|com.truecaller|2131366136|null|10553")
        compare(n.package, "com.truecaller")
        compare(n.appName, "Truecaller")
        compare(n.title, "Stay protected 24/7")
        compare(n.text, "Allow Truecaller to run in the background to identify and block calls while you are not using the app")
        verify(n.ticker.startsWith("Stay protected 24/7: "))
        compare(n.iconPath, "/tmp/kdeconnect_xephy/eb39605216ceabbbd952b1ab18d00267")
        compare(n.dismissable, true)
        compare(n.replyId, "")
        compare(n.actions, [])
        compare(n.receivedAt, 1234)
    }

    function test_normalize_degrades_a_sparse_leaf_to_empty_strings_and_a_dismissable_default() {
        const n = PhoneNotifications.normalizeNotification("3", deviceId, {}, 5)
        compare(n.appName, "")
        compare(n.title, "")
        compare(n.text, "")
        compare(n.ticker, "")
        compare(n.iconPath, "")
        compare(n.internalId, "")
        compare(n.package, "")
        compare(n.dismissable, true)
        compare(n.replyId, "")
        compare(n.actions, [])
        const undismissable = leaf("4", { "dismissable": { "type": "b", "data": false }, "replyId": { "type": "s", "data": "reply-9" } })
        compare(undismissable.dismissable, false)
        compare(undismissable.replyId, "reply-9")
    }

    function test_normalize_keeps_only_string_actions() {
        const n = leaf("5", { "actions": { "type": "as", "data": ["Mark as read", 7, null, "Reply"] } })
        compare(n.actions, ["Mark as read", "Reply"])
    }

    // ---- carryReceivedAt ----

    function test_a_refetch_keeps_the_time_a_known_notification_first_arrived() {
        const before = [leaf("70")]
        before[0].receivedAt = 100
        const fresh = [leaf("70"), leaf("71")]
        fresh[0].receivedAt = 900
        fresh[1].receivedAt = 900
        const merged = PhoneNotifications.carryReceivedAt(before, fresh)
        compare(merged.length, 2)
        compare(merged[0].publicId, "70")
        compare(merged[0].receivedAt, 100)
        compare(merged[1].publicId, "71")
        compare(merged[1].receivedAt, 900)
        // The previous list is not mutated and a dropped id does not come back.
        compare(PhoneNotifications.carryReceivedAt(before, []).length, 0)
    }

    // ---- groups ----

    function test_groups_by_app_name_newest_app_first_like_the_desktop_list() {
        const older = leaf("70")
        older.receivedAt = 100
        const newer = leaf("71", { "appName": { "type": "s", "data": "WhatsApp" }, "iconPath": { "type": "s", "data": "/tmp/wa" } })
        newer.receivedAt = 300
        const sibling = leaf("72")
        sibling.receivedAt = 200
        const groups = PhoneNotifications.groupsForList([older, newer, sibling])
        compare(Object.keys(groups).sort(), ["Truecaller", "WhatsApp"])
        compare(groups["Truecaller"].notifications.length, 2)
        compare(groups["Truecaller"].time, 200)
        compare(groups["Truecaller"].appIcon, "/tmp/kdeconnect_xephy/eb39605216ceabbbd952b1ab18d00267")
        compare(groups["WhatsApp"].appIcon, "/tmp/wa")
        compare(groups["WhatsApp"].time, 300)
        compare(PhoneNotifications.appNameListForGroups(groups), ["WhatsApp", "Truecaller"])
    }

    function test_the_double_derives_groups_from_its_list() {
        const a = leaf("70")
        a.receivedAt = 10
        const b = leaf("71", { "appName": { "type": "s", "data": "Signal" } })
        b.receivedAt = 20
        PhoneNotifications.applyNotifications([a, b], deviceId)
        compare(PhoneNotifications.count, 2)
        compare(PhoneNotifications.appNameList, ["Signal", "Truecaller"])
        compare(PhoneNotifications.groupsByAppName["Signal"].notifications[0].publicId, "71")
        // A sweep for a device that is no longer the active one is dropped.
        PhoneNotifications.applyNotifications([leaf("9")], "someone-else")
        compare(PhoneNotifications.count, 2)
    }

    // ---- the desktop dedupe predicate ----

    function test_the_daemons_own_app_names_are_mirrored_case_insensitively() {
        for (const name of ["kdeconnect", "KDE Connect", "kde connect", "org.kde.kdeconnect", "KDEConnect"])
            verify(PhoneNotifications.mirrorsAppName(name, []), `${name} is the daemon`)
    }

    function test_a_paired_devices_name_is_mirrored_and_other_apps_are_not() {
        const names = ["Galaxy S23 Ultra", "rox-xbox-ally-x"]
        verify(PhoneNotifications.mirrorsAppName("Galaxy S23 Ultra", names))
        verify(PhoneNotifications.mirrorsAppName("galaxy s23 ultra", names))
        verify(!PhoneNotifications.mirrorsAppName("Firefox", names))
        verify(!PhoneNotifications.mirrorsAppName("", names))
        verify(!PhoneNotifications.mirrorsAppName(null, names))
        verify(!PhoneNotifications.mirrorsAppName("Galaxy", names))
        verify(!PhoneNotifications.mirrorsAppName("Galaxy S23 Ultra", null))
    }

    // ---- the persisted cache ----

    function test_the_cache_round_trips_per_device_and_keeps_other_devices_entries() {
        const first = PhoneNotifications.cacheWith("", deviceId, [leaf("70")], 500)
        const second = PhoneNotifications.cacheWith(first, "other", [leaf("1"), leaf("2")], 600)
        const doc = JSON.parse(second)
        compare(Object.keys(doc).sort(), [deviceId, "other"])
        compare(doc[deviceId].savedAt, 500)
        compare(doc[deviceId].notifications.length, 1)
        compare(doc["other"].notifications.length, 2)
        const restored = PhoneNotifications.cachedNotificationsFor(second, deviceId)
        compare(restored.length, 1)
        compare(restored[0].publicId, "70")
        compare(restored[0].appName, "Truecaller")
        compare(PhoneNotifications.cachedNotificationsFor(second, "other").length, 2)
    }

    // A cache is written by whichever version of the service was running that
    // day. This one predates the fields the shared notification card reads,
    // and restoring it used to hand the card a row of undefineds: four
    // buttons refusing `urgency`, the icon refusing `image`, and
    // NotificationUtils calling `.replace` on an undefined body. Found on a
    // live shell, because every fixture in this suite writes a CURRENT cache.
    function test_a_cache_written_before_the_card_s_fields_is_upgraded_on_restore() {
        const legacy = JSON.stringify({
            [deviceId]: {
                notifications: [{
                    // Boring by the same rule every id in this service is
                    // held to before it is spliced into a D-Bus path.
                    publicId: "notif_7",
                    deviceId: deviceId,
                    appName: "Example",
                    title: "Old shape",
                    text: "Written before the card's fields existed",
                    iconPath: "/tmp/example.png",
                    actions: [],
                    receivedAt: 1000
                }]
            }
        });
        const restored = PhoneNotifications.cachedNotificationsFor(legacy, deviceId);
        compare(restored.length, 1);
        // The daemon's own names survive...
        compare(restored[0].title, "Old shape");
        // ...and the card's are derived rather than left undefined.
        compare(restored[0].summary, "Old shape");
        compare(restored[0].body, "Written before the card's fields existed");
        compare(typeof restored[0].urgency, "number");
        verify(String(restored[0].image).indexOf("example.png") >= 0);
    }

    function test_the_cache_answers_nothing_for_an_unknown_device_or_a_broken_document() {
        compare(PhoneNotifications.cachedNotificationsFor("", deviceId), [])
        compare(PhoneNotifications.cachedNotificationsFor(null, deviceId), [])
        compare(PhoneNotifications.cachedNotificationsFor("{not json", deviceId), [])
        compare(PhoneNotifications.cachedNotificationsFor('{"x":{"notifications":[]}}', deviceId), [])
        compare(PhoneNotifications.cachedNotificationsFor('{"' + deviceId + '":{"notifications":"nope"}}', deviceId), [])
        // An entry without a usable public id cannot be dismissed, so it is
        // not restored either.
        const doc = '{"' + deviceId + '":{"savedAt":1,"notifications":[{"publicId":"70","appName":"A"},{"appName":"B"},null,{"publicId":"../x"}]}}'
        const restored = PhoneNotifications.cachedNotificationsFor(doc, deviceId)
        compare(restored.length, 1)
        compare(restored[0].publicId, "70")
    }

    function test_a_broken_cache_document_is_replaced_rather_than_kept() {
        const doc = JSON.parse(PhoneNotifications.cacheWith("{not json", deviceId, [], 7))
        compare(Object.keys(doc), [deviceId])
        compare(doc[deviceId].notifications, [])
    }
}
