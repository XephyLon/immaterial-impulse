import QtQuick
import QtTest
import "../services/capture_control.js" as CaptureControl

// Behavioural tests for services/capture_control.js - the pure half of the
// privacy panel's actions: which argv gets run, and how the portal permission
// store's replies are read.
//
// Every command here ends up in a Process argv, so the tests that matter most
// are the ones that pin the REFUSALS: an id that is not a plain integer, or a
// portal app name carrying anything but the characters a bus name can hold,
// must come back null rather than reaching the command line. The privacy panel
// is fed by process names and D-Bus tables that other applications choose, so
// its inputs are not trusted.
TestCase {
    name: "CaptureControlTest"

    // --- Per-stream mute (pactl set-source-output-mute) ---

    function test_mute_command_is_argv_with_the_stream_index() {
        compare(CaptureControl.muteStreamCommand(262920, true),
            ["pactl", "set-source-output-mute", "262920", "1"]);
        compare(CaptureControl.muteStreamCommand("52", false),
            ["pactl", "set-source-output-mute", "52", "0"]);
    }

    function test_mute_command_refuses_anything_but_an_integer_index() {
        compare(CaptureControl.muteStreamCommand("52; rm -rf ~", true), null);
        compare(CaptureControl.muteStreamCommand("", true), null);
        compare(CaptureControl.muteStreamCommand(null, true), null);
        compare(CaptureControl.muteStreamCommand(-3, true), null);
        compare(CaptureControl.muteStreamCommand(1.5, true), null);
    }

    // --- Force stop (pw-cli destroy) ---

    function test_destroy_command_targets_the_pipewire_node_not_the_process() {
        // object.id is the node; object.serial (the pactl index) is not.
        compare(CaptureControl.destroyNodeCommand(282), ["pw-cli", "destroy", "282"]);
    }

    function test_destroy_command_refuses_a_non_integer_node() {
        compare(CaptureControl.destroyNodeCommand("282 && reboot"), null);
        compare(CaptureControl.destroyNodeCommand(undefined), null);
    }

    // --- Portal permission store ---

    function test_lookup_and_list_commands_address_the_permission_store() {
        var lookup = CaptureControl.permissionLookupCommand("devices", "microphone");
        compare(lookup[0], "busctl");
        compare(lookup.indexOf("--user") >= 0, true);
        compare(lookup[lookup.length - 4], "Lookup");
        compare(lookup[lookup.length - 3], "ss"); // the signature, before the args
        compare(lookup[lookup.length - 2], "devices");
        compare(lookup[lookup.length - 1], "microphone");

        var list = CaptureControl.permissionIdsCommand("devices");
        compare(list[list.length - 3], "List");
        compare(list[list.length - 2], "s");
        compare(list[list.length - 1], "devices");
    }

    function test_revoke_command_names_table_id_and_app() {
        var argv = CaptureControl.revokePermissionCommand("devices", "camera", "org.telegram.desktop");
        compare(argv[argv.length - 5], "DeletePermission");
        compare(argv[argv.length - 4], "sss");
        compare(argv[argv.length - 3], "devices");
        compare(argv[argv.length - 2], "camera");
        compare(argv[argv.length - 1], "org.telegram.desktop");
    }

    function test_revoke_refuses_names_outside_what_a_bus_name_can_hold() {
        compare(CaptureControl.revokePermissionCommand("devices", "camera", "org.x; reboot"), null);
        compare(CaptureControl.revokePermissionCommand("devices", "camera", ""), null);
        compare(CaptureControl.revokePermissionCommand("devices", "camera", "a b"), null);
        compare(CaptureControl.revokePermissionCommand("dev ices", "camera", "org.x"), null);
    }

    // --- Reading the store's replies (busctl --json=short) ---

    function test_lookup_reply_yields_one_entry_per_app() {
        // Shape verified live: data[0] is the app -> permissions map.
        var reply = '{"type":"a{sas}v","data":[{"org.example.One":["yes"],"org.example.Two":["no"]},{"type":"s","data":""}]}';
        var apps = CaptureControl.parsePermissionApps(reply);
        compare(apps.length, 2);
        compare(apps[0].app, "org.example.One");
        compare(apps[0].permissions, ["yes"]);
        compare(apps[0].granted, true);
        compare(apps[1].granted, false);
    }

    function test_a_table_with_no_entry_reads_as_empty_not_as_an_error() {
        // busctl exits non-zero with "No entry for microphone" when nothing has
        // ever been granted - the ordinary state on a machine with no
        // sandboxed apps, and not something to surface as a failure.
        compare(CaptureControl.parsePermissionApps("Call failed: No entry for microphone"), []);
        compare(CaptureControl.parsePermissionApps(""), []);
        compare(CaptureControl.parsePermissionApps(null), []);
    }

    function test_permission_ids_reply_is_unwrapped_one_level() {
        // List returns {"type":"as","data":[[...]]} - the ids are data[0].
        compare(CaptureControl.parsePermissionIds('{"type":"as","data":[["camera","microphone"]]}'),
            ["camera", "microphone"]);
        compare(CaptureControl.parsePermissionIds('{"type":"as","data":[[]]}'), []);
        compare(CaptureControl.parsePermissionIds("Call failed: whatever"), []);
    }
}
