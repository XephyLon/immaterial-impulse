#!/bin/bash
# Drives the Bluetooth battery bar widget in a nested Hyprland with the
# connected-device list FAKED, because nothing else can put a ring on it: the
# widget draws only for a Bluetooth-connected device with a battery level, and
# a test machine has none. A COPY of this tree gets BluetoothStatus's
# connectedDevices replaced by four plain objects - buds and a low mouse
# through the Battery1 path, a controller through the UPower fallback (a
# DualSense on USB shows up in UPower with its MAC, so on a machine that has
# one the fallback is the REAL one), a keyboard with no report - plus a probe
# IpcHandler patched into the widget. Then, on the nested compositor's own
# signature: the widget's geometry and ring types under Float and M3, a hover
# (movecursor onto the widget, the popup's popupVisible flips), and the click
# (the sidebar's showBluetoothDialog flips).
#
# Measured when it landed (1280x720, Float): 96x50 with three OUTLINE rings,
# the 12% mouse in the error colour, the controller at UPower's 100%; M3 swaps
# them for FILLED rings; vertical draws a 56x72 column; hover opens the popup
# with five children under deviceCards (the Repeater and four cards); the
# click opens the dialog. No WARN names the widget's files.
#
# Same shape as run_bar_exclusive_zone_probe.sh: own D-Bus session, own XDG
# dirs, SHORT runtime dir (a long one makes Hyprland's socket path too long
# and "IPC will not work"), nested signature exported before any hyprctl.
#
# Usage: tests/run_bluetooth_battery_probe.sh [cornerStyle] [vertical]
#        tests/run_bluetooth_battery_probe.sh 1 false
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
for binary in Hyprland qs dbus-run-session python3 rsync; do
    command -v "$binary" >/dev/null 2>&1 || { echo "SKIPPED: $binary not on PATH"; exit 0; }
done
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "SKIPPED: no WAYLAND_DISPLAY - the nested compositor needs a parent"
    exit 0
fi
STYLE="${1:-1}"; VERT="${2:-false}"
PARENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
TMP=$(mktemp -d /tmp/btp.XXXX)
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
echo "TMP=$TMP"
mkdir -p "$TMP/imi"; rsync -a --exclude tests "$SRC/" "$TMP/imi/"
COPY="$TMP/imi"
python3 - "$COPY" <<'PY'
import sys, re
from pathlib import Path
c = Path(sys.argv[1])
s = (c/"services/BluetoothStatus.qml").read_text()
old = "    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)\n"
new = '''    property list<var> connectedDevices: [
        { name: "Pixel Buds", icon: "audio-headset", address: "", batteryAvailable: true, battery: 0.72 },
        { name: "MX Anywhere", icon: "input-mouse", address: "", batteryAvailable: true, battery: 0.12 },
        { name: "DualSense Edge", icon: "input-gaming", address: "14:3A:9A:7C:45:47", batteryAvailable: false },
        { name: "Keychron", icon: "input-keyboard", address: "AA:BB:CC:DD:EE:FF", batteryAvailable: false }
    ]
'''
assert old in s; (c/"services/BluetoothStatus.qml").write_text(s.replace(old, new, 1))
w = (c/"modules/imi/bar/BluetoothBattery.qml").read_text()
probe = '''
    IpcHandler {
        target: "btprobe"
        function geom(): string {
            const p = root.mapToItem(null, 0, 0);
            const loader = root.vertical ? colLoader : rowLoader;
            const rings = loader.item ? Array.from(loader.item.children).filter(c => c && c.item).map(c =>
                `${c.item.toString().split("(")[0]} level=${c.item.level.toFixed(2)} low=${c.item.low} col=${c.item.colPrimary} size=${c.item.width}x${c.item.height}`) : [];
            return JSON.stringify({ x: p.x, y: p.y, w: root.width, h: root.height, implicitWidth: root.implicitWidth,
                implicitHeight: root.implicitHeight, populated: root.populated, visible: root.visible,
                devices: root.devices.map(d => d.name), rings: rings, style: Config.options.bar.cornerStyle });
        }
        function click(): string { root.clicked(null); return "clicked"; }
        function style(n: int): string { Config.options.bar.cornerStyle = n; return "style " + n; }
    }
    Component.onCompleted: console.log("BTPROBE widget completed populated=" + root.populated)
'''
w = w.rstrip()[:-1] + probe + "}\n"
w = w.replace("import QtQuick.Layouts\n", "import QtQuick.Layouts\nimport Quickshell.Io\n", 1)
(c/"modules/imi/bar/BluetoothBattery.qml").write_text(w)
p = (c/"modules/imi/bar/BluetoothBatteryPopup.qml").read_text()
p = p.replace("    readonly property var lowest: BluetoothStatus.lowestBatteryDevice\n",
              "    readonly property var lowest: BluetoothStatus.lowestBatteryDevice\n    onPopupVisibleChanged: console.log(\"BTPROBE popup visible=\" + popupVisible + \" lowest=\" + (lowest ? lowest.name : \"none\") + \" cards=\" + deviceCards.children.length)\n", 1)
