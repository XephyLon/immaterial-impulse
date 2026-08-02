import QtQuick
import QtQuick.Layouts
import qs.modules.common

Item {
    id: root

    property color backgroundColor: Appearance.colors.colPrimary
    property color handColor:       Appearance.colors.colOnPrimary
    property color centerDotColor:  Appearance.colors.colOnPrimary
    property string label:          ""
    property color labelColor:      Qt.rgba(
        Appearance.colors.colOnPrimary.r,
        Appearance.colors.colOnPrimary.g,
        Appearance.colors.colOnPrimary.b,
        0.75)
    property real labelSpacing: Appearance.spacing.space150

    // The dial and its label lay out inside this inset rather than against the
    // background's edge. Without it the label's top lands half a labelSpacing
    // below the dial band and its bottom lands the same distance off the
    // surface - 3px at the world clock's settings - so a labelled clock reads
    // as stuck to its own squircle.
    property real contentInset: Appearance.spacing.space100

    property real hourAngle:   0
    property real minuteAngle: 0

    property bool autoTime: true

    Timer {
        interval: 1000
        running:  root.autoTime
        repeat:   true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            const h   = now.getHours() % 12
            const m   = now.getMinutes()
            const s   = now.getSeconds()
            root.minuteAngle = m * 6 + s * 0.1
            root.hourAngle   = h * 30 + m * 0.5
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color:  root.backgroundColor
        radius: Appearance.rounding.large

        Behavior on color { ColorAnimation { duration: 400 } }
    }

    Canvas {
        id: clockCanvas
        anchors.fill: parent

        // The label used to be drawn at `cy + dotR + labelSpacing`, a few px
        // below the centre dot - but the minute hand reaches 0.82r, so at any
        // size where the label is legible the hands sweep straight through it.
        // A labelled clock therefore reserves a band at the bottom and centres
        // the dial in what is left, so the two never share the same pixels. An
        // unlabelled clock reserves nothing and is laid out exactly as before.
        readonly property real inset: root.contentInset
        readonly property real boxW:  Math.max(0, width  - inset * 2)
        readonly property real boxH:  Math.max(0, height - inset * 2)

        property real labelPixelSize: Math.max(11, Math.min(boxW, boxH) * 0.36 * 0.2)
        property real labelBand: root.label === "" ? 0 : labelPixelSize + root.labelSpacing
        property real dialHeight: boxH - labelBand

        property real cx: inset + boxW / 2
        property real cy: inset + dialHeight / 2
        property real r:  Math.min(boxW, dialHeight) * 0.36

        // Canvas text does not clip, so a city name wider than the inset box
        // would run out under the surface's rounded corners. Truncate to fit.
        function fitLabel(ctx, text, maxWidth) {
            if (maxWidth <= 0 || ctx.measureText(text).width <= maxWidth)
                return text;
            let truncated = text;
            while (truncated.length > 1
                    && ctx.measureText(truncated + "…").width > maxWidth)
                truncated = truncated.slice(0, -1);
            return truncated + "…";
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const cx = clockCanvas.cx
            const cy = clockCanvas.cy
            const r  = clockCanvas.r

            const hRad = (root.hourAngle   - 90) * Math.PI / 180
            const mRad = (root.minuteAngle - 90) * Math.PI / 180

            ctx.save()
            ctx.strokeStyle = root.handColor.toString()
            ctx.lineWidth   = Math.max(3, r * 0.095)
            ctx.lineCap     = "round"
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(
                cx + Math.cos(hRad) * r * 0.55,
                cy + Math.sin(hRad) * r * 0.55
            )
            ctx.stroke()
            ctx.restore()

            ctx.save()
            ctx.strokeStyle = root.handColor.toString()
            ctx.lineWidth   = Math.max(2, r * 0.045)
            ctx.lineCap     = "round"
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(
                cx + Math.cos(mRad) * r * 0.82,
                cy + Math.sin(mRad) * r * 0.82
            )
            ctx.stroke()
            ctx.restore()

            const dotR = Math.max(4, r * 0.055)
            ctx.beginPath()
            ctx.arc(cx, cy, dotR, 0, Math.PI * 2)
            ctx.fillStyle = root.centerDotColor.toString()
            ctx.fill()

            if (root.label !== "") {
                // Sits in the reserved band under the dial, half the label
                // spacing clear of it and a full inset clear of the bottom.
                const labelTop = clockCanvas.inset + clockCanvas.dialHeight + root.labelSpacing / 2
                ctx.font         = `${clockCanvas.labelPixelSize}px "${Appearance.font.family.main}"`
                ctx.fillStyle    = root.labelColor.toString()
                ctx.textAlign    = "center"
                ctx.textBaseline = "top"
                ctx.fillText(clockCanvas.fitLabel(ctx, root.label, clockCanvas.boxW), cx, labelTop)
            }
        }

        Connections {
            target: root
            function onHourAngleChanged()      { clockCanvas.requestPaint() }
            function onMinuteAngleChanged()    { clockCanvas.requestPaint() }
            function onLabelChanged()          { clockCanvas.requestPaint() }
            function onLabelSpacingChanged()   { clockCanvas.requestPaint() }
            function onHandColorChanged()      { clockCanvas.requestPaint() }
            function onCenterDotColorChanged() { clockCanvas.requestPaint() }
            function onLabelColorChanged()     { clockCanvas.requestPaint() }
        }

        Connections {
            target: Appearance.colors
            function onColPrimaryChanged()        { clockCanvas.requestPaint() }
            function onColOnPrimaryChanged()      { clockCanvas.requestPaint() }
        }

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
    }
}
