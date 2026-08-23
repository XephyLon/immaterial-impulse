import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.modules.common

Item {
    id: root
    
    property real sides: 12  
    property int implicitSize: 100
    property real amplitude: implicitSize / 50
    property int renderPoints: 360
    property color color: "#605790"
    property alias strokeWidth: shapePath.strokeWidth
    property bool constantlyRotate: false

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    property real shapeRotation: 0

    // A 30Hz clock, not a FrameAnimation, and gated on visibility. The old
    // FrameAnimation stepped 0.05°/frame, which redrew this decorative spin
    // at the display's full refresh (240 damage events a second here) and
    // made the speed itself a function of the refresh rate - 12°/s on a
    // 240Hz panel, 3°/s on a 60Hz one. Time-based stepping at the cookie
    // clock's own motionTickHz keeps the 240Hz look's speed everywhere at an
    // eighth of the redraws, and an invisible cookie doesn't tick at all.
    Loader {
        active: root.constantlyRotate && root.visible
        sourceComponent: Timer {
            readonly property int tickHz: 30
            readonly property real degreesPerSecond: 12
            running: true
            repeat: true
            interval: Math.round(1000 / tickHz)
            onTriggered: root.shapeRotation =
                (root.shapeRotation + degreesPerSecond / tickHz) % 360
        }
    }

    Behavior on sides {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: shapePath
            strokeWidth: 0
            fillColor: root.color
            pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting

            PathPolyline {
                property var pointsList: {
                    var points = []
                    var cx = shape.width / 2   // center x
                    var cy = shape.height / 2  // center y
                    var steps = root.renderPoints
                    var radius = root.implicitSize / 2 - root.amplitude
                    for (var i = 0; i <= steps; i++) {
                        var angle = (i / steps) * 2 * Math.PI
                        var rotatedAngle = angle * root.sides + Math.PI/2 + (root.shapeRotation * root.constantlyRotate)
                        var wave = Math.sin(rotatedAngle) * root.amplitude
                        var x = Math.cos(angle) * (radius + wave) + cx
                        var y = Math.sin(angle) * (radius + wave) + cy
                        points.push(Qt.point(x, y))
                    }
                    return points
                }

                path: pointsList
            }
            
        }
    }
}
