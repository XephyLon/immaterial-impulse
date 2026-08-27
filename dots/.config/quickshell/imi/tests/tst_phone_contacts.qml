import QtQuick
import QtTest
import testservices

// The contacts list's decisions - what a query matches, which cards the
// nameless filter hides and which it may never hide, how the list sorts,
// what starring does, and what argv reaches adb - exercised through the
// logic-only double in tests/imports/testservices. The fixture is shaped
// after what scripts/phone/contacts_monitor.py emits.
TestCase {
    name: "PhoneContactsTest"

    function contact(overrides) {
        return Object.assign({
            id: "", displayName: "", givenName: "", familyName: "", organization: "",
            phones: [], emails: [], photo: "", nameless: false, source: "kdeconnect-dev1"
        }, overrides)
    }

    function phone(value, type, primary) {
        return { value: value, normalized: value.replace(/[\s\-().]/g, ""), type: type, primary: primary === true }
    }

    readonly property var ada: contact({ id: "ada", displayName: "Ada Zed", givenName: "Ada", familyName: "Zed",
        organization: "Zed Labs", phones: [phone("+1 (555) 010-0001", "mobile", true)],
        emails: [{ value: "ada@zed.example", type: "work", primary: true }] })
    readonly property var bo: contact({ id: "bo", displayName: "Bo Ander", givenName: "Bo", familyName: "Ander",
        phones: [phone("555 010 0002", "home", true)] })
    readonly property var bare: contact({ id: "bare", displayName: "+15550100099", givenName: "+15550100099",
        phones: [phone("+15550100099", "mobile", true)], nameless: true })
    readonly property var starredBare: contact({ id: "starred", displayName: "+15550100077",
        phones: [phone("+15550100077", "mobile", true)], nameless: true })
    readonly property var orgOnly: contact({ id: "org", displayName: "Example Corp", organization: "Example Corp",
        phones: [phone("+15550100050", "work", true)] })

    function ids(list) {
        const out = []
        for (let i = 0; i < list.length; i++) out.push(list[i].id)
        return out
    }

    function init() {
        PhoneContacts.contacts = [bare, ada, starredBare, bo, orgOnly]
        PhoneContacts.query = ""
        PhoneContacts.hideUnnamed = true
        PhoneContacts.favorites = []
        PhoneContacts.sortBy = "first"
    }

    // ---- the filter ----

    function test_no_query_lists_every_named_contact_sorted_by_first_name() {
        compare(ids(PhoneContacts.filtered), ["ada", "bo", "org"])
        compare(PhoneContacts.count, 5, "count is the whole set, not the drawn list")
    }

    function test_a_query_matches_a_name_case_insensitively() {
        PhoneContacts.query = "aDa"
        compare(ids(PhoneContacts.filtered), ["ada"])
    }

    function test_a_query_matches_the_organization() {
        PhoneContacts.query = "labs"
        compare(ids(PhoneContacts.filtered), ["ada"])
    }

    function test_a_query_matches_an_email_address() {
        PhoneContacts.query = "zed.example"
        compare(ids(PhoneContacts.filtered), ["ada"])
    }

    function test_digits_match_a_number_across_its_separators() {
        // "555 010" is typed the way the number is drawn; the number is
        // stored as "+1 (555) 010-0001", so only the digits may be compared.
        PhoneContacts.query = "555 010-000"
        compare(ids(PhoneContacts.filtered), ["ada", "bo"])
        PhoneContacts.query = "(555) 010-0001"
        compare(ids(PhoneContacts.filtered), ["ada"], "separators in the query are dropped, not matched")
    }

    function test_a_query_that_matches_nothing_is_an_empty_list() {
        PhoneContacts.query = "nobody"
        compare(PhoneContacts.filtered.length, 0)
    }

    function test_whitespace_around_a_query_is_ignored() {
        PhoneContacts.query = "  bo  "
        compare(ids(PhoneContacts.filtered), ["bo"])
    }

    // ---- the nameless filter ----

    function test_hide_unnamed_drops_a_card_that_is_only_a_number() {
        verify(!ids(PhoneContacts.filtered).includes("bare"))
        PhoneContacts.hideUnnamed = false
        compare(ids(PhoneContacts.filtered), ["starred", "bare", "ada", "bo", "org"],
                "with the filter off the numbers sort ahead of the letters, 0077 before 0099")
    }

    function test_a_starred_nameless_card_is_never_hidden() {
        PhoneContacts.favorites = ["starred"]
        compare(ids(PhoneContacts.filtered), ["starred", "ada", "bo", "org"])
    }

    function test_a_starred_nameless_card_still_has_to_match_the_query() {
        PhoneContacts.favorites = ["starred"]
        PhoneContacts.query = "ada"
        compare(ids(PhoneContacts.filtered), ["ada"], "never hidden is about the nameless filter, not the search")
        PhoneContacts.query = "0077"
        compare(ids(PhoneContacts.filtered), ["starred"])
    }

    function test_the_nameless_query_still_finds_a_hidden_card_by_its_number_only_when_shown() {
        PhoneContacts.query = "0099"
        compare(PhoneContacts.filtered.length, 0, "hidden means hidden, even to a search")
        PhoneContacts.hideUnnamed = false
        compare(ids(PhoneContacts.filtered), ["bare"])
    }

    // ---- sorting ----

    function test_sort_by_last_name_orders_by_family_name() {
        PhoneContacts.sortBy = "last"
        compare(ids(PhoneContacts.filtered), ["bo", "org", "ada"],
                "Ander, then a card with no family name by its display name, then Zed")
    }

    function test_a_card_without_a_given_name_sorts_by_its_display_name() {
        PhoneContacts.contacts = [ada, orgOnly]
        compare(ids(PhoneContacts.filtered), ["ada", "org"])
        PhoneContacts.contacts = [contact({ id: "z", displayName: "Zulu Org", organization: "Zulu Org" }), ada]
        compare(ids(PhoneContacts.filtered), ["ada", "z"])
    }

    function test_sorting_is_case_insensitive_and_stable_on_ties() {
        const lower = contact({ id: "l", displayName: "adam", givenName: "adam" })
        const upper = contact({ id: "u", displayName: "Adam B", givenName: "Adam", familyName: "B" })
        PhoneContacts.contacts = [upper, lower]
        compare(ids(PhoneContacts.filtered), ["l", "u"], "equal keys fall back to the display name")
        // The tie-break must not be the runner's collation: this ordering was
        // green under en_US.UTF-8 and red in CI's C locale, because
        // localeCompare put "Adam B" before "adam" there.
        compare(PhoneContacts.compareFolded("adam", "Adam B"), -1, "the fold decides, not the case")
        compare(PhoneContacts.compareFolded("Adam B", "adam"), 1, "and it decides the same way round")
        compare(PhoneContacts.compareFolded("ADAM", "adam"), 0, "case alone is not an ordering")
    }

    function test_the_filter_does_not_mutate_the_source_list() {
        const before = ids(PhoneContacts.contacts)
        PhoneContacts.sortBy = "last"
        void PhoneContacts.filtered
        compare(ids(PhoneContacts.contacts), before)
    }

    // ---- favorites ----

    function test_toggling_adds_then_removes_and_never_mutates_the_input() {
        const start = ["ada"]
        const added = PhoneContacts.toggledFavorites(start, "bo")
        compare(added, ["ada", "bo"])
        compare(start, ["ada"], "the stored list is replaced, never spliced in place")
        compare(PhoneContacts.toggledFavorites(added, "ada"), ["bo"])
        compare(PhoneContacts.toggledFavorites([], "x"), ["x"])
        compare(PhoneContacts.toggledFavorites(null, "x"), ["x"])
    }

    function test_is_favorite_reads_the_list_by_index() {
        verify(PhoneContacts.isFavorite("ada", ["bo", "ada"]))
        verify(!PhoneContacts.isFavorite("ada", ["bo"]))
        verify(!PhoneContacts.isFavorite("ada", null))
        verify(!PhoneContacts.isFavorite("", ["ada"]))
    }

    // ---- adb ----

    function test_the_serial_comes_from_a_device_in_the_device_state() {
        const listing = "List of devices attached\nR58M12ABCDE\tdevice\n\n"
        compare(PhoneContacts.adbSerialFromDevices(listing), "R58M12ABCDE")
    }

    function test_a_usb_serial_wins_over_a_wireless_target() {
        const listing = "List of devices attached\n192.168.1.20:5555\tdevice\nR58M12ABCDE\tdevice\n"
        compare(PhoneContacts.adbSerialFromDevices(listing), "R58M12ABCDE")
        compare(PhoneContacts.adbSerialFromDevices("List of devices attached\n192.168.1.20:5555\tdevice\n"),
                "192.168.1.20:5555", "wireless is the answer when it is the only one")
    }

    function test_unauthorized_and_offline_devices_are_not_a_target() {
        const listing = "List of devices attached\nR58M12ABCDE\tunauthorized\n10.0.0.2:5555\toffline\n"
        compare(PhoneContacts.adbSerialFromDevices(listing), "")
        compare(PhoneContacts.adbSerialFromDevices(""), "")
        compare(PhoneContacts.adbSerialFromDevices("* daemon not running; starting now at tcp:5037\n* daemon started successfully\nList of devices attached\n"), "")
    }

    function test_a_tel_uri_keeps_the_dial_string_and_encodes_the_rest() {
        compare(PhoneContacts.intentUri("tel", "+1 (555) 010-0001"), "tel:+1(555)010-0001")
        compare(PhoneContacts.intentUri("sms", " 5550100002 "), "sms:5550100002")
        compare(PhoneContacts.intentUri("tel", "*100#"), "tel:*100%23", "a USSD code's # is a fragment marker unless encoded")
        compare(PhoneContacts.intentUri("tel", ""), "tel:")
        compare(PhoneContacts.intentUri("tel", null), "tel:")
    }

    function test_the_intent_argv_targets_the_serial_and_never_a_shell() {
        compare(PhoneContacts.intentArgv("R58M", "android.intent.action.DIAL", "tel:+15550100001"),
                ["adb", "-s", "R58M", "shell", "am", "start", "-a", "android.intent.action.DIAL", "-d", "tel:+15550100001"])
        compare(PhoneContacts.intentArgv("", "android.intent.action.SENDTO", "sms:5550100002"),
                ["adb", "shell", "am", "start", "-a", "android.intent.action.SENDTO", "-d", "sms:5550100002"])
    }

    // ---- the monitor ----

    function test_the_monitor_argv_names_the_device_only_when_there_is_one() {
        compare(PhoneContacts.monitorArgv("/s/contacts_monitor.py", "dev1"),
                ["python3", "/s/contacts_monitor.py", "--device", "dev1"])
        compare(PhoneContacts.monitorArgv("/s/contacts_monitor.py", ""),
                ["python3", "/s/contacts_monitor.py"])
    }

    function test_a_monitor_line_is_an_event_or_nothing() {
        compare(PhoneContacts.parseMonitorEvent('{"event": "ready", "sourcePath": "/x", "count": 3}').count, 3)
        compare(PhoneContacts.parseMonitorEvent("   "), null)
        compare(PhoneContacts.parseMonitorEvent("not json"), null)
        compare(PhoneContacts.parseMonitorEvent('{"count": 3}'), null, "no event name, no event")
        compare(PhoneContacts.parseMonitorEvent('[1, 2]'), null)
    }
}
