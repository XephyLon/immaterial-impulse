import qs.modules.common
import QtQuick

/**
 * Drives one control through the shared interaction states.
 *
 * A control hands it `hovered`, `down` and `controlEnabled`, and reads back
 * `scale`, `radiusScale` and `dimOpacity` - all three already animated on
 * whichever transition the model chose. Nothing here decides timing; the
 * vocabulary lives in `Appearance.interaction`.
 *
 * Two things this arrangement buys, both easy to lose:
 *
 * - Interruptibility. The targets are written through Behaviors, so a press
 *   landing halfway through the hover-in RETARGETS from where the value
 *   actually is. A SequentialAnimation fired on a signal would restart from
 *   its own idea of the start value and visibly jump.
 * - The right transition. Each animation's duration and curve are set BEFORE
 *   the target is written, in the same handler, so the Behavior carries the
 *   change with the tier belonging to THAT change - not the previous one,
 *   which is what a plain binding on duration would hand it.
 *
 * A QtObject rather than an Item on purpose: `Item.state` is taken, and a
 * driver that owns a rect would tempt callers into parenting things to it.
 */
QtObject {
    id: root

    property bool hovered: false
    property bool down: false
    property bool controlEnabled: true

    readonly property string interactionState: Appearance.interaction.state({
        hovered: root.hovered, down: root.down, enabled: root.controlEnabled
    })
    property string previousState: root.interactionState

    // What the control applies. Multipliers, so a control's own geometry
    // stays its own business.
    property real scale: 1
    property real radiusScale: 1
    // The lift and the settle as plain 0..1, for feedback that is not a
    // multiple of anything - a tint wash, a stroke weight, a glyph's alpha.
    property real hoverProgress: 0
    property real pressProgress: 0
    property real dimOpacity: 1

    onInteractionStateChanged: {
        const transition = Appearance.interaction.transition(root.previousState, root.interactionState);
        root.previousState = root.interactionState;
        scaleAnim.duration = transition.duration;
        scaleAnim.easing.bezierCurve = transition.curve;
        radiusAnim.duration = transition.duration;
        radiusAnim.easing.bezierCurve = transition.curve;
        hoverAnim.duration = transition.duration;
        hoverAnim.easing.bezierCurve = transition.curve;
        pressAnim.duration = transition.duration;
        pressAnim.easing.bezierCurve = transition.curve;
        opacityAnim.duration = transition.duration;
        opacityAnim.easing.bezierCurve = transition.curve;
        root.applyTargets();
    }

    function applyTargets() {
        const targets = Appearance.interaction.targets(root.interactionState);
        root.scale = targets.scale;
        root.radiusScale = targets.radiusScale;
        root.hoverProgress = targets.hover;
        root.pressProgress = targets.press;
        root.dimOpacity = targets.opacity;
    }

    Behavior on scale {
        NumberAnimation { id: scaleAnim; easing.type: Easing.BezierSpline }
    }
    Behavior on radiusScale {
        NumberAnimation { id: radiusAnim; easing.type: Easing.BezierSpline }
    }
    Behavior on hoverProgress {
        NumberAnimation { id: hoverAnim; easing.type: Easing.BezierSpline }
    }
    Behavior on pressProgress {
        NumberAnimation { id: pressAnim; easing.type: Easing.BezierSpline }
    }
    Behavior on dimOpacity {
        NumberAnimation { id: opacityAnim; easing.type: Easing.BezierSpline }
    }

    Component.onCompleted: root.applyTargets()
}
