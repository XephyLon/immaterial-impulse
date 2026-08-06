import qs.services
import QtQuick
import qs.modules.imi.onScreenDisplay

OsdValueIndicator {
    id: root
    // Clight validates temperatures to this range; the bar shows where the
    // current value sits inside it while the pill shows the real number.
    readonly property int coldest: 1000
    readonly property int warmest: 10000

    icon: "thermostat"
    name: Translation.tr("Color temperature")
    value: Math.max(0, Math.min(1, (Clight.temperature - root.coldest) / (root.warmest - root.coldest)))
    displayText: `${Clight.temperature}K`
}
