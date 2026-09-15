import QtQuick
import qs.services
import ".."

/**
 * The VPN (`kind: vpn`, NetworkManager profiles) or Tailscale (`tailscale`)
 * is up, or down when `connected` is false.
 */
ModeCondition {
    id: root
    readonly property bool tailscale: root.params?.kind === "tailscale"
    readonly property bool wantConnected: root.params?.connected !== false

    readonly property bool available: root.tailscale ? Tailscale.available : (Vpn.enableService && (Vpn.connections?.length ?? 0) > 0)
    readonly property bool up: root.tailscale ? Tailscale.running : Vpn.anyActive

    satisfied: root.available && root.up === root.wantConnected
    reason: !root.available ? "not available"
        : (root.tailscale ? (root.up ? "tailscale" : "tailscale down")
        : (root.up ? ((Vpn.connections.find(c => c.active) ?? {}).name || "vpn") : "vpn down"))
}
