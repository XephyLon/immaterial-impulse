pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell

/**
 * Automatic dark/light theme switching by time of day.
 * Two trigger modes are selectable via Config.options.appearance.autoTheme.mode:
 *   - "sunset": light at local sunrise, dark at local sunset (reuses Weather).
 *   - "fixed":  light/dark at two configured HH:MM clock times.
 * Off by default; the manual toggle stays the default. The desired mode is only
 * pushed to the shell's dark-mode source of truth when it actually differs, so a
 * mid-session manual override is respected until the next scheduled transition.
 */
Singleton {
    id: root

    readonly property string mode: Config.options.appearance.autoTheme?.mode ?? "off"
    readonly property string lightTime: Config.options.appearance.autoTheme?.lightTime ?? "07:00"
    readonly property string darkTime: Config.options.appearance.autoTheme?.darkTime ?? "19:00"
    readonly property bool enabled: (Config?.ready ?? false) && root.mode !== "off"

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    // Which mode we last requested, to avoid re-issuing the switch while the
    // colors regenerate and to keep respecting a manual override until the next
    // transition. -1 = nothing requested yet.
    property int lastRequestedDark: -1

    // Parses "HH:MM", "H:MM:SS", or 12h "h:mm AM/PM" into minutes-of-day, or -1.
    function parseMinutes(str) {
        if (!str)
            return -1;
        const match = String(str).match(/(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?/);
        if (!match)
            return -1;
        let hour = Number(match[1]);
        const minute = Number(match[2]);
        const meridiem = match[3] ? match[3].toUpperCase() : "";
        if (meridiem === "PM" && hour < 12)
            hour += 12;
        else if (meridiem === "AM" && hour === 12)
            hour = 0;
        if (isNaN(hour) || isNaN(minute))
            return -1;
        return hour * 60 + minute;
    }

    function inBetween(t, from, to) {
        if (from < to)
            return (t >= from && t < to);
        // Wrapped around midnight
        return (t >= from || t < to);
    }

    // Returns "light", "dark", or "" when the schedule can't be resolved yet.
    function computeDesired() {
        const t = root.clockHour * 60 + root.clockMinute;
        let lightStart = -1;
        let darkStart = -1;
        if (root.mode === "fixed") {
            lightStart = root.parseMinutes(root.lightTime);
            darkStart = root.parseMinutes(root.darkTime);
        } else if (root.mode === "sunset") {
            lightStart = root.parseMinutes(Weather.data.sunrise);
            darkStart = root.parseMinutes(Weather.data.sunset);
        }
        if (lightStart < 0 || darkStart < 0 || lightStart === darkStart)
            return "";
        return root.inBetween(t, lightStart, darkStart) ? "light" : "dark";
    }

    function reEvaluate() {
        if (!root.enabled)
            return;
        const desired = root.computeDesired();
        if (desired === "")
            return;
        const wantDark = (desired === "dark");
        const wantDarkInt = wantDark ? 1 : 0;
        if (wantDark === Appearance.m3colors.darkmode) {
            // Already in the desired state (possibly set manually); record it so a
            // later manual override isn't immediately re-applied against the user.
            root.lastRequestedDark = wantDarkInt;
            return;
        }
        if (root.lastRequestedDark === wantDarkInt)
            return; // Already requested this transition; don't fight the user.
        root.lastRequestedDark = wantDarkInt;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", wantDark ? "dark" : "light", "--noswitch"]);
    }

    onClockMinuteChanged: root.reEvaluate()
    onModeChanged: {
        root.lastRequestedDark = -1;
        root.reEvaluate();
    }
    onEnabledChanged: {
        root.lastRequestedDark = -1;
        root.reEvaluate();
    }

    Connections {
        target: Weather
        function onDataChanged() {
            if (root.mode === "sunset")
                root.reEvaluate();
        }
    }

    // Referenced from shell.qml to force instantiation of this lazily-loaded
    // Singleton, matching the Hyprsunset.load() convention.
    function load() {}

    Component.onCompleted: root.reEvaluate()
}
