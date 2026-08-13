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
    // Set by the host while its own box is animating; the cards drop their
    // shadow for the duration rather than re-blurring into a resizing FBO.
    property bool hostBoxInMotion: false

    // Implicit size from the SPAN, and the content fills whatever the host
    // gives - the host's box is what animates a resize. The old wrapper set
    // `width: implicitWidth` on itself AND its content, so the card snapped
    // to each span's size in one frame while the host's animated box was
    // ignored: elements travelled, the card teleported (the review).
    // Both axes come off the span name. The rows half was a literal 1 while
    // every span this widget offered was one row tall; 3x2 is the first that
    // is not, and a hardcoded 1 there is a card drawing half its content
    // outside the box the host gave it.
    readonly property var spanParts: (root.hostGridSize || "3x1").split("x")
    readonly property int spanCols: parseInt(root.spanParts[0]) || 3
    readonly property int spanRows: parseInt(root.spanParts[1]) || 1
    implicitWidth: Appearance.sizes.widgetGridSpanX(root.spanCols)
    implicitHeight: Appearance.sizes.widgetGridSpanY(root.spanRows)

    Expressive.DesktopWeatherWidget {
        id: content
        anchors.fill: parent
        sizeMode: root.hostGridSize || "3x1"
        resizeBow: root.hostResizeBow
        dragging: root.hostDragging
        boxInMotion: root.hostBoxInMotion
        useBlurBackground: PluginState.option("nandoroid_weather", "blurEnabled", false)
        backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_weather")
    }
}
