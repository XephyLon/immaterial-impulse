pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `barDock` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: Appearance.spacing.space125

    FormChoice {
        text: Translation.tr("Bar")
        current: row.obj.bar ?? "keep"
        onPicked: v => row.patchValue({ bar: v })
        options: [
            { displayName: Translation.tr("Keep"), value: "keep" },
            { displayName: Translation.tr("Auto-hide"), value: "autoHide" },
            { displayName: Translation.tr("Always shown"), value: "fixed" }
        ]
    }

    FormChoice {
        text: Translation.tr("Dock")
        current: row.obj.dock ?? "keep"
        onPicked: v => row.patchValue({ dock: v })
        options: [
            { displayName: Translation.tr("Keep"), value: "keep" },
            { displayName: Translation.tr("Hidden"), value: "hide" },
            { displayName: Translation.tr("Shown"), value: "show" }
        ]
    }
}
