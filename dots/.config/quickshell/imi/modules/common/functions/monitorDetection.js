.pragma library

// Connector-name heuristics for telling a laptop's built-in panel apart from
// external monitors, ported from end-4/dots-hyprland PR #2109
// (ExtMonitorInhibit). A monitor counts as "external" iff its connector name
// matches none of the built-in patterns.
//
// Caveat kept from upstream: DP-N-M is treated as built-in ("some integrated
// displays") even though dock/MST outputs can use the same form. On a desktop
// every monitor (DP-1, HDMI-A-1, ...) reads as external, which is why the
// auto-inhibit option is opt-in.
var builtInPatterns = [
    /^eDP/,          // most common laptop panel (eDP-1, eDP-2, ...)
    /^LVDS/,         // older laptops
    /^DSI/,          // some newer laptops
    /^DP-\d+-\d+$/,  // some integrated displays
];

function isBuiltIn(name) {
    const str = String(name ?? "");
    return builtInPatterns.some(pattern => pattern.test(str));
}

// `names` is a list of connector names (e.g. Quickshell.screens.map(s => s.name)).
function hasExternal(names) {
    return (names ?? []).some(name => !isBuiltIn(name));
}
