import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    readonly property bool settingsNavigationSection: true
    property var shape: MaterialShape.Shape.Clover4Leaf
    property string title
    property string icon: ""
    property var bgColor: Appearance.colors.colSecondaryContainer
    // Named contentData rather than data: aliasing 'data' shadows Item's own
    // member, which Qt warns about on every instantiation.
    default property alias contentData: sectionContent.data

    // The section's place in its page's staggered entrance (see ContentPage).
    // Folded into `opacity` rather than written to it, because a wave that
    // assigns `opacity` destroys whatever binding a member had.
    property real appear: 1
    opacity: appear

    Layout.fillWidth: true
    spacing: Appearance.spacing.space100

    RowLayout {
        spacing: Appearance.spacing.space100
        MaterialShapeWrappedMaterialSymbol {
            text: root.icon
            iconSize: Appearance.font.pixelSize.large + 1
            wrappedShape: root.shape
            color: bgColor
        }
        StyledText {
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: Appearance.spacing.space50
    }
}
