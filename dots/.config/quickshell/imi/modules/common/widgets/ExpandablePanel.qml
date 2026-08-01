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

    onExpandedChanged: {
        if (root.staggerStep > 0)
            root.runStagger();
    }

    function runStagger() {
        const kids = (root.staggerTarget ?? contentColumn).children;
        for (let i = 0; i < kids.length; i++) {
            if (!root.expanded) {
                // Collapsing runs everything out together - the panel's own
                // fade carries them - so reset for the next open.
                kids[i].opacity = 1;
                continue;
            }
            kids[i].opacity = 0;
            staggerFade.createObject(root, {
                item: kids[i],
                delay: root.staggerLeadIn + i * root.staggerStep
            }).start();
        }
    }

    Component {
        id: staggerFade
        SequentialAnimation {
            id: seq
            property Item item
            property int delay: 0
            PauseAnimation { duration: seq.delay }
            NumberAnimation {
                target: seq.item
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
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

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.margins: Appearance.spacing.space100
            spacing: Appearance.spacing.space100
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space100
            Layout.rightMargin: Appearance.spacing.space100
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            visible: root.divider && opacity > 0
            opacity: root.expanded ? 1 : 0
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
            Layout.topMargin: root.expanded ? Appearance.spacing.space100 : 0
            Layout.bottomMargin: root.expanded ? Appearance.spacing.space150 : 0

            implicitHeight: root.expanded ? contentColumn.implicitHeight : 0
            opacity: root.expanded ? 1 : 0
            visible: root.expanded || implicitHeight > 0
            enabled: root.expanded
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: root.expanded
                        ? Appearance.animation.elementMoveEnter.duration
                        : Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.expanded
                        ? Appearance.animation.elementMoveEnter.bezierCurve
                        : Appearance.animation.elementMoveExit.bezierCurve
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: contentColumn
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Appearance.spacing.space100
            }
        }
    }
}
