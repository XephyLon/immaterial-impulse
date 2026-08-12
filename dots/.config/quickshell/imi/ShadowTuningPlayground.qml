import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell

/*
 * Pick the widget card's shadow numbers on the real wallpaper, the same way
 * the elastic-resize constants were picked: sliders, a live readout, and the
 * states side by side rather than one at a time.
 *
 *   qs -p ShadowTuningPlayground.qml
 *
 * Standalone on purpose - no Appearance, no Config, no shell singletons - so
 * it starts in a second and cannot be broken by the shell it is tuning. The
 * card here is a stand-in with the same three body renderers WidgetCard has
 * (plain rounded rect, a named shape, and a canvas), because a shadow that
 * only works under a Rectangle is not the one we need.
 */
FloatingWindow {
    id: harness
    implicitWidth: 1500
    implicitHeight: 900
    color: "#101014"

    // Tunables, all live.
    property real restBlur: 0.42
    property real restOpacity: 0.30
    property real restOffsetY: 4
    property real restScale: 1.0
    property real hoverLift: 1.6      // multiplier on blur and offset while hovered
    property real dragLift: 2.4       // ...and while dragged
    property color shadowColor: "#000000"

    readonly property string readout:
        `blur ${restBlur.toFixed(2)} opacity ${restOpacity.toFixed(2)} ` +
        `offset ${restOffsetY.toFixed(1)} scale ${restScale.toFixed(2)} ` +
        `hover ${hoverLift.toFixed(2)} drag ${dragLift.toFixed(2)}`

    // The wallpaper, so the shadow is judged over the image it will live on
    // and not over a flat grey that flatters everything.
    property string wallpaper: Quickshell.env("SHADOW_PLAYGROUND_WALL")
        || "/home/xephy/Pictures/Wallpapers/aishot-1206.jpg"

    Item {
        id: pageFrame
        anchors.fill: parent

    Image {
        anchors.fill: parent
        source: harness.wallpaper === "" ? "" : `file://${harness.wallpaper}`
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // A light patch and a dark patch: a shadow that reads well over one and
    // vanishes or smears over the other is the usual failure.
    Row {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 120
        Rectangle { width: parent.width / 2; height: parent.height; color: "#f2f0ee" }
        Rectangle { width: parent.width / 2; height: parent.height; color: "#141218" }
    }

    component TunedCard: Item {
        id: card
        property string label: ""
        property string shapeMode: "rect"   // rect | cookie | canvas
        property bool dragging: false
        width: 260
        height: 150

        property real lift: card.dragging ? harness.dragLift
            : (hoverArea.containsMouse ? harness.hoverLift : 1.0)
        Behavior on lift { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Item {
            id: body
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                visible: card.shapeMode === "rect"
                radius: 30
                color: "#2a2733"
            }

            // A stand-in for the shape body: a squircle-ish blob, to prove the
            // shadow follows painted alpha rather than a rounded rect.
            Canvas {
                anchors.fill: parent
                visible: card.shapeMode !== "rect"
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "#2a2733";
                    ctx.beginPath();
                    const lobes = card.shapeMode === "cookie" ? 8 : 4;
                    const cx = width / 2, cy = height / 2;
                    const rx = width / 2 - 6, ry = height / 2 - 6;
                    for (let i = 0; i <= 240; i++) {
                        const t = i / 240 * Math.PI * 2;
                        const wobble = 1 + 0.10 * Math.cos(lobes * t);
                        const x = cx + Math.cos(t) * rx * wobble;
                        const y = cy + Math.sin(t) * ry * wobble;
                        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
                    }
                    ctx.closePath();
                    ctx.fill();
                }
                Component.onCompleted: requestPaint()
            }

            Text {
                anchors.centerIn: parent
                text: card.label
                color: "#e8e4ef"
                font.pixelSize: 15
                font.bold: true
            }
        }

        // The shadow: one effect over whatever painted the body, so all three
        // renderers are covered by the same path.
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: harness.restBlur * card.lift
            shadowOpacity: harness.restOpacity
            shadowVerticalOffset: harness.restOffsetY * card.lift
            shadowHorizontalOffset: 0
            shadowScale: harness.restScale
            shadowColor: harness.shadowColor
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            drag.target: card
            onPressed: card.dragging = true
            onReleased: card.dragging = false
        }
    }

    Item {
        anchors.fill: parent
        anchors.topMargin: 170

        TunedCard { x: 90; y: 40; label: "rest / hover me"; shapeMode: "rect" }
        TunedCard { x: 400; y: 40; label: "drag me"; shapeMode: "rect" }
        TunedCard { x: 710; y: 40; label: "shape body"; shapeMode: "cookie" }
        TunedCard { x: 1020; y: 40; label: "shape body"; shapeMode: "blob"; width: 200 }

        // The same four again over the light strip's colour, since a shadow's
        // opacity reads completely differently there.
        Rectangle {
            x: 60; y: 260; width: 1200; height: 240; radius: 20; color: "#f2f0ee"
            TunedCard { x: 30; y: 45; label: "on light"; shapeMode: "rect" }
            TunedCard { x: 340; y: 45; label: "on light"; shapeMode: "cookie" }
        }
    }

    component Slider: RowLayout {
        property string label
        property real value
        property real from
        property real to
        property real step: 0.01
        spacing: 8
        Text { text: parent.label; color: "#cfc9d8"; font.pixelSize: 12; Layout.preferredWidth: 74 }
        Rectangle {
            Layout.preferredWidth: 190
            Layout.preferredHeight: 6
            radius: 3
            color: "#3a3543"
            Rectangle {
                width: parent.width * (parent.parent.value - parent.parent.from)
                    / Math.max(parent.parent.to - parent.parent.from, 0.0001)
                height: parent.height
                radius: 3
                color: "#b9a8e6"
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                function set(mx) {
                    const t = Math.max(0, Math.min(1, (mx - 10) / parent.width));
                    const raw = parent.parent.from + t * (parent.parent.to - parent.parent.from);
                    parent.parent.value = Math.round(raw / parent.parent.step) * parent.parent.step;
                }
                onPressed: mouse => set(mouse.x)
                onPositionChanged: mouse => { if (pressed) set(mouse.x); }
            }
        }
        Text { text: parent.value.toFixed(2); color: "#e8e4ef"; font.pixelSize: 12; Layout.preferredWidth: 40 }
    }

    // Headless review path: set SHADOW_PLAYGROUND_SHOT to grab the page and exit.
    readonly property string shotPath: Quickshell.env("SHADOW_PLAYGROUND_SHOT") || ""
    Timer {
        running: pageFrame.shotPath !== ""
        interval: 1800
        onTriggered: pageFrame.grabToImage(result => {
            result.saveToFile(pageFrame.shotPath);
            Qt.quit();
        })
    }

    Rectangle {
        anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
        width: 360
        height: controls.implicitHeight + 28
        radius: 16
        color: "#181620"
        opacity: 0.94

        ColumnLayout {
            id: controls
            anchors { fill: parent; margins: 14 }
            spacing: 6

            Text { text: "Widget card shadow"; color: "#e8e4ef"; font.pixelSize: 14; font.bold: true }
            Slider { label: "blur"; from: 0; to: 1; value: harness.restBlur
                     onValueChanged: harness.restBlur = value }
            Slider { label: "opacity"; from: 0; to: 1; value: harness.restOpacity
                     onValueChanged: harness.restOpacity = value }
            Slider { label: "offset Y"; from: 0; to: 24; step: 0.5; value: harness.restOffsetY
                     onValueChanged: harness.restOffsetY = value }
            Slider { label: "scale"; from: 0.8; to: 1.2; value: harness.restScale
                     onValueChanged: harness.restScale = value }
            Slider { label: "hover x"; from: 1; to: 3; value: harness.hoverLift
                     onValueChanged: harness.hoverLift = value }
            Slider { label: "drag x"; from: 1; to: 4; value: harness.dragLift
                     onValueChanged: harness.dragLift = value }

            Text {
                Layout.fillWidth: true
                text: harness.readout
                color: "#b9a8e6"
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                text: "Hover a card to see the hover lift; press and drag for the drag lift. Paste the line above back when the numbers feel right."
                color: "#8d8699"
                font.pixelSize: 10
                wrapMode: Text.Wrap
            }
        }
    }
    }
}
