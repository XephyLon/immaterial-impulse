import QtQuick
import qs.modules.common
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive

Item {
    id: root
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    // The span the host resolved, handed down by PluginNode: stored choice,
    // then the manifest default. The host owns which size this widget is; the
    // widget owns what that size looks like.
    property string hostGridSize: ""
    // One tree below: the shared elements travel and the glyph container
    // morphs, so the host's midpoint dissolve would put a fade over elements
    // that deliberately never disappear.
    readonly property bool handlesSpanTransition: true
    property point hostResizeBow: Qt.point(0, 0)
    // Set by the host while this widget is being dragged; the cards lift.
    property bool hostDragging: false

    // Implicit size from the SPAN, and the content fills whatever the host
    // gives - the host's box is what animates a resize. The old wrapper set
    // `width: implicitWidth` on itself AND its content, so the card snapped
    // to each span's size in one frame while the host's animated box was
    // ignored: elements travelled, the card teleported (the review).
    readonly property int spanCols: parseInt((root.hostGridSize || "3x1")[0]) || 3
    implicitWidth: Appearance.sizes.widgetGridSpanX(root.spanCols)
    implicitHeight: Appearance.sizes.widgetGridSpanY(1)

    Expressive.DesktopWeatherWidget {
        id: content
        anchors.fill: parent
        sizeMode: root.hostGridSize || "3x1"
        resizeBow: root.hostResizeBow
        dragging: root.hostDragging
        useBlurBackground: PluginState.option("nandoroid_weather", "blurEnabled", false)
        backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_weather")
    }
}
