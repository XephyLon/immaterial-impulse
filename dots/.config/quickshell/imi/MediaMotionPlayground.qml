import QtQuick
import Quickshell
import qs
import qs.modules.common

/*
 * An isolated motion room for the media widget.
 *
 *     qs -p MediaMotionPlayground.qml
 *
 * The real one-tree widget, alone on a dark stage, with the three spans as
 * buttons - no shell, no desktop, no plugin state writes, no compositor
 * blur. The box animates the way the host animates it, so what this shows
 * is what the desktop shows, minus everything that is not the widget.
 * MprisController is live, so whatever is actually playing drives the
 * artwork, the ring and the reels.
 */
ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 720
        implicitHeight: 480
        color: "#14141c"

        // Loaded by URL: the package directory is hyphenated, which a
        // directory import cannot name (the module-directory lint's rule).
        Loader {
            id: subjectLoader
            x: 60
            y: 90
            width: item ? item.implicitWidth : 0
            height: item ? item.implicitHeight : 0
            source: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-media/Widget.qml")
            // The playground plays host: the box travels on the same curve
            // family the desktop host uses, and the span is handed over
            // instantly - what handlesSpanTransition arranges on the desktop.
            Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
            Behavior on height { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        }

        Row {
            x: 60
            y: 24
            spacing: 10
            Repeater {
                model: ["3x2", "2x2", "2x1"]
                Rectangle {
                    required property string modelData
                    width: 74; height: 34; radius: 17
                    color: subjectLoader.item && (subjectLoader.item.hostGridSize === modelData
                        || (subjectLoader.item.hostGridSize === "" && modelData === "3x2"))
                        ? "#5c8f92" : "#2a2a36"
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: "#ececf3"
                        font.family: "monospace"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (subjectLoader.item) subjectLoader.item.hostGridSize = parent.modelData
                    }
                }
            }
        }
    }
}
