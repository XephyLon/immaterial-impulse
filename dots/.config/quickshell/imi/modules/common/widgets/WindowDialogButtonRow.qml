import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The action row at the foot of a `WindowDialog`, in the dialog's own content
 * box like every other row in it.
 *
 * It used to carry `Layout.margins: -Appearance.spacing.space100` to buy back
 * 8px of the card's padding. That is not free space: the row was the only child
 * of the content column that left it, so the confirming button's edge stopped
 * lining up with whatever sat above it and the card's bottom padding came out
 * 8px short of its top. Measured on the polkit prompt, the one dialog with a
 * full-width field directly over the actions - the card's four paddings read
 * 23/23/23/15 and the OK button's right edge sat 8px past the field's.
 */
RowLayout {
    id: root
    spacing: Appearance.spacing.space50

    // Whether one of these actions carries a container, which is what makes the
    // others outlined - see `DialogButton.outlined` for the rule and why it
    // lives on the row rather than at each Cancel in the tree. The row is the
    // smallest thing that can see both actions at once.
    readonly property bool hasFilledAction: {
        for (const child of root.children)
            if (child.filled === true)
                return true;
        return false;
    }
}
