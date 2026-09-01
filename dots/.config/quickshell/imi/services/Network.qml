pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    // An access point destroyed during a rescan reads back as null until the
    // list settles, so every consumer of wifiNetworks has to tolerate holes.
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n?.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].filter(n => n).sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength
    property string networkInterface: ""
    property string ipAddress: ""
    property string publicIpAddress: ""
    property string gateway: ""
    property string macAddress: ""
    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? (
                (root.active?.strength ?? 0) > 83 ? "signal_wifi_4_bar" :
                (root.active?.strength ?? 0) > 67 ? "network_wifi" :
                (root.active?.strength ?? 0) > 50 ? "network_wifi_3_bar" :
                (root.active?.strength ?? 0) > 33 ? "network_wifi_2_bar" :
                (root.active?.strength ?? 0) > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])

    }

    function disconnectWifiNetwork(): void {
        if (active) disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            "command": ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        })
    }

    Process {
        id: enableWifiProc
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required")) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false
            connectProc.running = true
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: SplitParser {
            onRead: {
                wifiScanning = false;
                getNetworks.running = true;
            }
        }
        // A failed rescan (radio off, nmcli error) produces no stdout, which
        // would leave wifiScanning stuck at true and the rescan button
        // permanently disabled. Always clear the flag when the process ends.
        onExited: (exitCode, exitStatus) => {
            root.wifiScanning = false;
        }
    }

    // Status update
    function update() {
        updateConnectionType.startCheck();
        wifiStatusProcess.running = true
        updateNetworkName.running = true;
        updateNetworkStrength.running = true;
        updateNetworkDetails.running = true;
        updatePublicIp.running = true;
    }

    // One NetworkManager event feed for the whole shell. Vpn refreshes off
    // this signal instead of running a second `nmcli monitor` of its own -
    // measured before the change: two monitors per shell instance, and every
    // dead instance left both behind (30 orphans reaped from 15 restarts,
    // all reparented to init and sleeping until the next network event).
    signal monitorEvent()

    // Orphan reaper: `nmcli monitor` writes only on network events, so an
    // instance orphaned by a hard shell kill (SIGKILL, crash) sleeps forever
    // instead of hitting SIGPIPE - and every such death left one behind (322
    // found once, ~500 MiB). The old fix wrapped nmcli in a bash watchdog,
    // but that made nmcli a GRANDCHILD, and a SIGKILL skips bash's EXIT trap
    // and orphans it anyway. Two moves instead: run nmcli as a DIRECT child
    // (quickshell tears its own children down on a clean exit), and on every
    // start reap any `nmcli monitor` already reparented to init (ppid 1) -
    // which is exactly a previous instance's leak, never this one's (ours is
    // a child of the qs process). pkill exits 1 when it finds none; harmless.
    Process {
        running: true
        command: ["pkill", "-P", "1", "-x", "nmcli"]
    }

    Process {
        id: subscriber
        running: true
        // Direct child, no bash wrapper - the grandchild the wrapper created
        // was the leak. quickshell sends this SIGTERM on teardown.
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: {
                root.update();
                root.monitorEvent();
            }
        }
    }

    Process {
        id: updateConnectionType
        property string buffer
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        function startCheck() {
            buffer = "";
            updateConnectionType.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                updateConnectionType.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const lines = updateConnectionType.buffer.trim().split('\n');
            const connectivity = lines.pop() // none, limited, full
            let hasEthernet = false;
            let hasWifi = false;
            let wifiStatus = "disconnected";
            lines.forEach(line => {
                if (line.includes("ethernet") && line.includes("connected"))
                    hasEthernet = true;
                else if (line.includes("wifi:")) {
                    if (line.includes("disconnected")) {
                        wifiStatus = "disconnected"
                    }
                    else if (line.includes("connected")) {
                        hasWifi = true;
                        wifiStatus = "connected"

                        if (connectivity === "limited") {
                            hasWifi = false;
                            wifiStatus = "limited"
                        }
                    }
                    else if (line.includes("connecting")) {
                        wifiStatus = "connecting"
                    }
                    else if (line.includes("unavailable")) {
                        wifiStatus = "disabled"
                    }
                }
            });
            root.wifiStatus = wifiStatus;
            root.ethernet = hasEthernet;
            root.wifi = hasWifi;
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.networkName = data;
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        stdout: SplitParser {
            onRead: data => {
                root.networkStrength = parseInt(data);
            }
        }
    }

    Process {
        id: updateNetworkDetails
        running: true
        command: ["sh", "-c", "device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$3 == \"connected\" && $2 ~ /^(wifi|ethernet)$/ { print $1; exit }'); if [ -n \"$device\" ]; then nmcli -t -f GENERAL.DEVICE,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY device show \"$device\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let networkInterface = "";
                let ipAddress = "";
                let gateway = "";
                let macAddress = "";

                for (const line of text.trim().split("\n")) {
                    const separator = line.indexOf(":");
                    if (separator < 0) continue;

                    const key = line.slice(0, separator);
                    const value = line.slice(separator + 1);
                    if (key === "GENERAL.DEVICE")
                        networkInterface = value;
                    else if (key === "GENERAL.HWADDR")
                        macAddress = value;
                    else if (key.startsWith("IP4.ADDRESS") && ipAddress === "")
                        ipAddress = value.split("/")[0];
                    else if (key === "IP4.GATEWAY")
                        gateway = value;
                }

                root.networkInterface = networkInterface;
                root.ipAddress = ipAddress;
                root.gateway = gateway;
                root.macAddress = macAddress;
            }
        }
    }

    Process {
        id: updatePublicIp
        running: true
        command: ["curl", "-fsS", "--max-time", "5", "https://api.ipify.org"]
        stdout: StdioCollector {
            onStreamFinished: {
                const candidate = text.trim();
                root.publicIpAddress = /^[0-9a-fA-F:.]+$/.test(candidate)
                    ? candidate
                    : "";
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        Component.onCompleted: running = true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = text.trim() === "enabled";
            }
        }
    }

    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3],
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                // Walk backwards and splice by index. indexOf() returns -1 for an
                // entry that already went away, and splice(-1, 1) then drops the
                // last access point instead, leaving the stale one in the list to
                // read back as null once it is destroyed.
                for (let i = rNetworks.length - 1; i >= 0; --i) {
                    const existing = rNetworks[i];
                    if (existing && wifiNetworks.find(n => n.frequency === existing.frequency
                        && n.ssid === existing.ssid && n.bssid === existing.bssid)) continue;
                    rNetworks.splice(i, 1);
                    if (existing) existing.destroy();
                }

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n && n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
