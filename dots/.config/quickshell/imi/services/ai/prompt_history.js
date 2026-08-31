.pragma library

// Shell-style prompt recall (spec 2026-08-31), as a fold over
// { index, backup }: -1/"" is idle (the live draft). The composer applies
// the result verbatim; every decision is here, testable headless.
//
// step() returns { index, backup, text, handled }: `handled` says whether
// the key belonged to the history at all, and `text` is the composer's new
// content - null when nothing rewrites (unhandled, or Up at the oldest).

function idle() {
    return { index: -1, backup: "" };
}

function step(state, history, draft, delta) {
    var list = history || [];
    var unhandled = { index: state.index, backup: state.backup, text: null, handled: false };
    if (list.length === 0) return unhandled;
    if (state.index === -1) {
        // At the live draft: only Up enters the history, and the draft is
        // backed up so walking back down returns exactly what was typed.
        if (delta > 0) return unhandled;
        return { index: list.length - 1, backup: draft, text: list[list.length - 1], handled: true };
    }
    if (delta < 0) {
        if (state.index === 0)
            return { index: 0, backup: state.backup, text: null, handled: true };
        var older = state.index - 1;
        return { index: older, backup: state.backup, text: list[older], handled: true };
    }
    if (state.index >= list.length - 1)
        return { index: -1, backup: "", text: state.backup, handled: true };
    var newer = state.index + 1;
    return { index: newer, backup: state.backup, text: list[newer], handled: true };
}
