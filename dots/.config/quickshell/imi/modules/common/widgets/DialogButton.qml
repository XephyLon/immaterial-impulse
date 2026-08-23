import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

/**
 * Material 3 dialog button. See https://m3.material.io/components/dialogs/overview
 */
RippleButton {
    id: root

    property string buttonText
    padding: Appearance.spacing.space200
    implicitHeight: 36
    implicitWidth: buttonTextWidget.implicitWidth + padding * 2
    buttonRadius: Appearance?.rounding.full ?? 9999

    property color colEnabled: Appearance?.colors.colPrimary ?? "#65558F"
    property color colDisabled: Appearance?.m3colors.m3outline ?? "#8D8C96"
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active
    property alias colText: buttonTextWidget.color

    // Whether this action carries a container at all. Read off the fill rather
    // than set by the call site, so the one thing a caller has to do to make a
    // button the dialog's confirming action stays "give it a container".
    // `colBackground`, never `buttonColor` - the latter is transparentized
    // while the button is disabled, which would make a filled action stop
    // counting as one exactly while it waits for the response it submitted.
    readonly property bool filled: root.colBackground.a > 0

    // THE PAIRING RULE: in a dialog whose confirming action is filled, the
    // dismissing action is outlined; a dialog whose actions are all flat stays
    // flat. Two flat buttons say nothing about which one the dialog is asking
    // for, which a1e8a95a4 ("fix(polkit): the confirming action carries a
    // filled primary container") answered from the filled side - and a bare
    // label beside a filled container reads as a link rather than as the other
    // half of a choice, which is 283ada440 ("fix(editmode): the toolbar's
    // title stops reading as a button") from the other direction: the one
    // question a modal has to answer is which of these can I press.
    //
    // Derived from the row rather than hardcoded at the call site, so a dialog
    // that grows a filled confirm gets its dismissing action's edge without
    // anyone remembering to. A DialogButton outside a WindowDialogButtonRow -
    // the Wi-Fi dialog's rescan glyph - reads `undefined` and stays flat.
    property bool outlined: !root.filled && (parent?.hasFilledAction ?? false)
    border: root.outlined
    // `colOutline`, not `RippleButton`'s `colOutlineVariant` default: the
    // variant is documented as a SUBTLE boundary (docs/M3_GUIDELINES.md §1),
    // and subtle is exactly what failed here. It is also the tone the rule
    // above these buttons already draws in, so the card carries one outline
    // colour rather than two.
    colBorder: Appearance.colors.colOutline

    contentItem: StyledText {
        id: buttonTextWidget
        anchors.fill: parent
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        text: buttonText
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance?.font.pixelSize.small ?? 12
        color: root.enabled ? root.colEnabled : root.colDisabled

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
