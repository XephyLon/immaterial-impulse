.pragma library

// Per-project Wallpaper Engine settings, resolved against the globals.
//
// The shape is the reference app's (jagrat7/linux-wallpaper-engine)
// ENGINE_OVERRIDE_FIELDS: each overridable key falls back to the global
// config value when the project carries no override of its own, so a project
// with no record behaves exactly as every project always has. Only the keys
// the embedded renderer actually answers are overridable - fps, scaleMode
// and whether audio plays (WallpaperEngineSurface's whole property surface);
// a control for a flag the renderer does not read would be a fake action.
//
// The map is keyed by runtime project ids, so it lives in a raw-JSON store
// (WallpaperEngineOverrides.qml), never a JsonAdapter - undeclared children
// on one have segfaulted deserialization before (see CONTRIBUTING.md).

var KEYS = ["fps", "scaling", "silent"];

// The settings the active project runs at: its own override per key, else
// the global. An empty project id is the absence of a key, not a key.
function resolve(overrides, projectId, globals) {
    var result = {
        fps: globals.fps,
        scaling: globals.scaling,
        silent: globals.silent
    };
    if (!projectId || !overrides || typeof overrides !== "object")
        return result;
    var record = overrides[projectId];
    if (!record || typeof record !== "object")
        return result;
    for (var i = 0; i < KEYS.length; i++) {
        var key = KEYS[i];
        // undefined is absence; false and 0 are values (the Number(null)
        // trap's sibling).
        if (record[key] !== undefined && record[key] !== null)
            result[key] = record[key];
    }
    return result;
}

function hasOverride(overrides, projectId) {
    if (!projectId || !overrides || typeof overrides !== "object")
        return false;
    var record = overrides[projectId];
    return !!record && typeof record === "object" && Object.keys(record).length > 0;
}

// A new map with the key set (value) or cleared (null/undefined). A project
// whose last key is cleared is removed whole, so the store never accretes
// empty records - and a literal null is never stored, because a stored null
// answers past every later fallback (the PluginState.setOption lesson).
function setOverride(overrides, projectId, key, value) {
    var result = {};
    for (var id in overrides)
        result[id] = overrides[id];
    var record = {};
    for (var k in (result[projectId] ?? {}))
        record[k] = result[projectId][k];
    if (value === null || value === undefined)
        delete record[key];
    else
        record[key] = value;
    if (Object.keys(record).length === 0)
        delete result[projectId];
    else
        result[projectId] = record;
    return result;
}

// What a loaded store file becomes: only object entries, only known keys.
// A file another version wrote, or a hand edit, degrades to the subset this
// version understands rather than to a parse-time throw.
function sanitize(loaded) {
    var result = {};
    if (!loaded || typeof loaded !== "object")
        return result;
    for (var id in loaded) {
        var record = loaded[id];
        if (!record || typeof record !== "object")
            continue;
        var clean = {};
        for (var i = 0; i < KEYS.length; i++) {
            var key = KEYS[i];
            if (record[key] !== undefined && record[key] !== null)
                clean[key] = record[key];
        }
        if (Object.keys(clean).length > 0)
            result[id] = clean;
    }
    return result;
}
