import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

StyledText {
    id: root

    // Handed down rather than read here. "Follow clock font" and "animate time
    // change" are single options shared by every text in the widget, and this
    // component is instantiated in five places across two files - reading them
    // per instance would put the same PluginState default in five files.
    property string clockFontFamily: Appearance.font.family.expressive

    Layout.fillWidth: true
    font {
        family: root.clockFontFamily
        pixelSize: 20
        weight: 350
        // Set empty to prevent conflicts, not meaningless
        styleName: ""
        variableAxes: ({})
    }
    style: Text.Raised
    styleColor: Appearance.colors.colShadow
}
