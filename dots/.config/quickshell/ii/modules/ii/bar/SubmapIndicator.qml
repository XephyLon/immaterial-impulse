import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Hyprland submap pill. Only visible while a keybind submap (e.g. resize) is
// active; hidden once keybinds return to the global map. Follows the
// TimerPill/PrivacyIndicator appear/disappear motion: fade + scale on the
// pill, animated width for a smooth bar reflow.
Item {
    id: root

    property bool vertical: false

    readonly property bool shown: HyprlandSubmap.active

    // Retain the last non-empty submap name so the label doesn't blank out
    // while the pill is still fading/collapsing after the submap resets.
    readonly property string submapName: HyprlandSubmap.submapName
    property string displayName: ""
    onSubmapNameChanged: {
        if (root.submapName.length > 0 && root.submapName !== "global")
            root.displayName = root.submapName;
    }

    // Vivid accent fill with its matching on-color. Use the BASE tertiary pair
    // (not the *container* variants) - the base pair is M3's high-contrast
    // pairing - and a distinct hue from the timer (primary) and privacy
    // (error) pills.
    readonly property color pillColor: Appearance.colors.colTertiary
    readonly property color onColor: Appearance.colors.colOnTertiary

    // Stay visible while collapsing so the pill can fade/scale out instead of
    // vanishing; the width still animates for a smooth bar reflow.
    visible: implicitWidth > 0
    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.barHeight
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        radius: Appearance.rounding.full
        color: root.pillColor
        // Fade + scale with the show/hide so it eases in and out.
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.7
        transformOrigin: Item.Center
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        implicitWidth: root.vertical
            ? verticalIcon.implicitWidth + Appearance.spacing.space50 * 2
            : pillRow.implicitWidth + Appearance.spacing.space150 * 2
        // Match the M3 group pill height (bar height minus BarGroup's 4px insets).
        implicitHeight: root.vertical
            ? verticalIcon.implicitHeight + Appearance.spacing.space50 * 2
            : Appearance.sizes.barStandalonePillHeight

        RowLayout {
            id: pillRow
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50
            MaterialSymbol {
                text: "keyboard"
                iconSize: Appearance.font.pixelSize.large
                color: root.onColor
            }
            StyledText {
                text: root.displayName
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.onColor
            }
        }

        // The vertical bar is too narrow for the submap name; show the icon
        // only there (matches PrivacyIndicator's icon-only vertical form).
        MaterialSymbol {
            id: verticalIcon
            visible: root.vertical
            anchors.centerIn: parent
            text: "keyboard"
            iconSize: Appearance.font.pixelSize.large
            color: root.onColor
        }
    }
}
