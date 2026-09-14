.pragma library

// The cookie clock's look per wallpaper category (the AI styling that
// follows the generated wallpaper's category file). One table, so the
// widget applies a preset and never decides one; tests/tst_cookie_presets.qml
// pins the table's shape.
//
// Each preset: [sides, dialNumberStyle, hourHandStyle, minuteHandStyle,
// secondHandStyle, dateStyle] - the order applyStyle() takes.
var PRESETS = {
    "abstract":   [9,  "none", "fill",    "medium",  "dot",     "bubble"],
    "anime":      [7,  "none", "fill",    "bold",    "dot",     "bubble"],
    "city":       [23, "full", "hollow",  "thin",    "classic", "bubble"],
    "space":      [23, "full", "hollow",  "thin",    "classic", "bubble"],
    "minimalist": [6,  "none", "fill",    "bold",    "dot",     "hide"],
    "landscape":  [14, "full", "hollow",  "medium",  "classic", "bubble"],
    "plants":     [9,  "dots", "fill",    "bold",    "dot",     "border"],
    "person":     [14, "full", "classic", "classic", "classic", "rect"],
};

// The preset for a category file's contents, or null when there is none
// to apply (empty, whitespace, an unknown category).
function presetFor(category) {
    var key = String(category === undefined || category === null ? "" : category).trim().toLowerCase();
    if (key.length === 0) return null;
    return PRESETS.hasOwnProperty(key) ? PRESETS[key].slice() : null;
}
