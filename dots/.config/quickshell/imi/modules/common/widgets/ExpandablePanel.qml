pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A card whose content animates into and out of the layout, implementing the
 * Expandable Content contract in docs/M3_GUIDELINES.md so call sites do not
 * re-derive it.
 *
 * `expanded` is driven by the call site, never by this component: existing
 * surfaces trigger from a ConfigSwitch, a chevron button and nav-rail state,
 * so a built-in trigger would fit none of them.
 *
 * Plugin-facing. The property names here are a compatibility surface for
 * third-party plugins - see docs/PLUGINS.md before renaming any of them.
 */
StyledRectangle {
    id: root

    property bool expanded: false
    property alias header: headerRow.data
    default property alias content: contentColumn.data

    property int surfaceLayer: StyledRectangle.ContentLayer.Pane
    property bool outline: false
    property bool divider: true
    property bool shapeMorph: false
    property bool tonalLift: false
    property int staggerStep: 0
    // What the stagger walks. Defaults to the revealed content, but a call
    // site whose chips live inside a Flow or a layout points at that instead -
    // otherwise the stagger runs over two coarse containers and reads as
    // nothing happening.
    property Item staggerTarget: contentColumn

    // Makes the whole header a ripple surface rather than leaving interaction
    // to whatever the call site puts in it. Without this a panel whose header
    // holds only a small chevron feels dead next to one whose header is filled
    // by a ConfigSwitch, even though both are this component.
    //
    // It emits rather than assigning `expanded`: the trigger still belongs to
    // the call site, and a call site that binds `expanded` to its own state
    // would have that binding destroyed by a write from in here.
    property bool headerClickable: false
    signal headerClicked()

    // Fixed: the container needs a visible head start, otherwise staggered
    // children race the reveal instead of landing in space that exists.
    readonly property int staggerLeadIn: 120

    // Lifting is one step toward the viewer; Background (0) has nowhere to go.
    contentLayer: (root.tonalLift && root.expanded) ? Math.max(0, root.surfaceLayer - 1) : root.surfaceLayer

    implicitHeight: cardColumn.implicitHeight
    radius: (root.shapeMorph && root.expanded) ? Appearance.rounding.large : Appearance.rounding.normal
    border.width: root.outline ? Appearance.borderWidth.standard : 0
    border.color: root.expanded ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

    Behavior on radius {
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
    }
    Behavior on border.color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onStaggerStepChanged: {
        if (root.staggerStep > 0)
            return;
        const kids = (root.staggerTarget ?? contentColumn).children;
        for (let i = 0; i < kids.length; i++)
            if (kids[i].appear !== undefined)
                kids[i].appear = 1;
    }

    onExpandedChanged: {
        panel.animateTo(root.expanded);
        if (root.staggerStep > 0)
            root.runStagger();
    }

    // Children opt in by declaring `property real appear: 1` and folding it
    // into their own opacity. The stagger animates THAT, never `opacity`
    // itself: an imperative write to `opacity` destroys whatever binding the
    // child had, and RippleButton expresses its disabled state through
    // exactly that binding - so staggering used to leave every disabled
    // button looking enabled, permanently.
    function runStagger() {
        const kids = (root.staggerTarget ?? contentColumn).children;
        let index = 0;
        for (let i = 0; i < kids.length; i++) {
            if (kids[i].appear === undefined)
                continue;
            if (!root.expanded) {
                // Animate out together rather than snapping: assigning the
                // value directly meant the entrance was animated and the exit
                // was not, which reads as the content vanishing rather than
                // leaving.
                staggerFade.createObject(root, {
                    item: kids[i], delay: 0, to: 0,
                    span: Appearance.animation.elementMoveExit.duration
                }).start();
                continue;
            }
            kids[i].appear = 0;
            staggerFade.createObject(root, {
                item: kids[i], to: 1,
                span: Appearance.animation.elementMoveFast.duration,
                delay: root.staggerLeadIn + index * root.staggerStep
            }).start();
            index++;
        }
    }

    Component {
        id: staggerFade
        SequentialAnimation {
            id: seq
            property Item item
            property int delay: 0
            property real to: 1
            property int span: 200
            PauseAnimation { duration: seq.delay }
            NumberAnimation {
                target: seq.item
                property: "appear"
                to: seq.to
                duration: seq.span
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            onFinished: seq.destroy()
        }
    }

    ColumnLayout {
        id: cardColumn
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        Item {
            id: headerSlot
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + Appearance.spacing.space100 * 2

            // Behind the header content, so the header's own controls keep
            // their clicks and their own ripples.
            Loader {
                anchors.fill: parent
                active: root.headerClickable
                sourceComponent: RippleButton {
                    buttonRadius: root.radius
                    // Square the bottom corners once open so the hover and
                    // ripple meet the revealed content flush.
                    cornerBottomLeft: root.expanded ? 0 : root.radius
                    cornerBottomRight: root.expanded ? 0 : root.radius
                    Behavior on cornerBottomLeft {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on cornerBottomRight {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: root.headerClicked()
                }
            }

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space100
                spacing: Appearance.spacing.space100
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space100
            Layout.rightMargin: Appearance.spacing.space100
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            // Stays in the layout so its 1px never pops in or out; only its
            // opacity animates.
            visible: root.divider
            // Nothing to divide when the panel opens onto empty content.
            opacity: (root.expanded && panel.targetHeight > 0) ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Item {
            id: panel
            Layout.fillWidth: true
            // Leading indent only: the trailing edge stays aligned with the
            // header so nested content keeps its usable width.
            Layout.leftMargin: Appearance.spacing.space300
            Layout.rightMargin: Appearance.spacing.space100

            // The vertical insets are part of the ANIMATED height, not Layout
            // margins toggled on `expanded`. As margins they snapped in whole
            // the instant the panel opened while only the content height eased,
            // so the card jumped ~21px and then glided the rest - which reads
            // as a bounce. Folding them in means the whole thing animates.
            readonly property int verticalInset: Appearance.spacing.space100 + Appearance.spacing.space150
            // Empty content opens onto nothing, so it gets no inset either.
            // Otherwise a panel with no content still claimed its 20px of
            // padding once expanded - which is what put a band of dead space
            // under every enabled widget that happens to expose no options.
            readonly property real targetHeight: contentColumn.implicitHeight > 0
                ? contentColumn.implicitHeight + verticalInset : 0
            // Driven by the explicit animations below, not a binding. A single
            // `Behavior` whose duration and easing were ternaries on
            // `expanded` re-used the collapse parameters on the next expand -
            // the ternaries had not re-evaluated by the time the animation
            // started - so the first open decelerated correctly and every one
            // after it accelerated instead. Two animations, no ordering
            // ambiguity.
            implicitHeight: 0
            opacity: root.expanded ? 1 : 0
            enabled: root.expanded
            clip: true

            function animateTo(open) {
                expandAnim.stop();
                collapseAnim.stop();
                if (open) {
                    expandAnim.to = panel.targetHeight;
                    expandAnim.start();
                } else {
                    collapseAnim.start();
                }
            }

            // Deliberately NOT `visible: expanded || implicitHeight > 0`.
            // Qt propagates visibility to descendants, and a ColumnLayout
            // excludes invisible children - so hiding this item collapsed
            // contentColumn's implicit height to 0 while closed. The next
            // expand then animated toward a stale target and corrected
            // mid-flight, which is why the first open looked right and every
            // one after it jolted. Zero height plus clip already hides it, and
            // the content stays measured and instantiated throughout.

            NumberAnimation {
                id: expandAnim
                target: panel
                property: "implicitHeight"
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                id: collapseAnim
                target: panel
                property: "implicitHeight"
                to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }

            // A panel created in the already-expanded state never emits
            // expandedChanged, so animateTo() never runs and the panel would
            // sit at zero height with its content clipped away. Reachable
            // whenever a view rebuilds its delegates: filtering the Widgets
            // page recreates every card, and the enabled ones come back open.
            // Assigned rather than animated - a card that appears already open
            // should not play an entrance it never closed from.
            Component.onCompleted: {
                if (root.expanded)
                    panel.implicitHeight = panel.targetHeight;
            }

            // Content that grows while already open (a status line arriving,
            // say) follows without re-running the entrance.
            onTargetHeightChanged: {
                if (root.expanded && !expandAnim.running)
                    panel.implicitHeight = panel.targetHeight;
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: contentColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: Appearance.spacing.space100
                }
                spacing: Appearance.spacing.space100
            }
        }
    }
}
