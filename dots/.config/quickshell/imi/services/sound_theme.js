.pragma library

// Pure XDG sound-theme resolution: event name -> file on disk.
//
// Everything that decides *which* file a sound event plays lives here, so the
// rules are reachable from a test. The filesystem half is a dumb collector
// (scripts/sounds/scan-sound-themes.py) that reports what exists; this module
// makes every choice about it - which theme, which subdirectory, which
// extension, and when to walk up an Inherits= chain.
//
// Spec: https://specifications.freedesktop.org/sound-theme-spec/

// The theme every lookup falls back to. The spec calls it the default theme and
// it is what the freedesktop package installs; a theme naming no Inherits= still
// gets it, and so does a theme name that resolves to nothing at all.
var DEFAULT_THEME = "freedesktop";

// Extension precedence. `.disabled` is the spec's "this event is deliberately
// silent" marker and must stop the walk rather than fall through to a parent -
// otherwise a theme author's silence is overridden by an inherited sound, which
// is a *wrong* sound rather than a missing one. `.oga` is not in the spec but is
// what the freedesktop, ocean, Smooth and Pop themes actually ship.
var EXTENSIONS = [".disabled", ".oga", ".ogg", ".wav"];

// Used when a theme declares no Directories=. The empty entry is the theme root,
// which is where a directory of loose files (no index.theme at all) keeps them.
var FALLBACK_DIRECTORIES = ["stereo", ""];

// A key list is comma-separated per the spec, but every installed theme on this
// machine writes Directories= space-separated (Pop:
// "stereo/alert stereo/action stereo/notification"). Accept both.
function splitList(value) {
    return String(value === undefined || value === null ? "" : value)
        .replace(/,/g, " ")
        .split(/\s+/)
        .filter(function (part) {
            return part.length > 0;
        });
}

// Reads only the [Sound Theme] group. Localized keys (Name[de]=) are ignored on
// purpose: nothing here should pick a theme's identity out of the user's locale,
// and `valid` is what tells a directory of loose .wav files (/usr/share/sounds/alsa)
// apart from a real theme.
function parseIndexTheme(text) {
    var result = {
        valid: false,
        name: "",
        directories: [],
        inherits: []
    };
    var lines = String(text === undefined || text === null ? "" : text).split(/\r\n|\r|\n/);
    var inSection = false;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.length === 0 || line.charAt(0) === "#")
            continue;
        if (line.charAt(0) === "[") {
            inSection = (line === "[Sound Theme]");
            if (inSection)
                result.valid = true;
            continue;
        }
        if (!inSection)
            continue;
        var eq = line.indexOf("=");
        if (eq < 0)
            continue;
        var key = line.slice(0, eq).trim();
        var value = line.slice(eq + 1).trim();
        if (key === "Name")
            result.name = value;
        else if (key === "Directories")
            result.directories = splitList(value);
        else if (key === "Inherits")
            result.inherits = splitList(value);
    }
    return result;
}

// Folds the scanner's flat entry list into one record per theme name.
//
// `scan.entries` arrives in search-root precedence order (XDG_DATA_HOME first,
// /usr/share/sounds last), and a theme present in two roots keeps both entries in
// that order - so a theme dropped into ~/.local/share/sounds shadows the system
// copy file by file rather than only when it is complete.
function buildCatalogue(scan) {
    var catalogue = {
        themes: {},
        names: []
    };
    var entries = (scan && scan.entries) || [];
    for (var i = 0; i < entries.length; i++) {
        var raw = entries[i];
        var name = String((raw && raw.theme) || "");
        if (name.length === 0)
            continue;
        var theme = catalogue.themes[name];
        if (!theme) {
            theme = {
                name: name,
                displayName: "",
                valid: false,
                inherits: [],
                entries: []
            };
            catalogue.themes[name] = theme;
            catalogue.names.push(name);
        }
        var meta = parseIndexTheme(raw.index);
        // The highest-precedence copy carrying an index.theme owns the theme's
        // identity and its parents; a system copy does not get to re-parent a
        // theme the user has overridden.
        if (!theme.valid && meta.valid) {
            theme.valid = true;
            theme.displayName = meta.name;
            theme.inherits = meta.inherits;
        }
        var files = {};
        var list = (raw && raw.files) || [];
        for (var f = 0; f < list.length; f++)
            files[String(list[f])] = true;
        theme.entries.push({
            dir: String((raw && raw.dir) || ""),
            directories: meta.directories.length > 0 ? meta.directories : FALLBACK_DIRECTORIES.slice(),
            files: files
        });
    }
    return catalogue;
}

