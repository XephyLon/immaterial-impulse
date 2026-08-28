import qs.modules.common
import QtQuick

Text {
    id: root
    property bool animateChange: false
    property real animationDistanceX: 0
    property real animationDistanceY: 6

    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    // Plain text unless a site opts in: Text's inherited Text.AutoText renders
    // "<img src=...>" as markup, and StyledText is how attacker-controlled
    // plugin-manifest strings (name, description, option labels, ...) reach
    // the screen. Rich text is the reviewed exception, never the default.
    textFormat: Text.PlainText
    property bool shouldUseNumberFont: /^\d+$/.test(root.text)
    property var defaultFont: shouldUseNumberFont ? Appearance.font.family.numbers : Appearance.font.family.main
    
    font {
        hintingPreference: Font.PreferDefaultHinting
        family: defaultFont
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        variableAxes: shouldUseNumberFont ? ({}) : Appearance.font.variableAxes.main
    }
    color: Appearance?.m3colors.m3onBackground ?? "black"
    linkColor: Appearance?.m3colors.m3primary

    component Anim: NumberAnimation {
        target: root
        duration: Appearance.animation.elementMoveFaster.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animation.elementMoveFaster.bezierCurve
    }

    // The change animation moves THIS, never `root.x`/`root.y`. A layout owns
    // the position of the items it holds, so a text that animated its own x
    // had to remember where it started, and it remembered at
    // Component.onCompleted - before the layout had placed it. Every later
    // glyph swap then "returned" the item to that stale position: a ListView's
    // first delegate, built before the view had width, parked its chevron
    // mid-row the first time it was expanded. A transform is the item's own
    // and no layout writes it, so the rest position is simply zero.
    transform: Translate {
        id: textShift
    }

    Behavior on text {
        id: textAnimationBehavior
        enabled: root.animateChange

        SequentialAnimation {
            alwaysRunToEnd: true
            ParallelAnimation {
                Anim {
                    target: textShift
                    property: "x"
                    to: -root.animationDistanceX
                    easing.type: Easing.InSine
                }
                Anim {
                    target: textShift
                    property: "y"
                    to: -root.animationDistanceY
                    easing.type: Easing.InSine
                }
                Anim {
                    property: "opacity"
                    to: 0
                    easing.type: Easing.InSine
                }
            }
            PropertyAction {} // Tie the text update to this point (we don't want it to happen during the first slide+fade)
            PropertyAction {
                target: textShift
                property: "x"
                value: root.animationDistanceX
            }
            PropertyAction {
                target: textShift
                property: "y"
                value: root.animationDistanceY
            }
            ParallelAnimation {
                Anim {
                    target: textShift
                    property: "x"
                    to: 0
                    easing.type: Easing.OutSine
                }
                Anim {
                    target: textShift
                    property: "y"
                    to: 0
                    easing.type: Easing.OutSine
                }
                Anim {
                    property: "opacity"
                    to: 1
                    easing.type: Easing.OutSine
                }
            }
        }
    }
}
