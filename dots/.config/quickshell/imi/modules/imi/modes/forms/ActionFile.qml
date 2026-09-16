pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `file` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
RowLayout {
    required property var row

    spacing: Appearance.spacing.space100

    PlainField {
        Layout.fillWidth: true
        value: String(row.value ?? "")
        placeholder: Translation.tr("Absolute path to an image")
        onCommitted: v => row.setValue(v)
    }

    DialogButton {
        buttonText: Translation.tr("Use current")
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        colText: Appearance.colors.colOnSecondaryContainer
        onClicked: row.setValue(Config.options.background.wallpaperPath)
    }
}
