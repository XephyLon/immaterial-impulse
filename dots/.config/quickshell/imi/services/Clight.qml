pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * Clight daemon state and control (busctl-backed).
 *
 * The shell has no D-Bus binding - every service shells out via Process, so
 * this one talks to org.clight.clight through `busctl --user --json=short`
 * (see docs/proposals/clight-integration.md for the transport reasoning).
 *
 * Detection is two-staged like Tailscale.qml: `installed` (clight binary on
 * PATH, checked once at startup) gates the polling, and `available` (the
 * daemon answered the last properties poll) is what consumers branch on.
 * With either false everything degrades to the shell's stock behaviour -
 * Brightness.qml writes the backlight itself exactly as before.
 *
 * Clight's bus API only moves the backlight relatively (IncBl/DecBl take a
 * delta), so setBacklight() turns an absolute target into a delta against
 * `commandedBacklight` - the last value the daemon reported or was told.
 * Tracking the commanded value rather than the last poll is what keeps rapid
 * successive changes (a held brightness key, the OSD slider animation) from
 * compounding against a stale base. A poll that was already in flight when a
 * command landed can still reset the base one tick late; the next poll
 * converges it, and the error is bounded by one step.
 */
Singleton {
    id: root

    readonly property bool enableService: Config.options.light?.clight?.enable ?? true
    property int pollInterval: 5000

    property bool installed: false // clight binary found on PATH
    property bool available: false // daemon answered the last properties poll
    property bool ready: false     // first successful poll has landed

    property real backlight: 0
    property real commandedBacklight: 0
    property int temperature: 6500
    property real ambientBrightness: 0
    property bool sensorAvailable: false
    property bool inhibited: false
    property string version: ""

    property bool autoCalibration: false
    property int dayTemperature: 6500
    property int nightTemperature: 4000

    // Deferring whenever the daemon is up, not only when auto-calibration is
    // on: routing through Clight is what keeps its idea of the backlight in
    // step with ours, and it is a no-op difference when calibration is manual.
    readonly property bool managesBacklight: available

    // Emitted only for a change the daemon made after its first report, so a
    // startup read never announces anything.
    signal temperatureChangedByDaemon()

    readonly property string busName: "org.clight.clight"
    readonly property string busPath: "/org/clight/clight"

    // busctl --json=short GetAll: {"type":"a{sv}","data":[{"Name":{"type":"d","data":0.5},...}]}
    // Returns a flat name->value object, or null when the text is not a
    // properties document (daemon down, empty output, malformed JSON).
    function parseGetAll(text: string): var {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0)
            return null;
        let doc;
        try {
            doc = JSON.parse(trimmed);
        } catch (e) {
            return null;
        }
        const dict = doc?.data?.[0];
        if (!dict || typeof dict !== "object")
            return null;
        const values = {};
        for (const key in dict)
            values[key] = dict[key]?.data;
        return values;
    }

    function applyState(text: string): void {
        const values = root.parseGetAll(text);
        if (values === null) {
            root.available = false;
            root.ready = false;
            return;
        }
        const firstReport = !root.ready;
        root.available = true;
        if (values.BlPct !== undefined) {
            root.backlight = values.BlPct;
            root.commandedBacklight = values.BlPct;
        }
        if (values.Temp !== undefined) {
            const previous = root.temperature;
            root.temperature = values.Temp;
            if (!firstReport && previous !== values.Temp)
                root.temperatureChangedByDaemon();
        }
        if (values.AmbientBr !== undefined)
            root.ambientBrightness = values.AmbientBr;
        if (values.SensorAvail !== undefined)
            root.sensorAvailable = values.SensorAvail;
        if (values.Inhibited !== undefined)
            root.inhibited = values.Inhibited;
        if (values.Version !== undefined)
            root.version = values.Version;
        root.ready = true;
    }

    function applyBacklightConf(text: string): void {
        const values = root.parseGetAll(text);
        if (values === null)
            return;
        if (values.NoAutoCalib !== undefined)
            root.autoCalibration = !values.NoAutoCalib;
    }

    function applyGammaConf(text: string): void {
        const values = root.parseGetAll(text);
        if (values === null)
            return;
        if (values.DayTemp !== undefined)
            root.dayTemperature = values.DayTemp;
        if (values.NightTemp !== undefined)
            root.nightTemperature = values.NightTemp;
    }

    function refresh(): void {
        if (!root.enableService || !root.installed)
            return;
        for (const proc of [stateProc, backlightConfProc, gammaConfProc]) {
            proc.running = false;
            proc.running = true;
        }
    }

    function increaseBacklight(step = 0.05): void {
        root.relativeBacklight(step);
    }

    function decreaseBacklight(step = 0.05): void {
        root.relativeBacklight(-step);
    }

    function setBacklight(target: real): void {
        // Same never-fully-black floor as Brightness.qml's own writers.
        target = Math.max(0.01, Math.min(1, target));
        root.relativeBacklight(target - root.commandedBacklight);
    }

    function relativeBacklight(delta: real): void {
        if (!root.managesBacklight || Math.abs(delta) < 0.005)
            return;
        root.commandedBacklight = Math.max(0, Math.min(1, root.commandedBacklight + delta));
        cmdProc.exec(["busctl", "--user", "call", root.busName, root.busPath,
            root.busName, delta > 0 ? "IncBl" : "DecBl", "d", String(Math.abs(delta))]);
    }

    function setAutoCalibration(enabled: bool): void {
        if (!root.available)
            return;
        root.autoCalibration = enabled;
        cmdProc.exec(["busctl", "--user", "set-property", root.busName,
            `${root.busPath}/Conf/Backlight`, `${root.busName}.Conf.Backlight`,
            "NoAutoCalib", "b", enabled ? "false" : "true"]);
    }

    function setDayTemperature(value: int): void {
        if (!root.available)
            return;
        root.dayTemperature = value;
        cmdProc.exec(["busctl", "--user", "set-property", root.busName,
            `${root.busPath}/Conf/Gamma`, `${root.busName}.Conf.Gamma`,
            "DayTemp", "i", String(value)]);
    }

    function setNightTemperature(value: int): void {
        if (!root.available)
            return;
        root.nightTemperature = value;
        cmdProc.exec(["busctl", "--user", "set-property", root.busName,
            `${root.busPath}/Conf/Gamma`, `${root.busName}.Conf.Gamma`,
            "NightTemp", "i", String(value)]);
    }

    onEnableServiceChanged: {
        if (root.enableService) {
            root.refresh();
        } else {
            root.available = false;
            root.ready = false;
        }
    }

    Process {
        id: cmdProc
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    // One-shot presence check; the polling is gated on it so machines without
    // Clight never spawn a busctl.
    Process {
        id: whichProc
        running: true
        command: ["sh", "-c", "command -v clight"]
        onExited: (exitCode, exitStatus) => {
            root.installed = (exitCode === 0);
            if (root.installed)
                root.refresh();
        }
    }

    Process {
        id: stateProc
        command: ["busctl", "--user", "--json=short", "call", root.busName, root.busPath,
            "org.freedesktop.DBus.Properties", "GetAll", "s", root.busName]
        stdout: StdioCollector {
            onStreamFinished: root.applyState(text)
        }
    }

    Process {
        id: backlightConfProc
        command: ["busctl", "--user", "--json=short", "call", root.busName, `${root.busPath}/Conf/Backlight`,
            "org.freedesktop.DBus.Properties", "GetAll", "s", `${root.busName}.Conf.Backlight`]
        stdout: StdioCollector {
            onStreamFinished: root.applyBacklightConf(text)
        }
    }

    Process {
        id: gammaConfProc
        command: ["busctl", "--user", "--json=short", "call", root.busName, `${root.busPath}/Conf/Gamma`,
            "org.freedesktop.DBus.Properties", "GetAll", "s", `${root.busName}.Conf.Gamma`]
        stdout: StdioCollector {
            onStreamFinished: root.applyGammaConf(text)
        }
    }

    Timer {
        interval: root.pollInterval
        running: root.enableService && root.installed
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
