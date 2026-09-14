.pragma library

// The permission vocabulary for the assistant's tools (stage 4/5 of
// docs/proposals/ai-assistant-upgrade.md, sized to what is enforced): which
// tools run on their own, which raise the approval card first, which need
// an explicit confirm; how a call's arguments are validated against the
// registry's schema; and how a result is bounded before it goes back on the
// wire. Pure functions over their arguments - Ai.qml asks, this answers.

// read: runs at once, answers the model. reviewed: the reply shows what
// would change and the user approves or rejects (the card run_shell_command
// already has). destructive: the same card, but never auto-approvable by a
// grant. A tool not listed is `reviewed`: a write is never silently allowed.
var TIERS = {
    read: ["switch_to_search_mode", "get_shell_config", "remember_fact", "control_media", "focus_window",
           "send_notification", "get_system_status", "generate_image",
           "read_file", "list_directory", "get_clipboard", "get_wallpaper", "list_todos", "list_events",
           "search_documents"],
    reviewed: ["set_shell_config", "write_file", "append_file", "set_clipboard", "set_wallpaper",
               "set_accent", "set_palette_source", "set_color_scheme", "add_todo"],
    destructive: ["run_shell_command"],
};

function tierOf(name) {
    for (var tier in TIERS)
        if (TIERS[tier].indexOf(name) !== -1) return tier;
    return "reviewed";
}

// Validate `args` against a registry definition's JSON-schema-ish
// `parameters`: coerce what can be coerced (a number sent as a string, a
// boolean as "true"), drop keys the schema does not name, and report the
// required ones that are missing. Returns { ok, args, missing }.
function validateArgs(def, args) {
    var schema = (def && def.parameters) || { properties: {}, required: [] };
    var props = schema.properties || {};
    var out = {};
    var src = args || {};
    for (var key in props) {
        if (!(key in src) || src[key] === undefined || src[key] === null) continue;
        var want = props[key].type;
        var v = src[key];
        if (want === "integer" || want === "number") {
            var n = Number(v);
            if (isNaN(n)) continue;
            out[key] = want === "integer" ? Math.round(n) : n;
        } else if (want === "boolean") {
            out[key] = (v === true || v === "true" || v === 1 || v === "1");
        } else if (want === "string") {
            out[key] = String(v);
        } else {
            out[key] = v;
        }
        if (props[key]["enum"] && props[key]["enum"].indexOf(out[key]) === -1) delete out[key];
    }
    var missing = (schema.required || []).filter(function (k) { return !(k in out); });
    return { ok: missing.length === 0, args: out, missing: missing };
}

// One line the approval card can show: what would change, in the user's
// terms. Never the raw JSON.
function summaryFor(name, args) {
    var a = args || {};
    switch (name) {
    case "write_file": return "Write " + (a.path || "?") + " (" + String(a.content || "").length + " characters, replacing the file)";
    case "append_file": return "Append " + String(a.content || "").length + " characters to " + (a.path || "?");
    case "set_clipboard": return "Put on the clipboard: " + String(a.text || "").slice(0, 120) + (String(a.text || "").length > 120 ? "…" : "");
    case "set_wallpaper": return a.path === "random" ? "Pick a random wallpaper from the current folder" : "Set the wallpaper to " + (a.path || "?");
    case "set_accent": return a.color === "auto" ? "Let the wallpaper pick the accent colour" : "Set the accent colour to " + (a.color || "?");
    case "set_palette_source": return "Seed the palette from the wallpaper's " + (a.mode || "?") + " colour";
    case "set_color_scheme": return "Switch to " + (a.scheme || "?") + " mode";
    case "add_todo": return "Add to-do: " + (a.text || "?");
    case "set_shell_config": return "Set " + (a.key || "?") + " to " + String(a.value);
    default: return name + " " + JSON.stringify(a);
    }
}

// A result cut to a byte budget before it is sent, with a note that says so.
function bound(text, maxChars) {
    var s = String(text === undefined || text === null ? "" : text);
    if (s.length <= maxChars) return s;
    return s.slice(0, maxChars) + "\n[… " + (s.length - maxChars) + " more characters cut]";
}

var DEFAULT_MAX_RESULT_CHARS = 24000;
var HEX_COLOR = /^#[0-9A-Fa-f]{6}$/;
var PALETTE_SOURCES = ["dominant", "saturation", "less-saturation", "lightness", "darkness", "value"];
