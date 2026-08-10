import QtQuick
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive

// The 3x2 media widget: artwork-free controls, lyrics page, wavy seek bar.
// This is the layout the widget has always had, unchanged.
Item {
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    Expressive.DesktopMediaWidget {
        id: content
        width: implicitWidth
        height: implicitHeight
        showLyrics: PluginState.option("nandoroid_media", "showLyrics", false)
        useRomaji: PluginState.option("nandoroid_media", "useRomaji", false)
        useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled", false)
        backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_media")
    }
}
