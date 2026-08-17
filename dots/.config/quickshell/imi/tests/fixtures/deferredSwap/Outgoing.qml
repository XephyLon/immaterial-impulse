import QtQuick

// Half of the pair tst_deferred_property_swap.qml swaps between. The only
// thing either one carries is a name, because what is being measured is WHEN
// the swap lands, not what is on either side of it.
Item {
    readonly property string tag: "outgoing"
}
