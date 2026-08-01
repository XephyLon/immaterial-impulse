.pragma library

// Screen lists across this config use an empty array as the sentinel for
// "every screen" - bar.screenList, background.screenList and the desktop widget
// selectors all read `length === 0 ||` includes(name). That makes "no screens"
// unrepresentable: draining the last entry does not turn the surface off, it
// turns it back on everywhere.
//
// `toggle` therefore refuses the toggle that would empty the list and reports
// it, so the caller can restore its control instead of letting the user watch
// a switch bounce back on. Callers that want a surface disabled entirely should
// use that surface's own enable option, not an empty screen list.

// Returns { list, accepted }. `list` is the new screenList value in the same
// sentinel form the config stores ([] when every screen is selected); when
// `accepted` is false the caller should leave the config untouched.
function toggle(screenList, allNames, name, checked) {
    const selected = (screenList.length === 0) ? allNames.slice() : screenList.slice();
    let next;
    if (checked) {
        next = selected.includes(name) ? selected.slice() : selected.concat([name]);
    } else {
        next = selected.filter(entry => entry !== name);
    }
    if (next.length === 0)
        return { list: screenList, accepted: false };
    return { list: next.length === allNames.length ? [] : next, accepted: true };
}

// Whether `name` currently has the surface, under the empty-means-all rule.
function includes(screenList, name) {
    return screenList.length === 0 || screenList.includes(name);
}
