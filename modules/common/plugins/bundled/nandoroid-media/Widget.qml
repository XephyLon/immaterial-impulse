import QtQuick
import qs.modules.common
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive

Item {
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    width: implicitWidth
    height: implicitHeight
    Expressive.DesktopMediaWidget {
        id: content
        width: implicitWidth
        height: implicitHeight
        showLyrics: PluginState.option("nandoroid_media", "showLyrics", false)
        useRomaji: PluginState.option("nandoroid_media", "useRomaji", false)
        useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled", false)
        backgroundOpacity: Config.options.plugins.blurOpacity
    }
}
