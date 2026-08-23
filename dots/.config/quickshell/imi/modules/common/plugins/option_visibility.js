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
//
// The lists are duck-typed, NOT Array.isArray. The manifest is parsed as
// plain JSON, but on the way to this evaluator it crosses a QVariant
// boundary (it is carried through var properties and handed to the option
// row as a Repeater's modelData), and a JS tree converted to
// QVariantMap/QVariantList reads back as wrapper objects with `length` and
// indexed access that fail Array.isArray. Measured live on the clock's
// rules in Settings > Widgets: `Array.isArray(visibleWhen.anyOf)` was false
// with `anyOf.length === 2`, so every rule fell through to the fail-open
// answer and all 22 annotated rows stayed visible for every style. The
// wrappers are also not guaranteed the Array prototype, so the walks below
// use index loops rather than some/every/indexOf.

function isList(value) {
    return Array.isArray(value)
        || (!!value && typeof value === "object" && typeof value.length === "number");
}

function visible(option, read) {
    if (typeof option.enabledWhen === "string" && !read(option.enabledWhen))
        return false;
    return rule(option.visibleWhen, read);
}

function rule(r, read) {
    if (r === undefined || r === null)
        return true;
    if (isList(r.anyOf)) {
        for (let i = 0; i < r.anyOf.length; ++i)
            if (rule(r.anyOf[i], read))
                return true;
        return false;
    }
    if (isList(r.allOf)) {
        for (let i = 0; i < r.allOf.length; ++i)
            if (!rule(r.allOf[i], read))
                return false;
        return true;
    }
    if (typeof r.key !== "string")
        return true;
    const value = read(r.key);
    if (isList(r.in)) {
        for (let i = 0; i < r.in.length; ++i)
            if (r.in[i] === value)
                return true;
        return false;
    }
    if (r.equals !== undefined)
        return value === r.equals;
    return !!value;
}
