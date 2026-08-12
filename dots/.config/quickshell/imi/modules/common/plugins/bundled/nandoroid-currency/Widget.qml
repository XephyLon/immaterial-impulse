import QtQuick
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive
import "../../designsystem/services" as ExpressiveServices

Item {
    id: root
    objectName: "nandoroidCurrencyWrapper"
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    // The span the host resolved, handed down by PluginNode: stored choice,
    // then the manifest default. The host owns which size this widget is; the
    // widget owns what that size looks like. It used to own both, through a
    // `sizeMode` choice option of its own - a second mechanism for the concept
    // `__gridSize` now owns, in the same format.
    property string hostGridSize: ""
    property point hostResizeBow: Qt.point(0, 0)
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    width: implicitWidth
    height: implicitHeight
    readonly property string baseCode: PluginState.option("nandoroid_currency", "baseCurrency", "USD")
    readonly property string quoteOne: PluginState.option("nandoroid_currency", "quote1", "EUR")
    readonly property string quoteTwo: PluginState.option("nandoroid_currency", "quote2", "GBP")
    readonly property string quoteThree: PluginState.option("nandoroid_currency", "quote3", "JPY")
    readonly property string quoteFour: PluginState.option("nandoroid_currency", "quote4", "CAD")
    Binding { target: ExpressiveServices.CurrencyService; property: "baseCurrency"; value: baseCode }
    Binding { target: ExpressiveServices.CurrencyService; property: "quote1"; value: quoteOne }
    Binding { target: ExpressiveServices.CurrencyService; property: "quote2"; value: quoteTwo }
    Binding { target: ExpressiveServices.CurrencyService; property: "quote3"; value: quoteThree }
    Binding { target: ExpressiveServices.CurrencyService; property: "quote4"; value: quoteFour }
    Expressive.DesktopCurrencyWidget {
        id: content
        objectName: "nandoroidCurrencyContent"
        width: implicitWidth
        height: implicitHeight
        sizeMode: root.hostGridSize || "2x1"
        resizeBow: root.hostResizeBow
        useBlurBackground: PluginState.option("nandoroid_currency", "blurEnabled", false)
        backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_currency")
        onBaseCurrencyRequested: value => PluginState.setOption("nandoroid_currency", "baseCurrency", value)
        onQuoteCurrencyRequested: (index, value) => PluginState.setOption("nandoroid_currency", `quote${index}`, value)
    }
}
