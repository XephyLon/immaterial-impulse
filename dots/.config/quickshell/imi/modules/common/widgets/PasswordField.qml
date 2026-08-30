import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The shell's masked password field: a `ToolbarTextField` whose characters are
 * drawn as `PasswordChars`' Material shapes, each animating in as it is typed.
 *
 * This exists because the shell has two password prompts - the lock screen and
 * the polkit authentication dialog - and only one of them had the glyphs. The
 * masking is not one property: it is a transparent glyph colour, a transparent
 * selection pair, an overlay Loader anchored inside the field's own padding,
 * and the config switch that decides whether any of it happens. Spelled out at
 * a call site that is five things to get right, which is why the polkit prompt
 * had none of them and showed plain bullets beside a lock screen that did not.
 *
 * The overlay is `enabled: false`, and that is load-bearing rather than tidy:
 * `PasswordChars` is a `Flickable` drawn OVER the real field, so without it the
 * click that should focus the field is eaten by the overlay and typing appears
 * to do nothing. The lock screen never met that because it focuses its field
 * programmatically; the polkit dialog is clicked.
 */
ToolbarTextField {
    id: root

    // Whether the value is hidden. A polkit flow may ask for a visible
    // response (`flow.responseVisible`), and an unmasked field shows its own
    // glyphs rather than a row of shapes standing in for them.
    property bool masked: true
    // The colour the glyphs would be drawn in if they were drawn. It is not
    // the same on both surfaces - the lock screen's field sits on layer 1 and
    // the dialog's on layer 4 - and it still has to be stated even while the
    // shapes are showing, because turning the switch off falls back to it.
    property color colText: Appearance.colors.colOnLayer1
    property int charSize: 20

    // Whether the mask is drawn as Material shapes rather than dots: a lock
    // option, handed in by the surface that reads the lock's config.
    property bool materialShapeChars: false

    echoMode: root.masked ? TextInput.Password : TextInput.Normal
    inputMethodHints: root.masked ? Qt.ImhSensitiveData : Qt.ImhNone
    clip: true

    // The real glyphs go transparent rather than away: the field is still the
    // thing holding the text, the cursor and the selection, and the shapes are
    // a picture of it.
    color: ColorUtils.transparentize(root.colText, root.materialShapeChars ? 1 : 0)
    selectedTextColor: root.materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
    selectionColor: root.materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

    Loader {
        active: root.materialShapeChars
        enabled: false
        anchors {
            fill: parent
            leftMargin: root.padding
            rightMargin: root.padding
        }
        sourceComponent: PasswordChars {
            charSize: root.charSize
            length: root.text.length
            selectionStart: root.selectionStart
            selectionEnd: root.selectionEnd
            cursorPosition: root.cursorPosition
            showCursor: root.activeFocus
        }
    }
}
