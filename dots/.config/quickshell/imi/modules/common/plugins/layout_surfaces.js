.pragma library

// Two widget layouts, one store: the desktop's and the lock screen's, and the
// rule by which the second inherits the first until it is edited.
//
// Spec §4.3 chose ONE stored position per widget, shared by both surfaces, and
// gave two reasons - a second position doubles the placement model, and
// presets capture positions wholesale. The maintainer overruled it on
// 2026-08-18: "lockscreen widget layout is meant to be different from desktop
// layout if the user decides to alter the widgets and their order in
// lockscreen." The `if` is load-bearing and is what this module encodes.
//
// FORK ON FIRST EDIT. `lockPositions` sits beside `desktopPositions` with the
// same [screen][pluginId] shape, and a screen ABSENT from it means "the lock
// shows the desktop's layout" - the spec's model is still the state every
// user is in until they move something on the Lockscreen tab. The first lock
// write for a screen copies that screen's whole desktop layout across before
// applying the move, so the fork is a snapshot: after it, every widget on that
// screen follows the lock store, none half-follows the desktop. Deleting the
// screen's entry re-links it.
//
// Pure, .pragma library, no QML: the decisions here are the ones that would
// otherwise be reachable only through a running PluginState with a file behind
// it, and tst_layout_surfaces.qml drives every branch bare. PluginState is the
// caller that turns "the lock look is on" into a surface name and writes the
// result to disk.

var DESKTOP = "desktop";
var LOCK = "lock";

// Which store a surface name reads. Anything that is not the lock is the
// desktop, so a caller that passes nothing gets the desktop, which is what
// every pre-fork call site meant.
function storeKey(surface) {
    return surface === LOCK ? "lockPositions" : "desktopPositions";
}

// Has this screen's lock layout been forked from the desktop's?
function isForked(state, screenName) {
    var lock = state && state.lockPositions;
    return !!(lock && typeof lock === "object" && lock[screenName]
        && typeof lock[screenName] === "object");
}

// The raw stored entry for a widget on a surface, or undefined. On the lock
// surface an unforked screen READS THROUGH to the desktop - that is the
// inheritance - and a forked one reads only its own store, so a widget added
// to the desktop after the fork is absent from the lock rather than leaking
// in at the desktop's position. `undefined` here is what a caller normalises
// to the default; the distinction between "absent" and "at the default"
// matters to undo, which is why this returns the raw value.
function rawPosition(state, surface, screenName, pluginId) {
    if (!state || !screenName || !pluginId)
        return undefined;
    if (surface === LOCK && isForked(state, screenName)) {
        var lockScreen = state.lockPositions[screenName];
        return lockScreen[pluginId];
    }
    var desktop = state.desktopPositions;
    var desktopScreen = desktop && typeof desktop === "object" ? desktop[screenName] : undefined;
    return desktopScreen && typeof desktopScreen === "object" ? desktopScreen[pluginId] : undefined;
}

// A widget's SPAN is part of its layout, and it forks with the position -
// the maintainer's second report was a media widget at 3x2 on the desktop
// and 1x2 on the lock, which one shared span cannot hold. On the desktop the
// span stays where it has always been, `pluginOptions[id].__gridSize`, which
// is per plugin and not per screen (a widget is one size on every desktop).
// On a FORKED lock screen it lives IN the widget's lock record as
// `gridSize`, beside x and y: the record is already the per-surface,
// per-screen thing, and the fork snapshot copies the current span into each
// record so a freshly forked screen looks exactly like the desktop did.
//
// A lock record WITHOUT `gridSize` (a fork made before this key existed, or
// a preset from that shell) reads through to the desktop's option, so it
// still inherits rather than dropping to the manifest default.
function rawGridSize(state, surface, screenName, pluginId) {
    if (surface === LOCK && isForked(state, screenName)) {
        var record = state.lockPositions[screenName][pluginId];
        if (record && typeof record === "object" && record.gridSize !== undefined)
            return record.gridSize;
    }
    var options = state && state.pluginOptions;
    var plugin = options && typeof options === "object" ? options[pluginId] : undefined;
    return plugin && typeof plugin === "object" ? plugin.__gridSize : undefined;
}

