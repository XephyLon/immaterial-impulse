pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Hyprland

/**
 * Night light service on hyprsunset (controlled via hyprctl).
 *
 * The shell owns the on/off state, because hyprsunset will not tell us. On
 * 0.4.0 `hyprctl hyprsunset --help` lists exactly three requests -
 * `temperature`, `gamma`, `identity` - and the daemon's own socket answers
 * "invalid command" to everything else, so there is nothing to ask. The bare
 * `temperature` request reports the last temperature the daemon was *told*,
 * and `identity` (the off switch) never resets it: measured here, a daemon
 * running as `hyprsunset --identity` with a perfectly neutral screen reports
 * 6000, and a daemon put into identity after `temperature 5000` still reports
 * 5000. "Off" and "on" are indistinguishable through it.
 *
 * So on/off intent is persisted (Persistent.states.night.temperatureActive,
 * alongside idle.inhibit and record.enable) and re-*applied* at startup rather
 * than probed. Applied, not merely displayed: after a reboot the daemon is
 * gone, and within a session it may have been left in any state, so telling it
 * what we believe is the only way the indicator and the screen can agree.
 *
 * Automatic scheduling is still opt-in going forward only. Startup restores
 * the state the user last had and never consults the clock - we never
 * force-enable just because the clock happens to fall in the night window at
 * load time (see `firstEvaluation`).
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
    property bool stateRestored: false

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
        root.restoreState();
    }

    // Both loads are asynchronous and shell.qml calls load() from
    // Component.onCompleted, so neither is normally there yet. Persistent
    // holds the state to restore; Config holds the temperature to restore it
    // *at*, and restoring without it launches the daemon at the fallback
    // temperature and then corrects it over a hyprctl call that races the
    // daemon's socket on a cold start - the failure startHyprsunset's launch
    // flags exist to avoid.
    readonly property bool readyToRestore: (Persistent.ready ?? false) && (Config.ready ?? false)
    onReadyToRestoreChanged: root.restoreState()

    function restoreState() {
        if (root.stateRestored || !root.readyToRestore)
            return;
        root.stateRestored = true;
        // Unlike idle.inhibit, this is restored across a compositor restart
        // too (no `isNewHyprlandInstance` check): night light is a standing
        // preference, and a new session means a daemon that has just come up
        // knowing nothing, which is exactly when re-applying matters most.
        if (Persistent.states.night.temperatureActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    function enableTemperature() {
        root.startHyprsunset(["--temperature", String(root.colorTemperature)]);
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);
        root.setActive(true);
    }

    function disableTemperature() {
        // Mirrors enableTemperature deliberately: the launch flags cover a cold
        // start (where the hyprctl call races the daemon's socket and can be
        // lost), the hyprctl call covers a daemon that is already up.
        root.startHyprsunset(["--identity"]);
        Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        root.setActive(false);
    }

    // The only writer of temperatureActive. hyprsunset cannot be asked what it
    // is doing, so this value *is* the state - it has to reach disk, or the
    // next launch has nothing to restore from and is back to guessing.
    function setActive(active) {
        root.temperatureActive = active;
        Persistent.states.night.temperatureActive = active;
    }

    // The launch flags that reproduce the state we believe is applied, so a
    // launch that is not itself a night-light change cannot silently reset it.
    function currentStateArgs() {
        return root.temperatureActive ? ["--temperature", String(root.colorTemperature)] : ["--identity"];
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));
        root.gammaChangeAttempt();

        root.startHyprsunset(root.currentStateArgs());
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
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