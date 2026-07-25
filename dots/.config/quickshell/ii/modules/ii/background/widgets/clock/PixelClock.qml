pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

Item {
    id: root

    implicitWidth: 276
    implicitHeight: 252

    readonly property string glyphTopLeft: DateTime.digitH0
    readonly property string glyphTopRight: DateTime.digitH1
    readonly property string glyphBottomLeft: DateTime.digitM0
    readonly property string glyphBottomRight: DateTime.digitM1
    readonly property color tintSoft: Appearance.colors.colPrimaryContainer
    readonly property color tintBold: Appearance.colors.colPrimary
    readonly property real fringeSize: root.width * 0.026
    readonly property real tileW: root.width * 0.66
    readonly property real tileH: root.height * 0.66
    readonly property real leftAnchor: root.width * 0.00
    readonly property real rightAnchor: root.width * 0.30
    readonly property real topAnchor: root.height * -0.04
    readonly property real bottomAnchor: root.height * 0.42
    readonly property real glyphSize: root.height * 0.66

    function ringSamples(count, radius) {
        let pts = [{ dx: 0, dy: 0 }]
        for (let i = 0; i < count; i++) {
            const a = (i / count) * Math.PI * 2
            pts.push({ dx: Math.cos(a) * radius, dy: Math.sin(a) * radius })
        }
        return pts
    }
    readonly property var fringeSamples: ringSamples(16, fringeSize)

    StyledDropShadow {
        id: glyphShadow
        target: glyphStage
        visible: Config.options.background.widgets.enableShadows ?? false
    }

    Item {
        id: glyphStage
        anchors.fill: parent

        component GlyphTile: Text {
            width: root.tileW
            height: root.tileH
            font {
                family: "Google Sans Flex"
                weight: 1200
                bold: true
                pixelSize: root.glyphSize
                variableAxes: ({ "wght": 1200 })
            }
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            id: tileAFace
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.leftAnchor
                y: root.topAnchor
                text: root.glyphTopLeft
                color: root.tintSoft
            }
        }
        Item {
            id: tileAPunch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    id: punchA
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.rightAnchor + punchA.modelData.dx; y: root.topAnchor + punchA.modelData.dy; text: root.glyphTopRight; color: "black" }
                    GlyphTile { x: root.leftAnchor + punchA.modelData.dx; y: root.bottomAnchor + punchA.modelData.dy; text: root.glyphBottomLeft; color: "black" }
                    GlyphTile { x: root.rightAnchor + punchA.modelData.dx; y: root.bottomAnchor + punchA.modelData.dy; text: root.glyphBottomRight; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: tileAFace
            maskSource: tileAPunch
            invert: true
            z: 0
        }

        Item {
            id: tileBFace
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.rightAnchor
                y: root.topAnchor
                text: root.glyphTopRight
                color: root.tintBold
            }
        }
        Item {
            id: tileBPunch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    id: punchB
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.leftAnchor + punchB.modelData.dx; y: root.bottomAnchor + punchB.modelData.dy; text: root.glyphBottomLeft; color: "black" }
                    GlyphTile { x: root.rightAnchor + punchB.modelData.dx; y: root.bottomAnchor + punchB.modelData.dy; text: root.glyphBottomRight; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: tileBFace
            maskSource: tileBPunch
            invert: true
            z: 1
        }

        Item {
            id: tileCFace
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.leftAnchor
                y: root.bottomAnchor
                text: root.glyphBottomLeft
                color: root.tintBold
            }
        }
        Item {
            id: tileCPunch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    id: punchC
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.rightAnchor + punchC.modelData.dx; y: root.bottomAnchor + punchC.modelData.dy; text: root.glyphBottomRight; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: tileCFace
            maskSource: tileCPunch
            invert: true
            z: 2
        }

        GlyphTile {
            x: root.rightAnchor
            y: root.bottomAnchor
            text: root.glyphBottomRight
            color: root.tintSoft
            z: 3
        }
    }
}