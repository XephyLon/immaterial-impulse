.pragma library

// Per-project Wallpaper Engine settings, resolved against the globals.
//
// The shape is the reference app's (jagrat7/linux-wallpaper-engine)
// ENGINE_OVERRIDE_FIELDS: each overridable engine flag falls back to the
// global config value when the project carries no override of its own, so a
// project with no record behaves exactly as every project always has. Only
// keys the embedded renderer actually answers are overridable (fps,
// scaleMode, audio on/off, volume, the audio-reactive recorder and WE's
// mouse/parallax/particles switches - WallpaperEngineSurface's whole
// property surface); a control for a flag the renderer does not read would
// be a fake action.
//
// `properties` beside the flags is the per-wallpaper user-property map
// (project.json general.properties, values in --set-property's string form).
// It is inherently per-wallpaper - there is no global to fall back to - and
// it is deliberately NOT part of the "engine override" question the sidebar's
// Custom settings switch asks: hasOverride/clearEngineOverrides leave it
// alone, or flipping the switch off would eat the user's property edits.
//
// The map is keyed by runtime project ids, so it lives in a raw-JSON store
// (WallpaperEngineOverrides.qml), never a JsonAdapter - undeclared children
// on one have segfaulted deserialization before (see CONTRIBUTING.md).

var KEYS = [
    "fps", "scaling", "silent",
    "volume", "audioProcessing",
    "disableMouse", "disableParallax", "disableParticles"
];

// The settings the active project runs at: its own override per key, else
// the global; plus its property map, which has no global side. An empty
// project id is the absence of a key, not a key.
function resolve(overrides, projectId, globals) {
    var result = { properties: {} };
    for (var i = 0; i < KEYS.length; i++)
        result[KEYS[i]] = globals[KEYS[i]];
    if (!projectId || !overrides || typeof overrides !== "object")
        return result;
    var record = overrides[projectId];
    if (!record || typeof record !== "object")
        return result;
    for (i = 0; i < KEYS.length; i++) {
        var key = KEYS[i];
        // undefined is absence; false and 0 are values (the Number(null)
        // trap's sibling).
        if (record[key] !== undefined && record[key] !== null)
            result[key] = record[key];
    }
    if (record.properties && typeof record.properties === "object") {
        for (var name in record.properties)
            result.properties[name] = record.properties[name];
    }
    return result;
}

// Whether the project carries ENGINE flag overrides - the Custom settings
// switch's question. A record holding only tweaked properties answers no.
function hasOverride(overrides, projectId) {
    if (!projectId || !overrides || typeof overrides !== "object")
        return false;
    var record = overrides[projectId];
    if (!record || typeof record !== "object")
        return false;
    for (var i = 0; i < KEYS.length; i++)
        if (record[KEYS[i]] !== undefined && record[KEYS[i]] !== null)
            return true;
    return false;
}

// Whether the project carries property edits.
function hasProperties(overrides, projectId) {
    if (!projectId || !overrides || typeof overrides !== "object")
        return false;
    var record = overrides[projectId];
    return !!record && typeof record === "object"
        && !!record.properties && typeof record.properties === "object"
        && Object.keys(record.properties).length > 0;
}

function _cloneRecord(record) {
    var clone = {};
    for (var k in (record ?? {})) {
        if (k === "properties") {
            clone.properties = {};
            for (var name in record.properties)
                clone.properties[name] = record.properties[name];
        } else {
            clone[k] = record[k];
        }
    }
    return clone;
}

function _store(overrides, projectId, record) {
    var result = {};
    for (var id in overrides)
        result[id] = overrides[id];
    var empty = Object.keys(record).length === 0
        || (Object.keys(record).length === 1 && "properties" in record
            && Object.keys(record.properties).length === 0);
    if (empty)
        delete result[projectId];
    else
        result[projectId] = record;
    return result;
}

// A new map with the engine flag set (value) or cleared (null/undefined). A
// project whose record empties is removed whole, so the store never accretes
// empty records - and a literal null is never stored, because a stored null
// answers past every later fallback (the PluginState.setOption lesson).
function setOverride(overrides, projectId, key, value) {
    var record = _cloneRecord(overrides[projectId]);
    if (value === null || value === undefined)
        delete record[key];
    else
        record[key] = value;
    return _store(overrides, projectId, record);
}

// A new map with one project property set (string value) or cleared (null).
function setProjectProperty(overrides, projectId, name, value) {
    var record = _cloneRecord(overrides[projectId]);
    if (!record.properties)
        record.properties = {};
    if (value === null || value === undefined)
        delete record.properties[name];
    else
        record.properties[name] = String(value);
    if (Object.keys(record.properties).length === 0)
        delete record.properties;
    return _store(overrides, projectId, record);
}

// A new map with the project's ENGINE flags cleared and its property edits
// kept - what the Custom settings switch turning off means.
function clearEngineOverrides(overrides, projectId) {
    var record = _cloneRecord(overrides[projectId]);
    for (var i = 0; i < KEYS.length; i++)
        delete record[KEYS[i]];
    return _store(overrides, projectId, record);
}

// What a loaded store file becomes: only object entries, only known keys,
// property values coerced to the strings WE's command line gets (an object
// has no string form, so it drops). A file another version wrote, or a hand
// edit, degrades to the subset this version understands rather than to a
// parse-time throw.
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
        if (record.properties && typeof record.properties === "object") {
            var properties = {};
            for (var name in record.properties) {
                var value = record.properties[name];
                if (value === null || value === undefined || typeof value === "object")
                    continue;
                properties[name] = String(value);
            }
            if (Object.keys(properties).length > 0)
                clean.properties = properties;
        }
        if (Object.keys(clean).length > 0)
            result[id] = clean;
    }
    return result;
}
