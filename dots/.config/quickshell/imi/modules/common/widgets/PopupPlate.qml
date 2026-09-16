import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The plate of a standalone floating surface, once: the shell's shadow, a
 * `colLayer0` fill (the token that blurs and takes the background
 * transparency), the standard `colLayer0Border` outline and a rounded
 * corner. Content is declared inside; size and anchors are the caller's.
 *
 * Thirteen surfaces - the tray and dock menus, the two sidebars, the
 * on-screen keyboard, the drop shelf, the search widget, the screenshot
 * panel, the annotation toolbar, the Modes editor's popups - had each
 * spelled the same three lines out, and drifted on radius and border.
 * A bar island is not this: it sits on the bar's own colour and shadow
 * rules (BarContent, VerticalBarContent keep theirs).
 */
Item {
    id: root

    property real radius: Appearance.rounding.normal
    property color color: Appearance.colors.colLayer0
    property color colBorder: Appearance.colors.colLayer0Border
    property bool bordered: true
    property bool shadow: true
    // The plate itself, for a caller that clips or reads its geometry.
    readonly property alias plate: plate
    default property alias content: plate.data

    implicitWidth: plate.implicitWidth
    implicitHeight: plate.implicitHeight

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: root.radius
        color: root.color
        border.width: root.bordered ? Appearance.borderWidth.standard : 0
        border.color: root.colBorder
    }

    // Declared after the plate so `plate` exists when the shadow binds its
    // target (declared first, the Loader built it against an undefined id
    // for one frame and logged a TypeError); z puts it behind the plate.
    Loader {
        z: -1
        active: root.shadow
        anchors.fill: parent
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined
            target: plate
            visible: plate.visible
            opacity: plate.opacity
        }
    }
}
