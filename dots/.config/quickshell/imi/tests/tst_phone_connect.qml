import QtQuick
import QtTest
import testservices

// Behavioral tests for the parsing/normalization logic of
// services/PhoneConnect.qml, exercised through the logic-only double in
// tests/imports/testservices. Fixtures follow real `busctl --json=short`
// replies captured from a live KDE Connect daemon (a paired, reachable phone
// and an unpaired desktop); the Valent fixtures encode the documented
// signatures (ObjectManager device export, org.gtk.Actions battery state)
// since no live Valent daemon was available.
TestCase {
    name: "PhoneConnectTest"

    function init() {
        PhoneConnect.installed = false
        PhoneConnect.backend = "none"
        PhoneConnect.devices = []
    }

    // ---- parseBusctlReply ----

    function test_parse_busctl_reply_unwraps_data() {
        const data = PhoneConnect.parseBusctlReply('{"type":"as","data":[["a","b"]]}')
        compare(data.length, 1)
        compare(data[0][1], "b")
    }

    function test_parse_busctl_reply_rejects_non_reply_output() {
        compare(PhoneConnect.parseBusctlReply(""), null)
        compare(PhoneConnect.parseBusctlReply("   \n"), null)
        compare(PhoneConnect.parseBusctlReply(null), null)
        compare(PhoneConnect.parseBusctlReply("Call failed: No such object path"), null)
        compare(PhoneConnect.parseBusctlReply('{"type":"as"}'), null)
        compare(PhoneConnect.parseBusctlReply('"just a string"'), null)
    }

    // ---- unwrapVariants ----

    function test_unwrap_variants_flattens_variant_cells() {
        const flat = PhoneConnect.unwrapVariants({
            "name": { "type": "s", "data": "Galaxy S23 Ultra" },
            "isPaired": { "type": "b", "data": true },
            "charge": { "type": "i", "data": 100 }
        })
        compare(flat.name, "Galaxy S23 Ultra")
        compare(flat.isPaired, true)
        compare(flat.charge, 100)
    }

    function test_unwrap_variants_tolerates_null_and_plain_values() {
        compare(JSON.stringify(PhoneConnect.unwrapVariants(null)), "{}")
        const flat = PhoneConnect.unwrapVariants({ "plain": 5 })
        compare(flat.plain, 5)
    }

    // ---- backendFromNames ----

    function test_backend_detection_kdeconnect() {
        compare(PhoneConnect.backendFromNames([":1.5", "org.kde.kdeconnect.daemon", "org.freedesktop.DBus"]), "kdeconnect")
    }

    function test_backend_detection_valent() {
        compare(PhoneConnect.backendFromNames(["ca.andyholmes.Valent", ":1.9"]), "valent")
    }

    function test_backend_detection_prefers_kdeconnect_when_both_own_names() {
        compare(PhoneConnect.backendFromNames(["ca.andyholmes.Valent", "org.kde.kdeconnect.daemon"]), "kdeconnect")
    }

    function test_backend_detection_none() {
        compare(PhoneConnect.backendFromNames([":1.5", "org.freedesktop.DBus"]), "none")
        compare(PhoneConnect.backendFromNames([]), "none")
        compare(PhoneConnect.backendFromNames(null), "none")
    }

    // ---- normalizeKdeconnectDevice ----

    function pairedPhoneProps() {
        // Captured shape: GetAll on org.kde.kdeconnect.device, variant cells intact.
        return {
            "name": { "type": "s", "data": "Galaxy S23 Ultra" },
            "type": { "type": "s", "data": "phone" },
            "isPaired": { "type": "b", "data": true },
            "isReachable": { "type": "b", "data": true },
            "isPairRequestedByPeer": { "type": "b", "data": false },
            "pairState": { "type": "i", "data": 3 },
            "reachableAddresses": { "type": "as", "data": ["192.168.100.179"] }
        }
    }

    // Captured shape: GetAll on org.kde.kdeconnect.device.connectivity_report
    // at the device's /connectivity_report leaf.
    function lteReport() {
        return {
            "cellularNetworkStrength": { "type": "i", "data": 4 },
            "cellularNetworkType": { "type": "s", "data": "LTE" },
            "iconName": { "type": "s", "data": "network-mobile-100-lte" }
        }
    }

    function test_normalize_kdeconnect_paired_phone_with_battery() {
        const device = PhoneConnect.normalizeKdeconnectDevice("6131a746", pairedPhoneProps(), {
            "charge": { "type": "i", "data": 100 },
            "isCharging": { "type": "b", "data": true }
        })
        compare(device.id, "6131a746")
        compare(device.name, "Galaxy S23 Ultra")
        compare(device.type, "phone")
        compare(device.paired, true)
        compare(device.reachable, true)
        compare(device.batteryAvailable, true)
        compare(device.batteryCharge, 100)
        compare(device.batteryCharging, true)
    }

    function test_normalize_kdeconnect_missing_battery_degrades_cleanly() {
        // The battery object does not exist for unpaired devices - GetAll
        // fails and the pipeline passes null through.
        const device = PhoneConnect.normalizeKdeconnectDevice("3b767a24", {
            "name": { "type": "s", "data": "rox-xbox-ally-x" },
            "type": { "type": "s", "data": "desktop" },
            "isPaired": { "type": "b", "data": false },
            "isReachable": { "type": "b", "data": true }
        }, null)
        compare(device.paired, false)
        compare(device.type, "desktop")
        compare(device.batteryAvailable, false)
        compare(device.batteryCharge, -1)
        compare(device.batteryCharging, false)
    }

    function test_normalize_kdeconnect_missing_props_default_safe() {
        const device = PhoneConnect.normalizeKdeconnectDevice("x", {}, null)
        compare(device.name, "")
        compare(device.type, "")
        compare(device.paired, false)
        compare(device.reachable, false)
    }

    // ---- connectivity_report and reachableAddresses (slice 2) ----

    function test_normalize_kdeconnect_reads_reachable_addresses_and_the_cellular_report() {
        const device = PhoneConnect.normalizeKdeconnectDevice("6131a746", pairedPhoneProps(), {
            "charge": { "type": "i", "data": 85 },
            "isCharging": { "type": "b", "data": false }
        }, lteReport())
        compare(device.reachableAddresses.length, 1)
        compare(device.reachableAddresses[0], "192.168.100.179")
        compare(device.cellularNetworkType, "LTE")
        compare(device.cellularNetworkStrength, 4)
    }

    function test_normalize_kdeconnect_missing_connectivity_report_degrades_cleanly() {
        // The leaf does not exist for an unpaired device, or where the plugin
        // is off - its GetAll fails, parses to null, and the model says
        // "unknown" rather than inventing a signal.
        const device = PhoneConnect.normalizeKdeconnectDevice("x", {}, null, null)
        compare(device.reachableAddresses.length, 0)
        compare(device.cellularNetworkType, "")
        compare(device.cellularNetworkStrength, -1)
        // A report with the wrong shapes in it is the same as none.
        const odd = PhoneConnect.normalizeKdeconnectDevice("x", {}, null, {
            "cellularNetworkStrength": { "type": "s", "data": "four" },
            "cellularNetworkType": { "type": "i", "data": 4 }
        })
        compare(odd.cellularNetworkType, "")
        compare(odd.cellularNetworkStrength, -1)
    }

    function test_normalize_kdeconnect_keeps_only_string_addresses() {
        const device = PhoneConnect.normalizeKdeconnectDevice("x", {
            "reachableAddresses": { "type": "as", "data": ["10.0.0.5", 7, null, "fe80::1"] }
        }, null, null)
        compare(device.reachableAddresses.join(","), "10.0.0.5,fe80::1")
        const scalar = PhoneConnect.normalizeKdeconnectDevice("x", {
            "reachableAddresses": { "type": "s", "data": "not-a-list" }
        }, null, null)
        compare(scalar.reachableAddresses.length, 0)
    }

    // ---- pairing requests (slice 3) ----

    function test_pairing_request_is_pair_state_requested_by_peer() {
        // Device::PairState: 0 NotPaired, 1 Requested (by us), 2
        // RequestedByPeer, 3 Paired. Only 2 is something to accept.
        const asked = PhoneConnect.normalizeKdeconnectDevice("x", {
            "pairState": { "type": "i", "data": 2 }
        }, null, null)
        compare(asked.hasPairingRequest, true)
        compare(PhoneConnect.normalizeKdeconnectDevice("x", pairedPhoneProps(), null, null).hasPairingRequest, false)
        compare(PhoneConnect.normalizeKdeconnectDevice("x", {
            "pairState": { "type": "i", "data": 1 }
        }, null, null).hasPairingRequest, false)
        compare(PhoneConnect.normalizeKdeconnectDevice("x", {}, null, null).hasPairingRequest, false)
    }

    function test_pairing_request_reads_the_bool_a_daemon_without_pair_state_exposes() {
        // isPairRequestedByPeer predates the pairState property; either
        // spelling of "the peer asked" counts.
        const asked = PhoneConnect.normalizeKdeconnectDevice("x", {
            "isPairRequestedByPeer": { "type": "b", "data": true }
        }, null, null)
        compare(asked.hasPairingRequest, true)
    }

    function test_pairing_requests_lists_the_devices_asking() {
        PhoneConnect.applyBackend("kdeconnect")
        PhoneConnect.applyDevices([
            device("phone1", { paired: true, reachable: true }),
            device("laptop", { type: "laptop", reachable: true, hasPairingRequest: true }),
            device("tablet", { type: "tablet", reachable: false })
        ])
        compare(PhoneConnect.pairingRequests.length, 1)
        compare(PhoneConnect.pairingRequests[0].id, "laptop")
        PhoneConnect.applyBackend("none")
        compare(PhoneConnect.pairingRequests.length, 0)
    }

    // ---- Valent ----

    function valentManagedObjects() {
        return [{
            "/ca/andyholmes/Valent/Device/0": {
                "ca.andyholmes.Valent.Device": {
                    "Id": { "type": "s", "data": "abc123" },
                    "Name": { "type": "s", "data": "Pixel 9" },
                    "Type": { "type": "s", "data": "phone" },
                    "State": { "type": "u", "data": 3 }
                },
                "org.gtk.Actions": {}
            },
            "/ca/andyholmes/Valent/Device/1": {
                "ca.andyholmes.Valent.Device": {
                    "Id": { "type": "s", "data": "def456" },
                    "Name": { "type": "s", "data": "Tablet" },
                    "Type": { "type": "s", "data": "tablet" },
                    "State": { "type": "u", "data": 2 }
                }
            },
            "/ca/andyholmes/Valent": {
                "org.freedesktop.DBus.ObjectManager": {}
            }
        }]
    }

    function test_normalize_valent_objects_decodes_state_flags() {
        const devices = PhoneConnect.normalizeValentObjects(valentManagedObjects())
        compare(devices.length, 2)
        const phone = devices.find(d => d.id === "abc123")
        compare(phone.name, "Pixel 9")
        compare(phone.type, "phone")
        compare(phone.reachable, true) // state bit 1 = connected
        compare(phone.paired, true) // state bit 2 = paired
        compare(phone.objectPath, "/ca/andyholmes/Valent/Device/0")
        const tablet = devices.find(d => d.id === "def456")
        compare(tablet.reachable, false)
        compare(tablet.paired, true)
    }

    function test_normalize_valent_objects_carry_the_kdeconnect_only_fields_empty() {
        // Valent's pairing and connectivity surfaces were not verifiable
        // against a live daemon; the model still has the fields so the UI
        // reads one shape, at the values that mean "unknown".
        const phone = PhoneConnect.normalizeValentObjects(valentManagedObjects()).find(d => d.id === "abc123")
        compare(phone.hasPairingRequest, false)
        compare(phone.reachableAddresses.length, 0)
        compare(phone.cellularNetworkType, "")
        compare(phone.cellularNetworkStrength, -1)
    }

    function test_normalize_valent_objects_ignores_non_device_paths() {
        const devices = PhoneConnect.normalizeValentObjects([{
            "/ca/andyholmes/Valent": { "org.freedesktop.DBus.ObjectManager": {} }
        }])
        compare(devices.length, 0)
        compare(PhoneConnect.normalizeValentObjects(null).length, 0)
    }

    function test_decode_valent_battery_state() {
        const battery = PhoneConnect.decodeValentBattery([{
            "battery.state": [true, "", [{
                "type": "a{sv}",
                "data": {
                    "charging": { "type": "b", "data": false },
                    "percentage": { "type": "d", "data": 85.0 },
                    "is-present": { "type": "b", "data": true }
                }
            }]],
            "findmyphone.ring": [true, "", []]
        }])
        compare(battery.available, true)
        compare(battery.charge, 85)
        compare(battery.charging, false)
    }

    function test_decode_valent_battery_absent_action_degrades() {
        const battery = PhoneConnect.decodeValentBattery([{ "findmyphone.ring": [true, "", []] }])
        compare(battery.available, false)
        compare(battery.charge, -1)
        compare(PhoneConnect.decodeValentBattery(null).available, false)
    }

    // ---- sorting / active device / state application ----

    function device(id, overrides) {
        return Object.assign({
            id: id, name: id, type: "phone", reachable: false, paired: false,
            hasPairingRequest: false, reachableAddresses: [],
            cellularNetworkType: "", cellularNetworkStrength: -1,
            batteryAvailable: false, batteryCharge: -1, batteryCharging: false
        }, overrides ?? {})
    }

    function test_sort_devices_reachable_paired_first_then_name() {
        const sorted = PhoneConnect.sortDevices([
            device("c", { paired: true, reachable: false }),
            device("b", { paired: true, reachable: true }),
            device("a", { paired: false, reachable: true }),
            device("d", { paired: true, reachable: true })
        ])
        compare(sorted.map(d => d.id).join(","), "b,d,c,a")
    }

    function test_active_device_prefers_reachable_paired_phone() {
        PhoneConnect.applyBackend("kdeconnect")
        PhoneConnect.applyDevices([
            device("laptop", { type: "laptop", paired: true, reachable: true, name: "aaa" }),
            device("phone1", { type: "phone", paired: true, reachable: true, name: "zzz" })
        ])
        compare(PhoneConnect.activeDevice.id, "phone1")
        compare(PhoneConnect.materialSymbol, "mobile")
    }

    function test_active_device_falls_back_to_any_reachable_paired() {
        PhoneConnect.applyBackend("kdeconnect")
        PhoneConnect.applyDevices([
            device("laptop", { type: "laptop", paired: true, reachable: true }),
            device("phone1", { type: "phone", paired: true, reachable: false })
        ])
        compare(PhoneConnect.activeDevice.id, "laptop")
    }

    function test_no_backend_resets_to_clean_degraded_state() {
        PhoneConnect.applyBackend("kdeconnect")
        PhoneConnect.applyDevices([device("phone1", { paired: true, reachable: true })])
        compare(PhoneConnect.available, true)
        PhoneConnect.applyBackend("none")
        compare(PhoneConnect.available, false)
        compare(PhoneConnect.devices.length, 0)
        compare(PhoneConnect.activeDevice, null)
        compare(PhoneConnect.materialSymbol, "mobile_off")
    }

    function test_unreachable_only_devices_yield_no_active_device() {
        PhoneConnect.applyBackend("kdeconnect")
        PhoneConnect.applyDevices([device("phone1", { paired: true, reachable: false })])
        compare(PhoneConnect.activeDevice, null)
        compare(PhoneConnect.materialSymbol, "mobile_off")
    }

    // ---- monitor match rule ----

    function test_monitor_match_rule_narrows_at_the_bus() {
        // busctl reports a signal's sender as the unique name it arrived on
        // (":1.55" in the capture these fixtures come from), so the rule is
        // the only place the daemon can be named.
        const rule = PhoneConnect.monitorMatchRule("kdeconnect")
        verify(rule.includes("type='signal'"))
        verify(rule.includes("sender='org.kde.kdeconnect.daemon'"))
        verify(rule.includes("path_namespace='/modules/kdeconnect'"))
    }

    function test_monitor_match_rule_is_empty_for_unverified_backends() {
        // Valent has no rule because no live Valent daemon was reachable to
        // verify its signal set against; an empty rule keeps it on the poll.
        compare(PhoneConnect.monitorMatchRule("valent"), "")
        compare(PhoneConnect.monitorMatchRule("none"), "")
        compare(PhoneConnect.monitorMatchRule(""), "")
    }

    // ---- parseMonitorLine ----
    //
    // Every fixture below is a line captured verbatim from
    // `busctl --user --json=short monitor` against the live KDE Connect
    // daemon on the development machine, with the device id left as it came.

    readonly property string reachableLine: '{"type":"signal","endian":"l","flags":1,"version":1,"cookie":325,"timestamp-realtime":1787149977815500,"sender":":1.55","path":"/modules/kdeconnect/devices/3b767a2479954eceaf9f1e7fa212f48e","interface":"org.kde.kdeconnect.device","member":"reachableChanged","payload":{"type":"b","data":[false]}}'
    readonly property string deviceAddedLine: '{"type":"signal","endian":"l","flags":1,"version":1,"cookie":326,"timestamp-realtime":1787149977815282,"sender":":1.55","path":"/modules/kdeconnect","interface":"org.kde.kdeconnect.daemon","member":"deviceAdded","payload":{"type":"s","data":["3b767a2479954eceaf9f1e7fa212f48e"]}}'
    readonly property string methodCallLine: '{"type":"method_call","endian":"l","flags":0,"version":1,"cookie":2,"timestamp-realtime":1787149465537256,"sender":":1.18439","destination":"org.kde.kdeconnect.daemon","path":"/modules/kdeconnect","interface":"org.kde.kdeconnect.daemon","member":"devices","payload":{"type":"","data":[]}}'

    function test_parse_monitor_line_reads_a_real_signal() {
        const signal = PhoneConnect.parseMonitorLine(reachableLine)
        compare(signal.path, "/modules/kdeconnect/devices/3b767a2479954eceaf9f1e7fa212f48e")
        compare(signal.iface, "org.kde.kdeconnect.device")
        compare(signal.member, "reachableChanged")
        compare(signal.args[0], false)
    }

    function test_parse_monitor_line_rejects_everything_that_is_not_a_signal() {
        // A monitor sees the whole conversation, calls and returns included.
        compare(PhoneConnect.parseMonitorLine(methodCallLine), null)
        compare(PhoneConnect.parseMonitorLine(""), null)
        compare(PhoneConnect.parseMonitorLine("   \n"), null)
        compare(PhoneConnect.parseMonitorLine(null), null)
        compare(PhoneConnect.parseMonitorLine("Failed to become monitor: Invalid match rule"), null)
        compare(PhoneConnect.parseMonitorLine('{"type":"signal"'), null)
        compare(PhoneConnect.parseMonitorLine('"just a string"'), null)
    }

    // ---- signalChangesDevices ----

    function test_signal_changes_devices_accepts_the_verified_event_set() {
        verify(PhoneConnect.signalChangesDevices(PhoneConnect.parseMonitorLine(reachableLine)))
        verify(PhoneConnect.signalChangesDevices(PhoneConnect.parseMonitorLine(deviceAddedLine)))
        for (const member of ["deviceRemoved", "deviceListChanged", "deviceVisibilityChanged",
                              "pairingRequestsChanged"])
            verify(PhoneConnect.signalChangesDevices({ iface: "org.kde.kdeconnect.daemon", member: member, args: [] }),
                   `daemon.${member} should re-read`)
        for (const member of ["pairStateChanged", "nameChanged", "typeChanged", "pluginsChanged"])
            verify(PhoneConnect.signalChangesDevices({ iface: "org.kde.kdeconnect.device", member: member, args: [] }),
                   `device.${member} should re-read`)
        verify(PhoneConnect.signalChangesDevices({ iface: "org.kde.kdeconnect.device.battery", member: "refreshed", args: [true, 87] }))
        // connectivity_report.refreshed(si) - the cellular type and strength.
        verify(PhoneConnect.signalChangesDevices({ iface: "org.kde.kdeconnect.device.connectivity_report", member: "refreshed", args: ["LTE", 4] }))
    }

    function test_signal_changes_devices_reads_the_interface_out_of_properties_changed() {
        verify(PhoneConnect.signalChangesDevices({
            iface: "org.freedesktop.DBus.Properties", member: "PropertiesChanged",
            args: ["org.kde.kdeconnect.device.battery", { "charge": 41 }, []]
        }))
        verify(!PhoneConnect.signalChangesDevices({
            iface: "org.freedesktop.DBus.Properties", member: "PropertiesChanged",
            args: ["org.freedesktop.UPower.Device", {}, []]
        }))
        verify(!PhoneConnect.signalChangesDevices({
            iface: "org.freedesktop.DBus.Properties", member: "PropertiesChanged", args: []
        }))
    }

    function test_signal_changes_devices_ignores_traffic_the_model_does_not_hold() {
        // Both fire in the same burst as reachableChanged on a real daemon,
        // and the SMS plugin's are the reason this is an allowlist: they
        // share the device path and would re-read every device per message.
        verify(!PhoneConnect.signalChangesDevices({ iface: "org.kde.kdeconnect.device", member: "linksChanged", args: [] }))
        verify(!PhoneConnect.signalChangesDevices({ iface: "org.kde.kdeconnect.device", member: "statusIconNameChanged", args: [] }))
        verify(!PhoneConnect.signalChangesDevices({ iface: "org.kde.kdeconnect.device.conversations", member: "conversationUpdated", args: [] }))
        verify(!PhoneConnect.signalChangesDevices({ iface: "org.freedesktop.DBus", member: "NameOwnerChanged", args: [] }))
        verify(!PhoneConnect.signalChangesDevices(null))
    }

    // ---- restart plan ----

    function test_monitor_backoff_delay_doubles_and_caps() {
        compare(PhoneConnect.monitorBackoffDelay(1), 1000)
        compare(PhoneConnect.monitorBackoffDelay(2), 2000)
        compare(PhoneConnect.monitorBackoffDelay(3), 4000)
        compare(PhoneConnect.monitorBackoffDelay(4), 8000)
        compare(PhoneConnect.monitorBackoffDelay(5), 16000)
        compare(PhoneConnect.monitorBackoffDelay(6), 30000)
        compare(PhoneConnect.monitorBackoffDelay(40), 30000)
        // A caller that has not counted yet still waits a full rung, never 0.
        compare(PhoneConnect.monitorBackoffDelay(0), 1000)
        compare(PhoneConnect.monitorBackoffDelay(-3), 1000)
    }

    function test_monitor_exit_plan_backs_off_a_fast_exit() {
        // busctl handed a rule the bus rejects exits in milliseconds; this is
        // the case an unguarded `running` binding turns into a respawn loop.
        const first = PhoneConnect.monitorExitPlan(0, 40, true, 30000, 5)
        compare(first.retry, true)
        compare(first.attempts, 1)
        compare(first.delay, 1000)
        const second = PhoneConnect.monitorExitPlan(1, 40, true, 30000, 5)
        compare(second.attempts, 2)
        compare(second.delay, 2000)
    }

    function test_monitor_exit_plan_stops_at_the_ceiling() {
        const capped = PhoneConnect.monitorExitPlan(5, 40, true, 30000, 5)
        compare(capped.retry, false)
        compare(capped.delay, 0)
        compare(capped.attempts, 5)
    }

    function test_monitor_exit_plan_resets_after_a_healthy_run() {
        // Otherwise one daemon restart in a day-long session spends the
        // ceiling and the shell never streams again.
        const healthy = PhoneConnect.monitorExitPlan(4, 30000, true, 30000, 5)
        compare(healthy.retry, true)
        compare(healthy.attempts, 1)
        compare(healthy.delay, 1000)
        // ...including from the ceiling itself.
        const recovered = PhoneConnect.monitorExitPlan(5, 120000, true, 30000, 5)
        compare(recovered.retry, true)
        compare(recovered.attempts, 1)
    }

    function test_monitor_exit_plan_does_not_restart_what_nobody_wants() {
        const unwanted = PhoneConnect.monitorExitPlan(0, 40, false, 30000, 5)
        compare(unwanted.retry, false)
        compare(unwanted.delay, 0)
        // A deliberate stop after a healthy run leaves no debt behind.
        compare(PhoneConnect.monitorExitPlan(3, 90000, false, 30000, 5).attempts, 0)
    }

    // ---- device id guard ----

    function test_valid_device_id_accepts_kdeconnect_and_valent_ids() {
        compare(PhoneConnect.validDeviceId("6131a746_571a_4176_a007_95625ff8e08e"), true)
        compare(PhoneConnect.validDeviceId("3b767a2479954eceaf9f1e7fa212f48e"), true)
        compare(PhoneConnect.validDeviceId("abc-123"), true)
    }

    function test_valid_device_id_rejects_path_and_shell_metacharacters() {
        compare(PhoneConnect.validDeviceId("../../etc"), false)
        compare(PhoneConnect.validDeviceId("a/b"), false)
        compare(PhoneConnect.validDeviceId("a b"), false)
        compare(PhoneConnect.validDeviceId(""), false)
        compare(PhoneConnect.validDeviceId(null), false)
    }
}
