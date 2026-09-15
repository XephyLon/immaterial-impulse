import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The banner itself: the mode's glyph on its colour, a title and a line
 * that says why. Slides down from the top edge (the enter tier) and back
 * up (the exit tier).
 */
Item {
    id: root

    property bool isOpen: false
    property var payload: null
    property real topMarginValue: 0
    readonly property bool isExitAnimRunning: exitAnim.running

    // The payload is cleared by the engine only when the next one arrives,
    // so the exit animation keeps its text.
    readonly property string colorKey: root.payload?.color ?? ""
    readonly property string icon: root.payload?.icon ?? "tune"
    readonly property string title: root.payload?.title ?? ""
    readonly property string subtitle: root.payload?.subtitle ?? ""

    onIsOpenChanged: {
        if (isOpen) {
            exitAnim.stop();
            entranceAnim.start();
        } else {
            entranceAnim.stop();
            exitAnim.start();
        }
    }

    // A new payload while open: pulse the glyph so the change registers.
    onPayloadChanged: {
        if (root.isOpen)
            iconPulse.restart();
    }

    readonly property real horizontalPadding: Appearance.spacing.space250
    readonly property real bannerHeight: Appearance.sizes.barStandalonePillHeight + Appearance.spacing.space400

    implicitWidth: Math.min(520, contentLayout.implicitWidth + 2 * horizontalPadding) + 2 * Appearance.sizes.elevationMargin
    implicitHeight: bannerHeight + 2 * Appearance.sizes.elevationMargin

    property alias staticMaskTarget: staticMaskTarget
    property alias background: contentBackground
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
    }

    StyledRectangularShadow {
        target: contentBackground
        opacity: contentBackground.opacity
        transform: Translate {
            y: contentBackground.yOffset
        }
    }

    Rectangle {
        id: contentBackground

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: root.topMarginValue + Appearance.sizes.elevationMargin
        }

        width: parent.width - 2 * Appearance.sizes.elevationMargin
        height: root.bannerHeight
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer0

        readonly property real slideOffset: -(root.topMarginValue + Appearance.sizes.elevationMargin + height + Appearance.spacing.space500)
        opacity: 0
        property real yOffset: slideOffset

        transform: Translate {
            y: contentBackground.yOffset
        }

        ParallelAnimation {
            id: entranceAnim
            NumberAnimation {
                target: contentBackground
                property: "yOffset"
                from: contentBackground.slideOffset
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }

        ParallelAnimation {
            id: exitAnim
            NumberAnimation {
                target: contentBackground
                property: "yOffset"
                to: contentBackground.slideOffset
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
        }

        RowLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: root.horizontalPadding
                rightMargin: root.horizontalPadding
            }
            spacing: Appearance.spacing.space175

            MaterialShapeWrappedMaterialSymbol {
                id: iconShape
                shape: MaterialShape.Shape.Cookie12Sided
                text: root.icon
                iconSize: Appearance.font.pixelSize.larger
                implicitSize: 44
                color: ModeUi.container(root.colorKey)
                colSymbol: ModeUi.onContainer(root.colorKey)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    SequentialAnimation {
        id: iconPulse
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.25
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.0
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
}