// The fork itself: a fresh lock screen seeded from the desktop's records,
// each carrying the span the widget currently has. Shared by both writers
// below so the two cannot disagree about what a fork copies.
function forkedScreen(state, screenName) {
    var desktopScreen = (state && state.desktopPositions
        && state.desktopPositions[screenName]) || {};
    var screen = {};
    for (var pluginId in desktopScreen) {
        var record = Object.assign({}, desktopScreen[pluginId]);
        var span = rawGridSize(state, DESKTOP, screenName, pluginId);
        if (span !== undefined)
            record.gridSize = span;
        screen[pluginId] = record;
    }
    return screen;
}

// The next state after writing one widget's position on one surface. Returns
// a NEW top-level object and never mutates the one passed in - PluginState
// reassigns `state` wholesale so bindings notice, and a mutated-in-place
// object is one they would not.
//
// A lock write on an unforked screen forks it first, then the write lands.
// The position value REPLACES x/y/placementStrategy and keeps whatever
// gridSize the record already carried: a move is not a resize.
function withPosition(state, surface, screenName, pluginId, value) {
    var next = Object.assign({}, state || {});
    var key = storeKey(surface);
    var store = Object.assign({}, next[key] || {});
    var screen = (surface === LOCK && !isForked(state, screenName))
        ? forkedScreen(state, screenName)
        : Object.assign({}, store[screenName] || {});
    var previous = screen[pluginId];
    var record = Object.assign({}, value);
    if (surface === LOCK && previous && typeof previous === "object"
            && previous.gridSize !== undefined && record.gridSize === undefined)
        record.gridSize = previous.gridSize;
    screen[pluginId] = record;
    store[screenName] = screen;
    next[key] = store;
    return next;
}

// The next state after writing one widget's span on one surface. On the
// desktop this is the plugin option, unchanged from before the fork existed
// (null removes, as PluginState.setOption always meant). On the lock it
// forks the screen if needed and writes `gridSize` into the widget's record
// - creating a position-less record if the widget has none there yet, which
// rawPosition then answers as the default position; that only happens for a
// widget added to the desktop after the fork, and is the same "absent" the
// position side already reports for it.
function withGridSize(state, surface, screenName, pluginId, value) {
    var next = Object.assign({}, state || {});
    if (surface !== LOCK) {
        var options = Object.assign({}, next.pluginOptions || {});
        var plugin = Object.assign({}, options[pluginId] || {});
        if (value === null || value === undefined) delete plugin.__gridSize;
        else plugin.__gridSize = value;
        options[pluginId] = plugin;
        next.pluginOptions = options;
        return next;
    }
    var store = Object.assign({}, next.lockPositions || {});
    var screen = isForked(state, screenName)
        ? Object.assign({}, store[screenName] || {})
        : forkedScreen(state, screenName);
    var record = Object.assign({}, screen[pluginId] || {});
    if (value === null || value === undefined) delete record.gridSize;
    else record.gridSize = value;
    screen[pluginId] = record;
    store[screenName] = screen;
    next.lockPositions = store;
    return next;
}

// The next state after re-linking a screen's lock layout to the desktop's:
// the screen's lock entry is removed, and rawPosition reads through again.
// A screen that was never forked is returned unchanged (same object), so a
// caller can tell a no-op from a change by identity.
function withoutLockLayout(state, screenName) {
    if (!isForked(state, screenName))
        return state;
    var next = Object.assign({}, state);
    var lock = Object.assign({}, state.lockPositions);
    delete lock[screenName];
    next.lockPositions = lock;
    return next;
}
