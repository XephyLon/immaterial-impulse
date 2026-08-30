.pragma library

// The Material Symbol for a KDE Connect device type. One function, because
// the header chip and the roster row each carried this switch and the two
// had already diverged on what "no device" draws.
function forType(type) {
    switch (type ?? "") {
    case "phone": return "smartphone";
    case "tablet": return "tablet";
    case "laptop": return "laptop";
    case "desktop": return "computer";
    case "tv": return "tv";
    case "": return "mobile_off";
    default: return "devices";
    }
}
