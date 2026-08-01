import QtQuick
import QtTest
import testservices

// Behavioral tests for the parsing/state logic of services/Vpn.qml, exercised
// through the logic-only `Vpn` double in tests/imports/testservices. These pin
// the nmcli `-t -f NAME,TYPE,ACTIVE con show` parsing, including the command
// injection surface: names with spaces, quotes and shell metacharacters must
// survive untouched (the service never splices them into a shell string).
TestCase {
    name: "VpnTest"

    function init() {
        Vpn.connections = []
    }

    function test_empty_output_yields_no_connections() {
        compare(Vpn.parseConnections("").length, 0)
        compare(Vpn.parseConnections("   \n  ").length, 0)
        compare(Vpn.parseConnections(null).length, 0)
    }

    function test_filters_to_vpn_and_wireguard_types_only() {
        var text = [
            "Wired connection 1:802-3-ethernet:yes",
            "MyOffice:vpn:yes",
            "wg-home:wireguard:no",
            "Home Wifi:802-11-wireless:yes",
            "docker0:bridge:yes"
        ].join("\n")
        var conns = Vpn.parseConnections(text)
        compare(conns.length, 2)
        compare(conns[0].name, "MyOffice")
        compare(conns[0].active, true)
        compare(conns[1].name, "wg-home")
        compare(conns[1].active, false)
    }

    function test_names_with_spaces_and_metacharacters_survive() {
        // Command-injection surface: nothing here should be interpreted; the
        // whole string must come back verbatim as the connection NAME.
        var name = "Work VPN; rm -rf $HOME `whoami`"
        var conns = Vpn.parseConnections(name + ":vpn:yes")
        compare(conns.length, 1)
        compare(conns[0].name, name)
        compare(conns[0].active, true)
    }

    function test_escaped_colons_in_name_are_unescaped() {
        // nmcli -t escapes literal colons in NAME as "\:".
        var conns = Vpn.parseConnections("Prod\\:EU\\:1:vpn:yes")
        compare(conns.length, 1)
        compare(conns[0].name, "Prod:EU:1")
    }

    function test_derived_state_tracks_connections() {
        compare(Vpn.anyActive, false)
        compare(Vpn.materialSymbol, "vpn_key")
        compare(Vpn.activeConnections.length, 0)

        Vpn.connections = [
            { name: "A", active: false },
            { name: "B", active: true }
        ]
        compare(Vpn.anyActive, true)
        compare(Vpn.materialSymbol, "vpn_lock")
        compare(Vpn.activeConnections.length, 1)
        compare(Vpn.activeConnections[0].name, "B")
    }
}
