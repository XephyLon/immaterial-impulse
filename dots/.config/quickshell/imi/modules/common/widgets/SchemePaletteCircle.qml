import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Android 12-style palette circle: top half primary, bottom quarters
 * secondary/tertiary - the palette IS the button. Falls back to the scheme's
 * icon when the color venv cannot supply swatches.
 *
 * Swatches come from SchemePreview; the caller passes the entry for its own
 * scheme so this stays a pure drawing.
 */
Item {
    id: root

    property var swatches: []
    property string fallbackIcon: ""
    property color fallbackIconColor: Appearance.colors.colOnSecondaryContainer
    property real fallbackIconSize: Appearance.font.pixelSize.huge
    property real diameter: 30

    readonly property bool painted: root.swatches.length >= 3

    implicitWidth: root.diameter
    implicitHeight: root.diameter

    onSwatchesChanged: paletteCanvas.requestPaint()

    Canvas {
        id: paletteCanvas
        anchors.centerIn: parent
        width: root.diameter
        height: root.diameter
        visible: root.painted
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const c = root.swatches
            if (c.length < 3) return
            const r = width / 2
            ctx.beginPath(); ctx.moveTo(r, r)
            ctx.arc(r, r, r, Math.PI, 2 * Math.PI); ctx.closePath()
            ctx.fillStyle = c[0]; ctx.fill()
            ctx.beginPath(); ctx.moveTo(r, r)
            ctx.arc(r, r, r, Math.PI / 2, Math.PI); ctx.closePath()
            ctx.fillStyle = c[1]; ctx.fill()
            ctx.beginPath(); ctx.moveTo(r, r)
            ctx.arc(r, r, r, 0, Math.PI / 2); ctx.closePath()
            ctx.fillStyle = c[2]; ctx.fill()
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.painted
        text: root.fallbackIcon
        iconSize: root.fallbackIconSize
        color: root.fallbackIconColor
    }
}
