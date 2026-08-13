pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.modules.common.plugins.designsystem.widgets as Expressive

Item {
    id: root

    // The host's resolved lock (PluginNode forwards AbstractBackgroundWidget's
    // `interactionLocked`). The corner handle gates on this rather than on the
    // global `background.widgetsLocked` it used to read, so a widget the user
    // pinned on its own cannot still be resized. False with no host, for a bare
    // `qs -p` probe of this file, the same as `screenName: ""`.
    property bool hostInteractionLocked: false

    // The host's drag, forwarded to the elevation so the tile lifts while it is
    // handled. A body never told about the drag silently never lifts.
    property bool hostDragging: false

    // The tile is a shape-masked image, never a rectangular card: the host's
    // frost is a rounded rectangle, so it would render as a square halo around
    // a Circle/Heart/Cookie mask. An empty region list makes PluginWidget skip
    // the blur surface entirely.
    readonly property var blurRegions: []

    readonly property string imagePath: PluginState.option("custom-image", "path", "")
    readonly property string shapeName: PluginState.option("custom-image", "shape", "Cookie4Sided")
    property bool dropHover: false
    // The resize handle assigns this directly, which breaks the binding on
    // purpose - the same trade the built-in made - and persists it on release.
    property real widgetSize: PluginState.option("custom-image", "size", 200)

    // The manifest deliberately declares no `grid`, so the host sizes itself
    // from this implicit size and the root must NOT anchor to its parent (that
    // would be a binding loop - see PluginNode.qml). Sizing ourselves is also
    // the only way to stay square and stay user-resizable: a grid span is a
    // fixed count of 132x108 cells, which is neither. See docs/widget-grid.md.
    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    function getShape(name) {
        switch (name) {
            case "Circle":        return MaterialShape.Shape.Circle
            case "Square":        return MaterialShape.Shape.Square
            case "Slanted":       return MaterialShape.Shape.Slanted
            case "Arch":          return MaterialShape.Shape.Arch
            case "Fan":           return MaterialShape.Shape.Fan
            case "Arrow":         return MaterialShape.Shape.Arrow
            case "SemiCircle":    return MaterialShape.Shape.SemiCircle
            case "Oval":          return MaterialShape.Shape.Oval
            case "Pill":          return MaterialShape.Shape.Pill
            case "Triangle":      return MaterialShape.Shape.Triangle
            case "Diamond":       return MaterialShape.Shape.Diamond
            case "ClamShell":     return MaterialShape.Shape.ClamShell
            case "Pentagon":      return MaterialShape.Shape.Pentagon
            case "Gem":           return MaterialShape.Shape.Gem
            case "Sunny":         return MaterialShape.Shape.Sunny
            case "VerySunny":     return MaterialShape.Shape.VerySunny
            case "Cookie4Sided":  return MaterialShape.Shape.Cookie4Sided
            case "Cookie6Sided":  return MaterialShape.Shape.Cookie6Sided
            case "Cookie7Sided":  return MaterialShape.Shape.Cookie7Sided
            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided
            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided
            case "Ghostish":      return MaterialShape.Shape.Ghostish
            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf
            case "Clover8Leaf":   return MaterialShape.Shape.Clover8Leaf
            case "Burst":         return MaterialShape.Shape.Burst
            case "SoftBurst":     return MaterialShape.Shape.SoftBurst
            case "Boom":          return MaterialShape.Shape.Boom
            case "SoftBoom":      return MaterialShape.Shape.SoftBoom
            case "Flower":        return MaterialShape.Shape.Flower
            case "Puffy":         return MaterialShape.Shape.Puffy
            case "PuffyDiamond":  return MaterialShape.Shape.PuffyDiamond
            case "PixelCircle":   return MaterialShape.Shape.PixelCircle
            case "PixelTriangle": return MaterialShape.Shape.PixelTriangle
            case "Bun":           return MaterialShape.Shape.Bun
            case "Heart":         return MaterialShape.Shape.Heart
            default:              return MaterialShape.Shape.Cookie4Sided
        }
    }

    // The host (PluginWidget) is the MouseArea that drags this widget; a
    // HoverHandler reads hover without taking press events away from it.
    HoverHandler {
        id: widgetHover
    }

    Item {
        id: contentItem
        implicitWidth: root.widgetSize
        implicitHeight: root.widgetSize

        Behavior on implicitWidth {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        // The tokens, not the component. The tile is a shape-masked image, and
        // WidgetCard clips its content to a rounded RECTANGLE - it says so
        // itself - so a Heart or a Cookie9Sided would be cut square. The
        // elevation has no such limit: it shadows painted alpha, so the
        // silhouette it casts is whichever shape the user picked. That also
        // retires the invisible twin the old drop shadow needed as a source.
        Expressive.WidgetElevation {
            id: shapeElevation
            anchors.fill: parent
            dragging: root.hostDragging

            MaterialShape {
                id: imageShape
                anchors.fill: parent
                z: 0
                color: Appearance.colors.colPrimaryContainer
                shape: root.getShape(root.shapeName)

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: imageShape.width
                        height: imageShape.height
                        shape: root.getShape(root.shapeName)
                    }
                }

                StyledImage {
                    anchors.fill: parent
                    source: root.imagePath !== "" ? root.imagePath : ""
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    sourceSize.width: parent.width
                    sourceSize.height: parent.height
                    visible: root.imagePath !== ""
                }

                // Placeholder + hover hint
                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: contentItem.implicitWidth / 3
                    text: root.dropHover ? "download" : "image"
                    fill: root.dropHover ? 1 : 0
                    color: root.dropHover
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnPrimaryContainer
                    visible: root.imagePath === ""
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onEntered: (drag) => {
                        drag.accept(Qt.CopyAction)
                        root.dropHover = true
                    }
                    onExited: {
                        root.dropHover = false
                    }
                    onDropped: (drop) => {
                        if (drop.hasUrls && drop.urls.length > 0) {
                            var cleanPath = drop.urls[0].toString().replace(/^file:\/\//, "")
                            var ext = cleanPath.split(".").pop().toLowerCase()
                            var accepted = ["png","jpg","jpeg","webp","avif","bmp","gif","tiff","tif"]
                            if (accepted.indexOf(ext) !== -1) {
                                PluginState.setOption("custom-image", "path", cleanPath)
                            }
                        }
                        root.dropHover = false
                    }
                }
            }
        }

        Rectangle {
            id: resizeHandle
            width: 16
            height: 16
            radius: Appearance.rounding.unsharpenslight
            color: Appearance.colors.colOnPrimaryContainer
            // The shape fills this item, so its corner is this item's corner -
            // and the shape sits inside the elevation now, which is neither
            // this handle's parent nor its sibling to anchor to.
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: Appearance.spacing.space100
            }
            opacity: (widgetHover.hovered || resizeArea.containsMouse || resizeArea.pressed) ? 0.5 : 0
            visible: opacity > 0 && !root.hostInteractionLocked
            z: 1

            Behavior on opacity {
                NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration }
            }

            MouseArea {
                id: resizeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeFDiagCursor
                preventStealing: true

                property real startSize: 0
                property real startX: 0
                property real startY: 0

                onPressed: (mouse) => {
                    startSize = root.widgetSize
                    var globalPos = mapToItem(null, mouse.x, mouse.y)
                    startX = globalPos.x
                    startY = globalPos.y
                }
                onPositionChanged: (mouse) => {
                    if (!pressed) return
                    var globalPos = mapToItem(null, mouse.x, mouse.y)
                    var delta = Math.max(globalPos.x - startX, globalPos.y - startY)
                    root.widgetSize = Math.max(80, startSize + delta)
                }
                onReleased: {
                    PluginState.setOption("custom-image", "size", root.widgetSize)
                }
            }
        }
    }
}
