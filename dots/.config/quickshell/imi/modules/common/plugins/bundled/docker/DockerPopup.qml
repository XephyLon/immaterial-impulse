pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets
import "."

StyledPopup {
    id: root

    property bool composeView: false
    property bool pendingComposeView: false
    readonly property bool showPorts: PluginState.option("docker_plugin", "showPorts", true)

    function selectView(nextComposeView) {
        if (nextComposeView === root.composeView || viewTransition.running) return;
        root.pendingComposeView = nextComposeView;
        viewTransition.restart();
    }

    onActiveChanged: {
        if (!active) return;
        panelContent.opacity = 0;
        panelContent.scale = 0.92;
        Qt.callLater(() => popupEnter.restart());
    }

    function containerActions(container) {
        return [
            { icon: container.isRunning ? "restart_alt" : "play_arrow", label: container.isRunning ? "Restart" : "Start", action: container.isRunning ? "restart" : "start", enabled: true },
            { icon: container.isPaused ? "resume" : "pause", label: container.isPaused ? "Unpause" : "Pause", action: container.isPaused ? "unpause" : "pause", enabled: container.isRunning || container.isPaused },
            { icon: "stop", label: "Stop", action: "stop", enabled: container.isRunning || container.isPaused },
            { icon: "terminal", label: "Shell", action: "exec", enabled: container.isRunning },
            { icon: "description", label: "Logs", action: "logs", enabled: true }
        ];
    }

    function runContainerAction(container, action) {
        if (action === "logs") DockerService.openLogs(container.id);
        else if (action === "exec") DockerService.openExec(container.id);
        else DockerService.executeAction(container.id, action);
    }

    ColumnLayout {
        id: panelContent
        implicitWidth: 480
        spacing: Appearance.spacing.space150
        transformOrigin: Item.Top

        // StyledPopup's default property only accepts visual items. Keep the
        // animation objects in this Item-derived content tree so they do not
        // invalidate the entire popup type at load time.
        ParallelAnimation {
            id: popupEnter
            NumberAnimation {
                target: panelContent; property: "opacity"; from: 0; to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: panelContent; property: "scale"; from: 0.92; to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        SequentialAnimation {
            id: viewTransition
            ParallelAnimation {
                NumberAnimation {
                    target: viewSurface; property: "opacity"; to: 0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                }
                NumberAnimation {
                    target: viewSurface; property: "scale"; to: 0.96
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                }
            }
            ScriptAction { script: root.composeView = root.pendingComposeView }
            ParallelAnimation {
                NumberAnimation {
                    target: viewSurface; property: "opacity"; to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                }
                NumberAnimation {
                    target: viewSurface; property: "scale"; to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            MaterialShapeWrappedMaterialSymbol {
                text: "deployed_code"
                shape: MaterialShape.Shape.Cookie7Sided
                implicitSize: 42
                iconSize: Appearance.font.pixelSize.large
                color: DockerService.dockerAvailable
                    ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer
                colSymbol: DockerService.dockerAvailable
                    ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
            }

            ColumnLayout {
                spacing: 0
                StyledText {
                    text: "Docker Manager"
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: DockerService.dockerAvailable
                        ? `${DockerService.runningCount} running · ${DockerService.totalCount} total`
                        : DockerService.lastError
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: DockerService.dockerAvailable
                        ? Appearance.colors.colSubtext : Appearance.colors.colError
                }
            }

            Item { Layout.fillWidth: true }

            ActionButton {
                iconText: DockerService.refreshing ? "progress_activity" : "refresh"
                label: "Refresh"
                animateIcon: DockerService.refreshing
                enabled: !DockerService.refreshing
                onTriggered: DockerService.refresh()
            }
            ActionButton {
                iconText: "close"
                label: "Close"
                onTriggered: root.pinnedOpen = false
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            ViewButton {
                label: "Containers"
                iconText: "deployed_code"
                selected: !root.composeView
                onTriggered: root.selectView(false)
            }
            ViewButton {
                label: "Compose"
                iconText: "account_tree"
                selected: root.composeView
                enabled: DockerService.composeProjects.length > 0
                onTriggered: root.selectView(true)
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle {
            id: viewSurface
            Layout.fillWidth: true
            Layout.preferredHeight: 440
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            clip: true

            StyledText {
                anchors.centerIn: parent
                visible: DockerService.dockerAvailable
                    && ((!root.composeView && DockerService.containers.length === 0)
                        || (root.composeView && DockerService.composeProjects.length === 0))
                text: root.composeView ? "No Compose projects" : "No containers"
                color: Appearance.colors.colSubtext
            }

            Flickable {
                id: flickable
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space100
                contentWidth: width
                contentHeight: listColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ScrollBar {}

                Column {
                    id: listColumn
                    width: flickable.width
                    spacing: Appearance.spacing.space100

                    Repeater {
                        model: root.composeView ? DockerService.composeProjects : DockerService.containers
                        delegate: Loader {
                            required property var modelData
                            width: listColumn.width
                            sourceComponent: root.composeView ? projectCard : containerCard
                            onLoaded: {
                                if (root.composeView) item.projectData = modelData;
                                else item.containerData = modelData;
                            }
                        }
                    }
                }
            }
        }
    }

    component ActionButton: RippleButton {
        id: actionButton
        property string iconText
        property string label
        property bool animateIcon: false
        readonly property color contentColor: toggled
            ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        signal triggered
        implicitWidth: contentRow.implicitWidth + Appearance.spacing.space200
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.small
        scale: down ? 0.94 : (hovered ? 1.04 : 1)
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        releaseAction: () => actionButton.triggered()
        contentItem: Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: actionButton.iconText
                iconSize: Appearance.font.pixelSize.normal
                color: actionButton.contentColor
                rotation: 0
                RotationAnimation on rotation {
                    from: 0; to: 360
                    duration: Appearance.animationCurves.expressiveSlowSpatialDuration * 2
                    loops: Animation.Infinite
                    running: actionButton.animateIcon
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: actionButton.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: actionButton.contentColor
            }
        }
    }

    component ViewButton: ActionButton {
        property bool selected: false
        toggled: selected
    }

    property Component containerCard: Component {
        Rectangle {
            id: card
            property var containerData: ({})
            property bool expanded: false
            width: parent?.width ?? 0
            implicitHeight: cardContent.implicitHeight + Appearance.spacing.space200
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer3
            border.width: Appearance.borderWidth.standard
            border.color: expanded ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
            Behavior on border.color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            ColumnLayout {
                id: cardContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Appearance.spacing.space100
                spacing: Appearance.spacing.space100

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100
                    MaterialSymbol {
                        text: card.containerData.isPaused ? "pause_circle"
                            : card.containerData.isRunning ? "check_circle" : "cancel"
                        color: card.containerData.isPaused ? Appearance.colors.colTertiary
                            : card.containerData.isRunning ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: card.containerData.name
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: `${card.containerData.status} · ${card.containerData.image}`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    ActionButton {
                        iconText: card.expanded ? "expand_less" : "expand_more"
                        label: ""
                        implicitWidth: 34
                        onTriggered: card.expanded = !card.expanded
                    }
                }

                ColumnLayout {
                    visible: card.expanded
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    StyledText {
                        visible: root.showPorts && card.containerData.ports.length > 0
                        text: Array.isArray(card.containerData.ports)
                            ? card.containerData.ports.join("\n") : card.containerData.ports
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space50
                        Repeater {
                            model: root.containerActions(card.containerData)
                            delegate: ActionButton {
                                required property var modelData
                                iconText: modelData.icon
                                label: modelData.label
                                enabled: modelData?.enabled === true
                                onTriggered: root.runContainerAction(card.containerData, modelData.action)
                            }
                        }
                    }
                }
            }
        }
    }

    property Component projectCard: Component {
        Rectangle {
            id: project
            property var projectData: ({})
            property bool expanded: false
            width: parent?.width ?? 0
            implicitHeight: projectContent.implicitHeight + Appearance.spacing.space200
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer3
            border.width: Appearance.borderWidth.standard
            border.color: expanded ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
            Behavior on border.color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            ColumnLayout {
                id: projectContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Appearance.spacing.space100
                spacing: Appearance.spacing.space100

                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol { text: "account_tree"; color: Appearance.colors.colPrimary }
                    StyledText {
                        Layout.fillWidth: true
                        text: project.projectData.name
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        text: `${project.projectData.runningCount}/${project.projectData.totalCount}`
                        color: Appearance.colors.colSubtext
                    }
                    ActionButton {
                        iconText: project.expanded ? "expand_less" : "expand_more"
                        label: ""
                        implicitWidth: 34
                        onTriggered: project.expanded = !project.expanded
                    }
                }

                Flow {
                    visible: project.expanded
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50
                    ActionButton { iconText: "play_arrow"; label: "Up"; onTriggered: DockerService.executeComposeAction(project.projectData, "up") }
                    ActionButton { iconText: "stop"; label: "Stop"; onTriggered: DockerService.executeComposeAction(project.projectData, "stop") }
                    ActionButton { iconText: "restart_alt"; label: "Restart"; onTriggered: DockerService.executeComposeAction(project.projectData, "restart") }
                    ActionButton { iconText: "download"; label: "Pull"; onTriggered: DockerService.executeComposeAction(project.projectData, "pull") }
                    ActionButton { iconText: "description"; label: "Logs"; onTriggered: DockerService.openComposeLogs(project.projectData) }
                    ActionButton { iconText: "delete"; label: "Down"; onTriggered: DockerService.executeComposeAction(project.projectData, "down") }
                }
            }
        }
    }
}
