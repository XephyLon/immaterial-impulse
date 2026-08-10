import QtQuick

// A consumer's claim on the cava process.
//
// `CavaService` runs cava while at least one claim is held, so a consumer
// declares one of these and binds `active` to the condition under which it is
// actually showing bands - or leaves it alone, when merely existing is that
// condition. The default is true because most consumers are built by a Loader
// or a layout entry that already gates them.
//
// It is a component rather than a pair of `refCount++`/`refCount--` lines at
// each call site because the two halves have to agree about a third thing -
// whether this consumer is currently counted - and three copies of that
// bookkeeping had already been written by hand, one of which balanced its
// increment only on destruction.
QtObject {
    id: root

    property bool active: true
    property bool held: false

    function sync() {
        if (root.active === root.held) return;
        CavaService.refCount += root.active ? 1 : -1;
        root.held = root.active;
    }

    onActiveChanged: root.sync()
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (!root.held) return;
        CavaService.refCount--;
        root.held = false;
    }
}
