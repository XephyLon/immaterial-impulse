.pragma library

// The set of monitors the screensaver's on-demand path is deliberately holding
// black. It lives here rather than inline in Screensaver.qml because a Scope
// built out of Quickshell types cannot be constructed by qmltestrunner, while
// every way this state can go wrong is plain set arithmetic: a name added
// twice, a monitor unplugged while it is blanked, a "blank everything" that
// only half applies.

function isBlanked(screens, name) {
    return !!name && screens.indexOf(name) !== -1;
}

function withScreen(screens, name) {
    if (!name || isBlanked(screens, name))
        return screens.slice();
    return screens.concat([name]);
}

function withoutScreen(screens, name) {
    return screens.filter(function (each) {
        return each !== name;
    });
}

function toggledScreen(screens, name) {
    if (!name)
        return screens.slice();
    return isBlanked(screens, name) ? withoutScreen(screens, name) : withScreen(screens, name);
}

// "Blank every screen" is the same list with every name in it, so the
// all-screens verb needs no second flag that could disagree with this one.
// It still has to see the idle flag: an idle-raised saver is on screen while
// this list is empty, and a toggle that ignored it would answer "everything is
// already black" with "black everything" instead of taking it down.
function toggledAll(screens, allNames, idleActive) {
    return (idleActive || screens.length > 0) ? [] : allNames.slice();
}

// A monitor unplugged while blanked takes its overlay with it, but its name
// would sit in this list forever - and the idle inhibitor derived from the
// list would be held forever with it.
function pruned(screens, liveNames) {
    return screens.filter(function (each) {
        return liveNames.indexOf(each) !== -1;
    });
}
