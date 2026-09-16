import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The shell's pill field on the editor's card tier: boxed to a form row's
 * height with the text centred in it (the field's own all-round padding
 * would leave 12px for the glyphs and clip them), the card-tier fill, and
 * the focus ring on. PlainField, TimeField and NumberField add commit
 * semantics; the searches and the chip input's entry use it directly.
 */
ToolbarTextField {
    Layout.fillHeight: false
    implicitHeight: 36
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    // The popups this sits in scale on entry; hinted native glyphs
    // re-rasterise every frame of it.
    renderType: Text.QtRendering
    focusRing: true
    colBackground: Appearance.colors.colLayer3
    color: Appearance.colors.colOnLayer3
}
