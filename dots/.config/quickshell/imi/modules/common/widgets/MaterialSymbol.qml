import qs.modules.common
import QtQuick

StyledText {
    id: root

    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0

    property real resolvedFill: fill >= 0.5 ? 1.0 : 0.0

    renderType: Text.NativeRendering
    // Icon ligature names are never rich text, and some reach here from
    // attacker-controlled plugin manifests (PluginOptions feeds
    // `optionData.icon` through ConfigSwitch.buttonIcon). StyledText inherits
    // Text.AutoText, which would render "<img src=...>" as markup.
    textFormat: Text.PlainText

    font {
        hintingPreference: Font.PreferNoHinting
        family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
        pixelSize: iconSize
        weight: resolvedFill > 0.5 ? Font.DemiBold : Font.Normal
        variableAxes: {
            "FILL": resolvedFill,
            // Quantized to the axis' own integer range (Material Symbols
            // defines opsz 20-48). Every distinct axis value mints a separate
            // font engine, and icons sized by layout arithmetic produce
            // near-duplicate fractional sizes - 62 engines were live for this
            // one family. Clamping to whole numbers caps the set at 29, and
            // an optical-size step of under 1pt is not a visible difference.
            "opsz": Math.max(20, Math.min(48, Math.round(iconSize))),
        }
    }
}