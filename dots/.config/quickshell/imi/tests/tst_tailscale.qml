import QtQuick
import QtTest
import testservices

// Behavioral tests for the parsing/state logic of services/Tailscale.qml,
// exercised through the logic-only `Tailscale` double in
// tests/imports/testservices. These pin the `tailscale status --json` parsing:
// exit-node peer filtering, IPv4 preference for `--exit-node=`, online-first
// sorting, and active-node detection via both ExitNodeStatus.ID and the
// per-peer ExitNode flag.
TestCase {
    name: "TailscaleTest"

    function init() {
        Tailscale.installed = false
        Tailscale.available = false
        Tailscale.running = false
        Tailscale.backendState = ""
        Tailscale.currentExitNodeId = ""
        Tailscale.exitNodes = []
    }

    function makeStatus(overrides) {
        const base = {
            BackendState: "Running",
            Self: { ID: "n0", HostName: "laptop", TailscaleIPs: ["100.64.0.1", "fd7a::1"] },
            Peer: {}
        }
        return JSON.stringify(Object.assign(base, overrides ?? {}))
    }

    function test_non_status_output_yields_null() {
        compare(Tailscale.parseStatus(""), null)
        compare(Tailscale.parseStatus("   \n  "), null)
        compare(Tailscale.parseStatus(null), null)
        compare(Tailscale.parseStatus("failed to connect to local tailscaled"), null)
        compare(Tailscale.parseStatus("[1, 2, 3]") !== null, true) // arrays are objects; still parse (no peers)
    }

    function test_daemon_down_resets_state() {
        Tailscale.available = true
        Tailscale.running = true
        Tailscale.currentExitNodeId = "n1"
        Tailscale.exitNodes = [{ id: "n1", name: "a", ip: "100.64.0.2", online: true, active: true }]
        Tailscale.applyStatus("")
        compare(Tailscale.available, false)
        compare(Tailscale.running, false)
        compare(Tailscale.exitNodeActive, false)
        compare(Tailscale.exitNodes.length, 0)
    }

    function test_stopped_backend_is_available_but_not_running() {
        Tailscale.applyStatus(makeStatus({ BackendState: "Stopped" }))
        compare(Tailscale.available, true)
        compare(Tailscale.running, false)
        compare(Tailscale.backendState, "Stopped")
        compare(Tailscale.materialSymbol, "vpn_key_off")
    }

    function test_filters_to_exit_node_option_peers_only() {
        const status = makeStatus({
            Peer: {
                "nodekey:aa": { ID: "n1", HostName: "plain-peer", TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: false },
                "nodekey:bb": { ID: "n2", HostName: "exit-a", TailscaleIPs: ["100.64.0.3"], Online: true, ExitNodeOption: true },
                "nodekey:cc": { ID: "n3", HostName: "no-flag-at-all", TailscaleIPs: ["100.64.0.4"], Online: true }
            }
        })
        const parsed = Tailscale.parseStatus(status)
        compare(parsed.exitNodes.length, 1)
        compare(parsed.exitNodes[0].name, "exit-a")
        compare(parsed.running, true)
    }

    function test_prefers_ipv4_address() {
        compare(Tailscale.firstIpv4(["fd7a::2/128", "100.64.0.9/32"]), "100.64.0.9")
        compare(Tailscale.firstIpv4(["100.64.0.9"]), "100.64.0.9")
        compare(Tailscale.firstIpv4(["fd7a::2/128"]), "fd7a::2")
        compare(Tailscale.firstIpv4([]), "")
        compare(Tailscale.firstIpv4(null), "")
    }

    function test_sorts_online_first_then_alphabetical() {
        const status = makeStatus({
            Peer: {
                "nodekey:aa": { ID: "n1", HostName: "zeta", TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: true },
                "nodekey:bb": { ID: "n2", HostName: "alpha", TailscaleIPs: ["100.64.0.3"], Online: false, ExitNodeOption: true },
                "nodekey:cc": { ID: "n3", HostName: "beta", TailscaleIPs: ["100.64.0.4"], Online: true, ExitNodeOption: true }
            }
        })
        const names = Tailscale.parseStatus(status).exitNodes.map(n => n.name)
        compare(names.length, 3)
        compare(names[0], "beta")
        compare(names[1], "zeta")
        compare(names[2], "alpha")
    }

    function test_active_node_via_exit_node_status_id() {
        const status = makeStatus({
            ExitNodeStatus: { ID: "n2", Online: true },
            Peer: {
                "nodekey:aa": { ID: "n1", HostName: "a", TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: true },
                "nodekey:bb": { ID: "n2", HostName: "b", TailscaleIPs: ["100.64.0.3"], Online: true, ExitNodeOption: true }
            }
        })
        Tailscale.applyStatus(status)
        compare(Tailscale.currentExitNodeId, "n2")
        compare(Tailscale.exitNodeActive, true)
        compare(Tailscale.currentExitNodeName, "b")
        compare(Tailscale.materialSymbol, "vpn_lock")
    }

    function test_active_node_via_peer_exit_node_flag() {
        const status = makeStatus({
            Peer: {
                "nodekey:aa": { ID: "n1", HostName: "a", TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: true, ExitNode: true }
            }
        })
        Tailscale.applyStatus(status)
        compare(Tailscale.currentExitNodeId, "n1")
        compare(Tailscale.exitNodeActive, true)
        compare(Tailscale.currentExitNodeName, "a")
    }

    function test_no_exit_node_selected() {
        const status = makeStatus({
            Peer: {
                "nodekey:aa": { ID: "n1", HostName: "a", TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: true }
            }
        })
        Tailscale.applyStatus(status)
        compare(Tailscale.currentExitNodeId, "")
        compare(Tailscale.exitNodeActive, false)
        compare(Tailscale.currentExitNodeName, "")
        compare(Tailscale.materialSymbol, "vpn_key")
    }

    function test_hostname_falls_back_to_dns_name() {
        const status = makeStatus({
            Peer: {
                "nodekey:aa": { ID: "n1", HostName: "", DNSName: "exitbox.tailnet.ts.net.", TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: true }
            }
        })
        const parsed = Tailscale.parseStatus(status)
        compare(parsed.exitNodes[0].name, "exitbox")
    }
}
