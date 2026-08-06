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
            // A poll that raced an in-flight or queued command reports the
            // pre-command value; adopting it as the base would re-apply the
            // delta. Only converge the base while the queue is idle.
            if (!root.commandInFlight && Math.abs(root.pendingDelta) < 0.005)
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

    property real pendingDelta: 0
    property bool commandInFlight: false

    function increaseBacklight(step = 0.05): void {
        root.queueBacklightDelta(step);
    }

    function decreaseBacklight(step = 0.05): void {
        root.queueBacklightDelta(-step);
    }

    function setBacklight(target: real): void {
        // Same never-fully-black floor as Brightness.qml's own writers.
        target = Math.max(0.01, Math.min(1, target));
        if (!root.managesBacklight)
            return;
        // Absolute target: replaces whatever delta is still queued.
        root.pendingDelta = target - root.commandedBacklight;
        root.drainBacklightQueue();
    }

    function queueBacklightDelta(delta: real): void {
        if (!root.managesBacklight)
            return;
        root.pendingDelta += delta;
        root.drainBacklightQueue();
    }

    // One busctl in flight at a time: Process.exec on a running process kills
    // it, silently dropping that command's delta - an animated slider issues
    // a change per frame, so queued deltas accumulate and follow on exit.
    function drainBacklightQueue(): void {
        if (root.commandInFlight || Math.abs(root.pendingDelta) < 0.005)
            return;
        const delta = root.pendingDelta;
        root.pendingDelta = 0;
        root.commandedBacklight = Math.max(0, Math.min(1, root.commandedBacklight + delta));
        root.commandInFlight = true;
        cmdProc.exec(["busctl", "--user", "call", root.busName, root.busPath,
            root.busName, delta > 0 ? "IncBl" : "DecBl", "d", String(Math.abs(delta))]);
    }

    function setAutoCalibration(enabled: bool): void {
        if (!root.available)
            return;
        root.autoCalibration = enabled;
        propProc.exec(["busctl", "--user", "set-property", root.busName,
            `${root.busPath}/Conf/Backlight`, `${root.busName}.Conf.Backlight`,
            "NoAutoCalib", "b", enabled ? "false" : "true"]);
    }

    function setDayTemperature(value: int): void {
        if (!root.available)
            return;
        root.dayTemperature = value;
        propProc.exec(["busctl", "--user", "set-property", root.busName,
            `${root.busPath}/Conf/Gamma`, `${root.busName}.Conf.Gamma`,
            "DayTemp", "i", String(value)]);
    }

    function setNightTemperature(value: int): void {
        if (!root.available)
            return;
        root.nightTemperature = value;
        propProc.exec(["busctl", "--user", "set-property", root.busName,
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
            root.commandInFlight = false;
            if (Math.abs(root.pendingDelta) >= 0.005) {
                root.drainBacklightQueue();
            } else {
                root.refresh();
            }
        }
    }

    // Property writes get their own process so a settings interaction cannot
    // kill an in-flight backlight command (and vice versa).
    Process {
        id: propProc
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
