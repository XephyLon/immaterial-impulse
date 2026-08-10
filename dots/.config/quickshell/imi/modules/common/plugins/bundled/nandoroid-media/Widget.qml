import QtQuick
import qs.modules.common
import "media_layouts.js" as MediaLayouts

// A shell around one layout file per span.
Item {
    id: root

    // The span the host resolved, handed down by PluginNode: the stored choice,
    // then the manifest default. Empty until the host answers, and for a bare
    // `qs -p` probe of this file.
    property string hostGridSize: ""

    readonly property var span: MediaLayouts.spanFor(root.hostGridSize)

    // Not derived from the loaded layout: the manifest declares a grid, so the
    // host sizes this item to the span and fills it, and reading the item's
    // implicit size back through a filled Loader is a binding loop.
    implicitWidth: Appearance.sizes.widgetGridSpanX(root.span.cols)
    implicitHeight: Appearance.sizes.widgetGridSpanY(root.span.rows)

    readonly property var blurRegions: layout.item ? layout.item.blurRegions : []
    readonly property bool managesBlurTint: layout.item ? layout.item.managesBlurTint === true : false

    Loader {
        id: layout
        anchors.fill: parent
        source: MediaLayouts.layoutFor(root.hostGridSize)
    }
}