// Breadth-first over Inherits=, which is what makes a diamond ("both parents
// inherit freedesktop") visit each theme once and a cycle terminate at all.
// DEFAULT_THEME is appended last rather than inserted, so an explicit Inherits=
// ordering still decides everything above it.
function themeChain(catalogue, themeName) {
    var chain = [];
    var seen = {};
    var queue = [String(themeName === undefined || themeName === null ? "" : themeName).trim()];
    while (queue.length > 0) {
        var name = queue.shift();
        if (name.length === 0 || seen[name] === true)
            continue;
        seen[name] = true;
        chain.push(name);
        var theme = catalogue && catalogue.themes ? catalogue.themes[name] : null;
        if (!theme)
            continue;
        for (var i = 0; i < theme.inherits.length; i++)
            queue.push(theme.inherits[i]);
    }
    if (seen[DEFAULT_THEME] !== true)
        chain.push(DEFAULT_THEME);
    return chain;
}

// An event id is a name, never a path. `..` in an event name would otherwise
// reach out of the theme directory entirely, and the caller hands whatever it is
// given straight to a player process.
function isPlayableEventName(eventName) {
    var event = String(eventName === undefined || eventName === null ? "" : eventName);
    if (event.length === 0)
        return false;
    if (event.indexOf("/") >= 0 || event.indexOf("\\") >= 0)
        return false;
    return event !== "." && event !== "..";
}

// The whole point: one absolute path, or "" for "play nothing".
//
// "" covers both "no theme in the chain has this event" and "a theme in the
// chain silenced it with a .disabled marker" - the caller cannot act differently
// on those two, and conflating them is what keeps the marker meaningful.
function resolveEvent(catalogue, themeName, eventName) {
    if (!isPlayableEventName(eventName))
        return "";
    var event = String(eventName);
    var chain = themeChain(catalogue, themeName);
    for (var c = 0; c < chain.length; c++) {
        var theme = catalogue && catalogue.themes ? catalogue.themes[chain[c]] : null;
        if (!theme)
            continue;
        for (var e = 0; e < theme.entries.length; e++) {
            var entry = theme.entries[e];
            for (var d = 0; d < entry.directories.length; d++) {
                var dir = entry.directories[d];
                var prefix = dir.length > 0 ? dir + "/" : "";
                for (var x = 0; x < EXTENSIONS.length; x++) {
                    var relative = prefix + event + EXTENSIONS[x];
                    if (entry.files[relative] !== true)
                        continue;
                    if (EXTENSIONS[x] === ".disabled")
                        return "";
                    return entry.dir + "/" + relative;
                }
            }
        }
    }
    return "";
}

// What the settings picker offers. A directory of loose sound files with no
// index.theme (/usr/share/sounds/alsa is the one on a stock Arch install) is
// reachable by name but is not a sound theme and is not offered as one.
function selectableThemes(catalogue) {
    var offered = [];
    var names = (catalogue && catalogue.names) || [];
    for (var i = 0; i < names.length; i++) {
        var theme = catalogue.themes[names[i]];
        if (!theme || !theme.valid)
            continue;
        offered.push({
            id: theme.name,
            displayName: theme.displayName.length > 0 ? theme.displayName : theme.name
        });
    }
    offered.sort(function (a, b) {
        return a.displayName.toLowerCase() < b.displayName.toLowerCase() ? -1 : (a.displayName.toLowerCase() > b.displayName.toLowerCase() ? 1 : 0);
    });
    return offered;
}