(c/"modules/imi/bar/BluetoothBatteryPopup.qml").write_text(p)
sb = (c/"modules/imi/sidebarRight/SidebarRightContent.qml").read_text()
sb = sb.replace("    function consumeDialogRequest() {\n", "    onShowBluetoothDialogChanged: console.log(\"BTPROBE sidebar showBluetoothDialog=\" + showBluetoothDialog)\n    function consumeDialogRequest() {\n", 1)
(c/"modules/imi/sidebarRight/SidebarRightContent.qml").write_text(sb)
print("patched")
PY
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME/immaterial-impulse" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$TMP/run"
cat > "$XDG_CONFIG_HOME/immaterial-impulse/config.json" <<JSON
{"bar":{"cornerStyle":$STYLE,"vertical":$VERT,"layouts":{"leftLayout":["bluetoothBattery","activeWindow"],"middleLayout":["workspaces","clockWidget"],"rightLayout":["systemIcons"]}},"policies":{"ai":0,"weeb":0}}
JSON
cat > "$TMP/hypr.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x720@60", position = "auto", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0, disable_autoreload = true }, animations = { enabled = false } })
LUA
export XDG_RUNTIME_DIR="$TMP/run"; export WAYLAND_DISPLAY="$PARENT_SOCKET"
dbus-run-session -- bash -s "$TMP" "$COPY" <<'NESTED'
set -u
TMP="$1"; COPY="$2"
Hyprland -c "$TMP/hypr.lua" > "$TMP/hypr.log" 2>&1 &
HPID=$!
SIG=""
for _ in $(seq 1 60); do sleep 0.5; SIG=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); [ -n "$SIG" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ] && break; SIG=""; done
[ -z "$SIG" ] && { echo "FAILED: nested compositor"; tail -5 "$TMP/hypr.log"; kill $HPID; exit 1; }
export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
echo "nested: sig=$SIG display=$WAYLAND_DISPLAY"
cd "$COPY"
qs -p "$COPY/shell.qml" > "$TMP/shell.log" 2>&1 &
QPID=$!
for _ in $(seq 1 40); do sleep 0.5; grep -q "BTPROBE widget completed" "$TMP/shell.log" && break; done
sleep 3
echo "--- bar layer ---"; hyprctl layers -j | python3 -c "
import json,sys
for m,v in json.load(sys.stdin).items():
    for lvl,ls in v['levels'].items():
        for l in ls:
            if 'bar' in l['namespace']: print(' ', l['namespace'], l['x'], l['y'], l['w'], l['h'])"
echo "--- geom ---"; G=$(qs ipc -p "$COPY/shell.qml" call btprobe geom 2>&1); echo "$G"
X=$(python3 -c "import json,sys; g=json.loads(sys.argv[1]); print(int(g['x']+g['w']/2))" "$G" 2>/dev/null)
Y=$(python3 -c "import json,sys; g=json.loads(sys.argv[1]); print(int(g['y']+g['h']/2))" "$G" 2>/dev/null)
BARY=$(hyprctl layers -j | python3 -c "
import json,sys
for m,v in json.load(sys.stdin).items():
    for lvl,ls in v['levels'].items():
        for l in ls:
            if l['namespace']=='quickshell:bar': print(l['y']); raise SystemExit
print(0)")
BARX=$(hyprctl layers -j | python3 -c "
import json,sys
for m,v in json.load(sys.stdin).items():
    for lvl,ls in v['levels'].items():
        for l in ls:
            if l['namespace']=='quickshell:bar': print(l['x']); raise SystemExit
print(0)")
echo "--- hover at $((BARX+X)),$((BARY+Y)) ---"
hyprctl dispatch movecursor 640 600 >/dev/null; sleep 0.5
hyprctl dispatch movecursor $((BARX+X)) $((BARY+Y)) >/dev/null; sleep 2.5
grep "BTPROBE popup" "$TMP/shell.log" | tail -2
hyprctl dispatch movecursor 640 600 >/dev/null; sleep 2
grep "BTPROBE popup" "$TMP/shell.log" | tail -1
echo "--- M3 style ---"; qs ipc -p "$COPY/shell.qml" call btprobe style 3 >/dev/null; sleep 1.5; qs ipc -p "$COPY/shell.qml" call btprobe geom
echo "--- click ---"; qs ipc -p "$COPY/shell.qml" call btprobe click; sleep 2.5
grep "BTPROBE sidebar" "$TMP/shell.log" | tail -2
hyprctl layers -j | python3 -c "
import json,sys
for m,v in json.load(sys.stdin).items():
    for lvl,ls in v['levels'].items():
        for l in ls:
            if 'sidebar' in l['namespace']: print('  layer', l['namespace'], l['w'], l['h'])"
echo "--- vertical ---"; qs ipc -p "$COPY/shell.qml" call btprobe style 1 >/dev/null
kill $QPID 2>/dev/null; sleep 1; kill $HPID 2>/dev/null; sleep 1; kill -9 $HPID 2>/dev/null
echo "--- shell log: errors/warnings naming our files ---"
grep -E "ERROR|WARN" "$TMP/shell.log" | grep -i -E "Bluetooth|BarWidgets|GlobalStates|SidebarRight|btprobe" | head -20
echo "--- all BTPROBE lines ---"; grep BTPROBE "$TMP/shell.log" | head -20
NESTED
