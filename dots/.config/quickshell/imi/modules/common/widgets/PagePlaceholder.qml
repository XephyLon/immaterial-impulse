import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "../functions/placeholderFit.js" as PlaceholderFit

Item {
    id: root

    property bool shown: true
    property alias icon: shapeWidget.text
    property alias title: widgetNameText.text
    property alias description: widgetDescriptionText.text
    property alias shape: shapeWidget.shape
    property alias descriptionHorizontalAlignment: widgetDescriptionText.horizontalAlignment

    // The width the description wraps at, for a caller whose empty state is a
    // sentence rather than a word. `dropIconWhenCramped` widens this column to
    // the whole page - only so the fit decision below measures against a width
    // that cannot move under it - and a description filling that width is a
    // paragraph run edge to edge, which is a measure nobody chose. -1, the
    // default, is the column's own width: every caller that drew a two-word
    // description keeps exactly what it drew.
    property real descriptionMaximumWidth: -1

    // Drop the shape rather than let it draw outside the page when the page is
    // too short to hold the whole column - placeholderFit.js has the reasoning
    // for why the shape is what gives way. Off by default: a page with room to
    // spare wants it, since an empty state is mostly that shape. Only a page
    // squeezed by a sibling of fixed height needs this.
    property bool dropIconWhenCramped: false
    readonly property var textHeights: {
        const heights = [];
        if (widgetNameText.visible)
            heights.push(widgetNameText.implicitHeight);
        if (widgetDescriptionText.visible)
            heights.push(widgetDescriptionText.implicitHeight);
        return heights;
    }
    readonly property bool iconShown: !root.dropIconWhenCramped
        || PlaceholderFit.iconFits(root.height, shapeWidget.implicitHeight,
                                   root.textHeights, column.spacing)

    opacity: shown ? 1 : 0
    visible: opacity > 0
    anchors {
        fill: parent
        topMargin: -30 * (1 - opacity)
        bottomMargin: 30 * (1 - opacity)
    }

    Behavior on opacity {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        spacing: Appearance.spacing.space100
        // Only while measuring. A description wraps to this column's width, so
        // leaving that width to the children would let dropping the shape
        // narrow the column, reflow the description, change the height being
        // measured, and feed straight back into the decision that dropped it.
        width: root.dropIconWhenCramped ? root.width : column.implicitWidth

        MaterialShapeWrappedMaterialSymbol {
            id: shapeWidget
            visible: root.iconShown
            Layout.alignment: Qt.AlignHCenter
            padding: Appearance.spacing.space150
            iconSize: 56
            rotation: -30 * (1 - root.opacity)
        }
        StyledText {
            id: widgetNameText
            visible: title !== ""
            Layout.alignment: Qt.AlignHCenter
            font {
                family: Appearance.font.family.title
                pixelSize: Appearance.font.pixelSize.larger
                variableAxes: Appearance.font.variableAxes.title
            }
            color: Appearance.m3colors.m3outline
            horizontalAlignment: Text.AlignHCenter
        }
        StyledText {
            id: widgetDescriptionText
            visible: description !== ""
            Layout.fillWidth: true
            Layout.maximumWidth: root.descriptionMaximumWidth > 0
                ? root.descriptionMaximumWidth : Number.POSITIVE_INFINITY
            // A clamped paragraph is centred in the column rather than left
            // against its edge, or the measure reads as a ragged margin on one
            // side. Unclamped it fills, so the alignment has nothing to do.
            Layout.alignment: root.descriptionMaximumWidth > 0 ? Qt.AlignHCenter : 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3outline
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
        }
    }
}
