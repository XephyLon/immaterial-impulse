pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * One condition of a mode: its summary, whether it holds right now, and —
 * unfolded — the form for its parameters. Each change is written back as
 * a whole trigger object; the engine normalizes it.
 */
Rectangle {
    id: root

    required property var trigger
    property var watcher: null
    property int triggerIndex: 0
    property bool expanded: false

    readonly property string type: root.trigger?.type ?? ""
    readonly property var condition: root.watcher?.conditionAt(root.triggerIndex) ?? null
    readonly property bool supported: root.condition?.supported ?? true
    readonly property bool misplacedEvent: root.condition?.misplacedEvent ?? false
    /// The owning mode or routine's id (shortcut triggers derive their name from it).
    property string ownerId: ""
    readonly property bool negated: root.trigger?.not === true
    readonly property int forSec: ModeSchema.durationSec(root.trigger?.forSec)
    // The verdict the engine uses (after the dwell); `counting` is the gap
    // between the condition turning true and the dwell running out.
    readonly property bool holds: root.condition ? (root.condition.ok ?? false)
        : ((root.condition?.item?.satisfied ?? false) !== root.negated)
    readonly property bool counting: root.condition?.counting ?? false
    readonly property string liveReason: root.condition?.item?.reason ?? ""

    onExpandedChanged: formLoader.sync()

    signal changed(var trigger)
    signal removeRequested()

    function set(changes) {
        root.changed(Object.assign({}, ModeSchema.clone(root.trigger), changes));
    }

    implicitHeight: column.implicitHeight + Appearance.spacing.space200
    radius: Appearance.rounding.normal
    color: headerArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    // The header is the unfold button too: a click on it, outside the
    // controls, folds the form open or shut.
    MouseArea {
        id: headerArea
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: header.height + Appearance.spacing.space200
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: Appearance.spacing.space100
            leftMargin: Appearance.spacing.space175
            rightMargin: Appearance.spacing.space100
        }
        spacing: Appearance.spacing.space100

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: Appearance.spacing.space150

            MaterialSymbol {
                text: ModeUi.triggerTypeIcon(root.type)
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: ModeUi.triggerText(root.trigger)
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: ModeUi.triggerTypeLabel(root.type)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            // Live verdict, so a mode that "should have started" is
            // diagnosable from its own row.
            Rectangle {
                visible: root.watcher !== null
                implicitWidth: verdictRow.implicitWidth + Appearance.spacing.space200
                implicitHeight: 24
                radius: Appearance.rounding.full
                color: !root.supported ? Appearance.colors.colErrorContainer
                    : (root.holds ? Appearance.colors.colPrimaryContainer
                    : (root.counting ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer3))

                MouseArea {
                    id: verdictArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                StyledToolTip {
                    extraVisibleCondition: verdictArea.containsMouse
                        && (root.liveReason.length > 0 || root.counting || root.misplacedEvent)
                    text: root.misplacedEvent
                        ? Translation.tr("A moment, not a state: only a routine of type \"When conditions become true\" can fire on it")
                        : (root.counting
                            ? Translation.tr("True right now; counts once it has held for %1").arg(ModeUi.durationText(root.forSec))
                            : root.liveReason)
                }

                RowLayout {
                    id: verdictRow
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    readonly property color fg: !root.supported ? Appearance.colors.colOnErrorContainer
                        : (root.holds ? Appearance.colors.colOnPrimaryContainer
                        : (root.counting ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSubtext))

                    MaterialSymbol {
                        text: !root.supported ? "error" : (root.holds ? "check" : (root.counting ? "timer" : "remove"))
                        iconSize: Appearance.font.pixelSize.small
                        color: verdictRow.fg
                    }

                    StyledText {
                        text: !root.supported
                            ? (root.misplacedEvent ? Translation.tr("Needs a \"when\" routine") : Translation.tr("Unsupported"))
                            : (ModeSchema.isEventTrigger(root.type)
                                ? (root.holds ? Translation.tr("Just fired") : Translation.tr("Listening"))
                                : (root.holds ? Translation.tr("Holds now")
                                : (root.counting ? Translation.tr("Counting") : Translation.tr("Not now"))))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: verdictRow.fg
                    }
                }
            }

            IconButton {
                buttonIcon: root.expanded ? "expand_less" : "expand_more"
                buttonSize: 32
                colText: Appearance.colors.colOnLayer2
                onClicked: root.expanded = !root.expanded
            }

            IconButton {
                buttonIcon: "close"
                buttonSize: 32
                colText: Appearance.colors.colOnLayer2
                onClicked: root.removeRequested()
            }
        }

        // The parameter form lives in forms/Trigger<Editor>.qml and gets this
        // row as `row`; it is created on unfold and torn down on fold.
        Loader {
            id: formLoader
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space400
            Layout.rightMargin: Appearance.spacing.space75
            visible: status === Loader.Ready && item !== null
            readonly property string formUrl: ModeUi.triggerFormUrl(root.type)
            onFormUrlChanged: formLoader.sync()

            function sync() {
                if (!root.expanded || !formLoader.formUrl.length) {
                    formLoader.source = "";
                    return;
                }
                formLoader.setSource(formLoader.formUrl, { row: root });
            }
        }

        // Every condition can be read the other way round: "Zoom is not
        // running" is how "when Zoom closes" is said. The shell's switch row
        // (icon, label, description, trailing switch; the whole row flips
        // it), on the header's columns: glyph under glyph, switch under the
        // trailing buttons - the Button's own side padding is what pushed
        // them off.
        ConfigSwitch {
            Layout.fillWidth: true
            Layout.bottomMargin: Appearance.spacing.space50
            leftPadding: 0
            rightPadding: 0
            iconSize: Appearance.font.pixelSize.huge
            visible: root.expanded
            buttonIcon: "flip"
            text: Translation.tr("Invert")
            description: root.negated ? Translation.tr("Holds while the above is not the case")
                : Translation.tr("Hold when the above is not the case instead")
            checked: root.negated
            onToggleRequested: root.set({ not: !root.negated })
        }

        // "Idle for 10 minutes", "in a game for 5 minutes": the verdict has
        // to last this long before it counts. Zero means at once. A moment
        // (an event) cannot be held.
        ConfigSwitch {
            Layout.fillWidth: true
            Layout.bottomMargin: Appearance.spacing.space50
            leftPadding: 0
            rightPadding: 0
            iconSize: Appearance.font.pixelSize.huge
            visible: root.expanded && !ModeSchema.isEventTrigger(root.type)
            buttonIcon: "hourglass_top"
            text: Translation.tr("For at least")
            description: root.forSec > 0
                ? Translation.tr("Counts only once it has held for %1 without a break").arg(ModeUi.durationText(root.forSec))
                : Translation.tr("Counts the moment it holds")
            checked: root.forSec > 0
            onToggleRequested: root.set({ forSec: root.forSec > 0 ? 0 : 300 })

            // Created on demand: a field built while hidden measures its
            // unit strip at zero width and keeps it.
            trailingContent: Loader {
                active: root.forSec > 0
                visible: active

                sourceComponent: DurationField {
                    seconds: root.forSec
                    minimum: 1
                    onCommitted: sec => root.set({ forSec: sec })
                }
            }
        }
    }
}
