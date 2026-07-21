import QtQuick
import qs.modules.common
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive
import "../../designsystem/services" as ExpressiveServices

Item {
    id: root
    objectName: "nandoroidCurrencyWrapper"
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
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
        sizeMode: PluginState.option("nandoroid_currency", "sizeMode", "2x1")
        useBlurBackground: PluginState.option("nandoroid_currency", "blurEnabled", false)
        backgroundOpacity: Config.options.plugins.blurOpacity
        onBaseCurrencyRequested: value => PluginState.setOption("nandoroid_currency", "baseCurrency", value)
        onQuoteCurrencyRequested: (index, value) => PluginState.setOption("nandoroid_currency", `quote${index}`, value)
        onSizeModeRequested: value => PluginState.setOption("nandoroid_currency", "sizeMode", value)
    }
}
