pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Snagit-style annotation bar shown under the selected region: tools,
 * colors, stroke widths, undo/clear, then confirm/cancel.
 */
Rectangle {
    id: bar

    required property var annotationLayer
    signal confirmed()
    signal cancelled()

    readonly property var tools: [
        { id: "pen",     icon: "stylus_note",     tip: Translation.tr("Draw") },
        { id: "arrow",   icon: "north_east",      tip: Translation.tr("Arrow") },
        { id: "rect",    icon: "crop_square",     tip: Translation.tr("Box") },
        { id: "ellipse", icon: "circle",          tip: Translation.tr("Ellipse") }
    ]
    readonly property var palette: ["#ff5252", "#ffb300", "#4caf50", "#2196f3", "#ffffff", "#111111"]
    readonly property var widths: [2, 4, 8]

    implicitWidth: row.implicitWidth + Appearance.spacing.space200 * 2
    implicitHeight: 48
    radius: height / 2
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    // IconButton at the bar's own size: 36, not the 40 of the standard
    // density - the bar is a fixed 48 px pill and a 40 px circle inside it
    // leaves 4 px of rail on either side.
    component BarButton: IconButton {
        id: button
        buttonSize: 36
        iconSize: Appearance.font.pixelSize.large
        // Selecting a tool squares the circle off, which is the toolbar's
        // own answer to "which tool am I in" - so the radius stays named.
        buttonRadius: button.toggled ? Appearance.rounding.small : height / 2
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colRippleToggled: Appearance.colors.colPrimaryActive
        colText: button.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Appearance.spacing.space50

        Repeater {
            model: bar.tools
            delegate: BarButton {
                required property var modelData
                buttonIcon: modelData.icon
                tooltip: modelData.tip
                toggled: bar.annotationLayer.tool === modelData.id
                onClicked: bar.annotationLayer.tool = modelData.id
            }
        }

        Rectangle { implicitWidth: 1; implicitHeight: 24; color: Appearance.colors.colLayer0Border }

        Repeater {
            model: bar.palette
            delegate: RippleButton {
                id: colorButton
                required property string modelData
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: height / 2
                colBackground: "transparent"
                colRipple: Appearance.colors.colLayer1Active
                colBackgroundHover: Appearance.colors.colLayer1Hover
                contentItem: Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    color: colorButton.modelData
                    border.width: String(bar.annotationLayer.strokeColor) === colorButton.modelData ? 2 : 1
                    border.color: String(bar.annotationLayer.strokeColor) === colorButton.modelData
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                    scale: String(bar.annotationLayer.strokeColor) === colorButton.modelData ? 1.25 : 1
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                onClicked: bar.annotationLayer.strokeColor = colorButton.modelData
            }
        }

        Rectangle { implicitWidth: 1; implicitHeight: 24; color: Appearance.colors.colLayer0Border }

        Repeater {
            model: bar.widths
            delegate: RippleButton {
                id: widthButton
                required property int modelData
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: height / 2
                colBackground: "transparent"
                colRipple: Appearance.colors.colLayer1Active
                colBackgroundHover: Appearance.colors.colLayer1Hover
                toggled: bar.annotationLayer.strokeWidth === modelData
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                contentItem: Rectangle {
                    anchors.centerIn: parent
                    width: 4 + widthButton.modelData * 2
                    height: width
                    radius: width / 2
                    color: Appearance.colors.colOnLayer0
                }
                onClicked: bar.annotationLayer.strokeWidth = widthButton.modelData
                StyledToolTip { text: `${widthButton.modelData}px` }
            }
        }

        Rectangle { implicitWidth: 1; implicitHeight: 24; color: Appearance.colors.colLayer0Border }

        BarButton {
            buttonIcon: "undo"
            tooltip: Translation.tr("Undo")
            enabled: bar.annotationLayer.hasAnnotations
            opacity: enabled ? 1 : 0.4
            onClicked: bar.annotationLayer.undo()
        }
        BarButton {
            buttonIcon: "delete_sweep"
            tooltip: Translation.tr("Clear annotations")
            enabled: bar.annotationLayer.hasAnnotations
            opacity: enabled ? 1 : 0.4
            onClicked: bar.annotationLayer.clearAll()
        }

        Rectangle { implicitWidth: 1; implicitHeight: 24; color: Appearance.colors.colLayer0Border }

        RippleButton {
            implicitHeight: 36
            buttonRadius: height / 2
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            onClicked: bar.confirmed()
            contentItem: RowLayout {
                anchors.fill: parent
                spacing: Appearance.spacing.space50
                MaterialSymbol {
                    Layout.leftMargin: Appearance.spacing.space150
                    text: "content_copy"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnPrimary
                }
                StyledText {
                    Layout.rightMargin: Appearance.spacing.space150
                    text: Translation.tr("Copy")
                    color: Appearance.colors.colOnPrimary
                }
            }
            StyledToolTip { text: Translation.tr("Copy to clipboard (Enter)") }
        }
        BarButton {
            buttonIcon: "close"
            tooltip: Translation.tr("Cancel (Esc)")
            onClicked: bar.cancelled()
        }
    }
}
