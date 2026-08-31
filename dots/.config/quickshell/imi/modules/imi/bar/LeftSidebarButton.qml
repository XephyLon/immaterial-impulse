import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root
    property bool showPing: false
    property bool vertical: Config.options.bar.vertical
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool phoneEnabled: Config.options.sidebar.phone.enable
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property real buttonPadding: Appearance.spacing.space50

    visible: aiChatEnabled || translatorEnabled || animeEnabled || phoneEnabled

    implicitWidth: 32
    implicitHeight: 32

    buttonRadius: Appearance.rounding.full
    colBackground: isMaterial ? Appearance.colors.colPrimaryContainer : "transparent"
    colBackgroundHover: isMaterial ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: isMaterial ? Appearance.colors.colLayer1Active : Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarLeftOpen

    onPressed: {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }
    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    // The lit state: an expressive M3 shape grows in behind the distro
    // icon while the sidebar is open - the glyph IS the "on" light, so the
    // icon inks to onPrimary over it and the pop reverses on close.
    MaterialShape {
        id: litGlyph
        anchors.centerIn: parent
        shape: MaterialShape.Shape.Cookie6Sided
        implicitSize: 28
        color: Appearance.colors.colPrimary
        scale: root.toggled ? 1 : 0
        opacity: root.toggled ? 1 : 0
        rotation: root.toggled ? 0 : -90
        visible: opacity > 0.01
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
        }
        Behavior on rotation {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    MaterialSymbol {
        id: aiSpark
        anchors.centerIn: parent
        text: "auto_awesome"
        iconSize: 18
        fill: 1
        color: Appearance.m3colors.m3onPrimary
        scale: root.toggled ? 1 : 0
        rotation: root.toggled ? 0 : -90
        opacity: root.toggled ? 1 : 0
        visible: opacity > 0.01
        z: 2
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }
        Behavior on rotation {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    CustomIcon {
        id: distroIcon
        anchors.centerIn: parent
        width: root.isMaterial ? (root.vertical ? 24 : 22) : 19.5
        height: root.isMaterial ? (root.vertical ? 24 : 22) : 19.5
        source: Config.options.custom.distroIcon !== ""
            ? Config.options.custom.distroIcon
            : `${SystemInfo.distroIcon}.svg`
        colorize: Config.options.custom.colorizeIcon
        color: Appearance.colors.colPrimary
        // Through-zero morph: the brand mark hands the button to the AI
        // spark as the sidebar opens - distro shrinks and spins out, the
        // spark grows in over the lit glyph. Two glyph systems (an SVG and
        // a font symbol) cannot share one path, so the morph is the
        // travel: scale through zero, opposite spins, one container.
        scale: root.toggled ? 0 : 1
        rotation: root.toggled ? 90 : 0
        opacity: root.toggled ? 0 : 1
        Behavior on scale {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on rotation {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
