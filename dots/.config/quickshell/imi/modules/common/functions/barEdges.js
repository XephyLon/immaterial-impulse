.pragma library

// Which edge of the bar a popup opens from, and so where a widget's open-state
// indicator sits. The bar's `bottom` flag is also its side when vertical: a
// vertical bar with `bottom` set stands on the right.
function popupEdge(vertical, bottom) {
    if (vertical)
        return bottom ? "left" : "right";
    return bottom ? "top" : "bottom";
}
