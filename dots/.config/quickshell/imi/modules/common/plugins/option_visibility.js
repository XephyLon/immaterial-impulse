.pragma library

// Whether a manifest option's row is shown, given the plugin's current values.
//
// Two fields on an option feed this. `enabledWhen: "<key>"` is the older one:
// a boolean key that, while off, HIDES the row - the name says "enabled" and
// the row is not greyed but gone, which is how it has always behaved and what
// the two quote rows in the clock's manifest rely on. `visibleWhen` is the
// honestly named one and can match a value, which a boolean gate cannot: the
// clock has 28 options and a `style` choice, and the eleven `cookie*` rows have
// nothing to say to someone whose clock is digital.
//
//   "visibleWhen": { "key": "style", "in": ["cookie"] }
//   "visibleWhen": { "key": "quoteEnable", "equals": true }
//   "visibleWhen": { "anyOf": [ {...}, {...} ] }      // or allOf
//
// `read(key)` returns the option's current value, resolved against the
// manifest's own default for that key, so a rule written against a default
// the user has never changed still reads the value the widget is using.
//
// A rule this cannot read - no key, or a key that is not a string - answers
// VISIBLE. Hiding is the silent failure here: a row that is wrongly hidden is
// a setting the user cannot reach and nothing logs, while a row that is
// wrongly shown is a row.

function visible(option, read) {
    if (typeof option.enabledWhen === "string" && !read(option.enabledWhen))
        return false;
    return rule(option.visibleWhen, read);
}

function rule(r, read) {
    if (r === undefined || r === null)
        return true;
    if (Array.isArray(r.anyOf))
        return r.anyOf.some(inner => rule(inner, read));
    if (Array.isArray(r.allOf))
        return r.allOf.every(inner => rule(inner, read));
    if (typeof r.key !== "string")
        return true;
    const value = read(r.key);
    if (Array.isArray(r.in))
        return r.in.indexOf(value) !== -1;
    if (r.equals !== undefined)
        return value === r.equals;
    return !!value;
}
