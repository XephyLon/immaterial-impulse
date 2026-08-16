.pragma library

// Does this launcher query want `qalc` run on it?
//
// The launcher used to answer that question by running qalc and looking at
// what came back, which meant a process per keystroke for every query the user
// typed - "firefox" spawned eight of them - and a math row rendering qalc's
// opinion of an application name. The decision has to be made before the spawn,
// and it has to be made from the query text alone, so it lives here where a
// test can reach it.
//
// Deliberately NOT an evaluator. The temptation is to answer "is this maths"
// by trying to evaluate it, and the shortest way to do that in QML is `eval()`
// behind a character whitelist - a whitelist is one edit away from being an
// arbitrary-code path, and the whole point of shelling out to qalc is that the
// expression never becomes program text here. This file only ever inspects
// characters.

// A query is only considered arithmetic if it opens like arithmetic. An
// application name cannot, so "firefox", "code" and "discord" cost nothing;
// "2+2", "(3*4)/2", "-5 C to F" and ".5 in mm" all still reach qalc.
var MATH_LEAD = /^[0-9.(+\-]/;

function _text(value) {
    return String(value === undefined || value === null ? "" : value);
}

/**
 * Whether `query` should be handed to qalc.
 *
 * The math prefix ("=" by default) is explicit intent and is honoured as long
 * as something follows it, so `=pi`, `=e^2` and `=5 kg to lb` all work even
 * though none of them opens with a digit. Without the prefix the query must
 * both open like an expression and contain a digit somewhere - "(a+b)" opens
 * like one and is not one, and qalc answers it with the query echoed back,
 * which is exactly the useless row this gate exists to stop rendering.
 */
function isMathQuery(query, mathPrefix) {
    var text = _text(query);
    var prefix = _text(mathPrefix);

    if (prefix.length > 0 && text.indexOf(prefix) === 0)
        return text.slice(prefix.length).trim().length > 0;

    var trimmed = text.trim();
    if (trimmed.length === 0)
        return false;
    if (!MATH_LEAD.test(trimmed))
        return false;
    return /[0-9]/.test(trimmed);
}

/**
 * The expression to hand to qalc, i.e. the query minus its math prefix.
 *
 * Returned as an argv element by the caller, never interpolated into a shell
 * string - `qalc -t <expr>` with the expression as its own argument, the same
 * discipline services/FileSearch.qml documents for its scan.
 */
function expressionFor(query, mathPrefix) {
    var text = _text(query);
    var prefix = _text(mathPrefix);
    if (prefix.length > 0 && text.indexOf(prefix) === 0)
        return text.slice(prefix.length);
    return text;
}
