import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * An icon-only button that is not in a toolbar: a glyph in a round ripple
 * surface, flat on whatever it sits on. `buttonSize` is the one knob for
 * density (40 is the standard; 32 for a dense row; 28 beside small text) -
 * the glyph size follows it. `toggled` draws the secondary-container role
 * like IconToolbarButton. Placement is the caller's.
 *
 * Forty-three call sites had each spelled this out - RippleButton, a fixed
 * square, full radius, a centred MaterialSymbol - at eight different sizes.
 * IconToolbarButton is the same control for a toolbar (it fills the
 * toolbar's height); CloseButton is this with the close glyph.
 */
RippleButton {
    id: root
    // `buttonIcon`, not `icon`: `icon` is a FINAL property of AbstractButton.
    property string buttonIcon: ""
    property real buttonSize: 40
    // Three rungs, so a 32px button keeps the `larger` glyph the rows drew
    // before (a two-rung ladder shrank sixteen of them by 3px).
    property real iconSize: root.buttonSize >= 32 ? Appearance.font.pixelSize.larger
        : root.buttonSize >= 28 ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.normal
    property real iconFill: 0
    // Opt-in: a glyph that swaps (star/star_outline, expand_less/more) slides;
    // a glyph that never changes does not carry a dormant animation tree.
    property bool animateChange: false
    property string tooltip: ""
    property color colText: root.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

    implicitWidth: root.buttonSize
    implicitHeight: root.buttonSize
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.buttonIcon
        iconSize: root.iconSize
        fill: root.iconFill
        color: root.colText
        animateChange: root.animateChange
    }

    // Built only when there is something to say: a ToolTip is a popup. Its
    // parent is the button, not the Loader, so the tooltip follows the
    // button's hover (StyledToolTip reads `parent.hovered`).
    Loader {
        active: root.tooltip.length > 0
        sourceComponent: StyledToolTip {
            parent: root
            text: root.tooltip
        }
    }
}
