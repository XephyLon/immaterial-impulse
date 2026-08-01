import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions


DropShadow {
    required property var target
    source: target
    anchors.fill: source
    radius: 12 * Appearance.effectiveScale
    samples: 24
    color: Functions.ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.1)
    transparentBorder: true
    cached: true
}
