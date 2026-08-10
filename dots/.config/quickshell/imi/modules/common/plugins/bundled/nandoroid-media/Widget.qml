import QtQuick

// A shell around one layout file. The widget is content-sized, so the Loader is
// deliberately unanchored and takes its size from this item instead: anchoring
// it to a parent whose own implicit size is derived from the loaded item is the
// binding loop AGENT.md warns about.
Item {
    id: root

    readonly property var blurRegions: layout.item ? layout.item.blurRegions : []
    readonly property bool managesBlurTint: layout.item ? layout.item.managesBlurTint === true : false
    implicitWidth: layout.item ? layout.item.implicitWidth : 0
    implicitHeight: layout.item ? layout.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
        id: layout
        width: root.width
        height: root.height
        source: "LayoutLarge.qml"
    }
}
