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
            "isPairRequestedByPeer": { "type": "b", "data": false }
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
