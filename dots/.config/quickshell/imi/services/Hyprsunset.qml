pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Night light service on hyprsunset (controlled via hyprctl).
 *
 * Automatic scheduling is opt-in going forward only: on startup we merely
 * SYNC with whatever is actually running (fetchState), we never force-enable
 * just because the clock happens to fall in the night window at load time.
 */
Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25

    property string from: Config.options?.light?.night?.from ?? "19:00"
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: (Config.options?.light?.night?.automatic ?? false) && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int gamma: 100
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);

        if (firstEvaluation) {
            firstEvaluation = false;
            root.fetchState();
            return;
        }
        root.ensureState();
    }

    onShouldBeOnChanged: {
        if (!root.firstEvaluation)
            root.ensureState();
    }

    function ensureState() {
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    // `hyprsunset --help`: "--temperature -t  Set the temperature in K
    // (default 6000)". So a bare `hyprsunset` does not start neutral - it
    // applies a 6000K warm tint the moment it comes up. Every launch that is
    // not explicitly turning night light *on* must therefore say --identity
    // ("Use the identity matrix (no color change)"), or merely starting the
    // daemon switches night light on for someone who never enabled it.
    //
    // The target state goes in as launch flags rather than a follow-up hyprctl
    // call: that call is fire-and-forget and races the daemon's socket on a
    // cold start, silently leaving the wrong temperature applied.
    function startHyprsunset(initialArgs = ["--identity"]) {
        const launch = ["hyprsunset"].concat(initialArgs).join(" ");
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || ${launch}`]);
    }

    function load() {
        root.startHyprsunset();
        root.fetchState();
    }

    function enableTemperature() {
        root.startHyprsunset(["--temperature", String(root.colorTemperature)]);
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);
        root.temperatureActive = true;
    }

    function disableTemperature() {
        Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        root.temperatureActive = false;
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));
        root.gammaChangeAttempt();

        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
    }

    function fetchState() {
        fetchProc.running = true;
    }

    Process {
        id: fetchProc
        running: true
        command: ["bash", "-c", "hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output.startsWith("Couldn't"))
                    root.temperatureActive = false;
                else
                    root.temperatureActive = (output != "6500");
            }
        }
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    // Change temp
    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);
        }
    }
}