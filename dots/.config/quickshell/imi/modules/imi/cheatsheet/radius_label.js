.pragma library

// A corner radius as a designer reads it. `Appearance.rounding.full` is 9999
// and the pressed morph takes 85% of it, so the workbench was printing
// "9999.0 -> 8499.1" on every pill - two numbers that mean one word.
function label(value) {
    if (value === undefined || value === null || isNaN(value))
        return "\u2014";
    if (value >= 999)
        return "full";
    return Number(value).toFixed(1);
}
