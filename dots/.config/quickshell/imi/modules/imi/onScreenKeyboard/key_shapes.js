.pragma library

// A keycap's own box, in pixels. 44 rather than a round 45 so that the PITCH -
// a key plus the gap after it - is a multiple of four, and a quarter unit is
// therefore a whole number of pixels. QQuickLayout rounds every item's width
// UP, so a key whose span lands on a half pixel is drawn half a pixel wide of
// where its units put it, and fourteen spacers into the function row that is
// seven pixels of drift against the row below.
//
// They live here rather than in OskKey because osk_lattice.js derives the
// column the keys are placed on from the same two numbers, and two homes for a
// pitch is two answers to where a column starts.
const baseKeyWidth = 44;
const baseKeyHeight = 45;

// How wide and how tall every `shape` a layout in layouts.js may name is, in
// KEYBOARD UNITS - the same unit a keycap is sold in, where a plain letter is
// 1u and a US Enter is 2.25u.
//
// A unit is not a multiple of one key's width: a key spanning u units covers u
// key bodies AND the (u - 1) gaps between them, so OskKey resolves a unit
// against the row's gap as well as against the base key size. That conversion
// is what makes a row's total width depend only on the units it spans and not
// on how many keys it spent them over - which is the only reason the numpad's
// columns sit under each other when the row above them is thirteen keys and
// the row below is ten.
//
// A shape must appear in BOTH tables. A missing entry falls back to 1u with
// nothing in any log, and one row a hair narrower than the rest is a keyboard
// whose right-hand clusters drift; tst_osk_layouts.qml fails on a shape that
// is in one table only.
const widthUnits = {
    "normal": 1,
    "fn": 1,
    "empty": 0.5,
    "control": 1.25,
    "mod": 1.25,
    "shiftIso": 1.25,
    "enterIsoBottom": 1.25,
    "tab": 1.5,
    "backslash": 1.5,
    "enterIsoTop": 1.5,
    "caps": 1.75,
    "backspace": 2,
    "numpadZero": 2,
    "enter": 2.25,
    "shift": 2.25,
    "shiftRight": 2.75,
    "space": 6.25
};

// Only two shapes are not a full key tall: the function row is a short key,
// and a spacer has no height at all so it can pad any row without deciding
// how tall that row is.
const heightUnits = {
    "normal": 1,
    "fn": 0.7,
    "empty": 0,
    "control": 1,
    "mod": 1,
    "shiftIso": 1,
    "enterIsoBottom": 1,
    "tab": 1,
    "backslash": 1,
    "enterIsoTop": 1,
    "caps": 1,
    "backspace": 1,
    "numpadZero": 1,
    "enter": 1,
    "shift": 1,
    "shiftRight": 1,
    "space": 1
};
