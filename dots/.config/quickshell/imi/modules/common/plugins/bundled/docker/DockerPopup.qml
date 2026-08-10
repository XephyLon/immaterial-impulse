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

    readonly property bool showPorts: PluginState.option("docker_plugin", "showPorts", true)

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
        spacing: Appearance.spacing.space150

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            MaterialShapeWrappedMaterialSymbol {
                text: "deployed_code"
                shape: MaterialShape.Shape.Cookie7Sided
                padding: Appearance.spacing.space125
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

            MaterialLoadingIndicator {
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 24
                loading: DockerService.refreshing
                visible: DockerService.refreshing
            }

            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 36
                text: "refresh"
                enabled: !DockerService.refreshing
                onClicked: DockerService.refresh()
                StyledToolTip { text: "Refresh" }
            }
            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 36
                text: "close"
                onClicked: root.pinnedOpen = false
                StyledToolTip { text: "Close" }
            }
        }

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: swipeView.currentIndex
            onCurrentIndexChanged: swipeView.currentIndex = currentIndex

            SecondaryTabButton {
                buttonIcon: "deployed_code"
                buttonText: "Containers"
            }
            SecondaryTabButton {
                buttonIcon: "account_tree"
                buttonText: "Compose"
                enabled: DockerService.composeProjects.length > 0
            }
        }

        StyledRectangle {
            // The popup sizes itself to its content, and a ColumnLayout
            // recomputes its own implicitWidth from its children - so the
            // intended popup width has to be declared on a child, not on
            // panelContent, to survive.
            Layout.fillWidth: true
            Layout.preferredWidth: 480
            Layout.preferredHeight: 440
            contentLayer: StyledRectangle.ContentLayer.Group
            radius: Appearance.rounding.normal
            clip: true

            SwipeView {
                id: swipeView
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space100
                clip: true

                CardList {
                    model: DockerService.containers
                    placeholderIcon: "deployed_code"
                    placeholderTitle: "No containers"
                    cardDelegate: root.containerCard
                }
                CardList {
                    model: DockerService.composeProjects
                    placeholderIcon: "account_tree"
                    placeholderTitle: "No Compose projects"
                    cardDelegate: root.projectCard
                }
            }
        }
    }

    // One scrolling column of cards, with the shell's empty-state placeholder
    // when the model is empty. Both tabs are the same shape, so the page is a
    // component rather than two near-identical Flickables.
    component CardList: Item {
        id: cardList
        required property var model
        required property Component cardDelegate
        required property string placeholderIcon
        required property string placeholderTitle

        // The placeholder anchors to this Item, not to the Flickable's content
        // item - an empty list has zero content height, so a placeholder inside
        // the Flickable would collapse to nothing.
        PagePlaceholder {
            shown: DockerService.dockerAvailable && cardList.model.length === 0
            icon: cardList.placeholderIcon
            title: cardList.placeholderTitle
        }

        StyledFlickable {
            id: flickable
            anchors.fill: parent
            contentWidth: width
            contentHeight: cardColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: cardColumn
                width: flickable.width
                spacing: Appearance.spacing.space100

                Repeater {
                    model: cardList.model
                    delegate: Loader {
                        required property var modelData
                        width: cardColumn.width
                        sourceComponent: cardList.cardDelegate
                        onLoaded: item.itemData = modelData
                    }
                }
            }
        }
    }

    // Card chrome only. ExpandablePanel owns the motion contract, clipping,
    // input gating and indent; this fixes the Docker-specific look on top.
    component Card: ExpandablePanel {
        property var itemData: ({})

        // Styling matches the settings page's plugin cards: no outline, the
        // hairline rule between header and detail. Only two things differ, and
        // both for a reason - the surface sits a layer deeper because these
        // cards nest inside the popup's own colLayer2 stage rather than
        // directly on a page, and the action chips stagger in.
        surfaceLayer: StyledRectangle.ContentLayer.Subgroup
        staggerStep: 40
        // The whole header toggles, with a ripple across it - the same feel as
        // the settings page, where a full-width ConfigSwitch fills the header.
        // The chevron stays as the visual affordance.
        headerClickable: true
        onHeaderClicked: expanded = !expanded
    }

    // The chevron that expands a card. `expand_more`/`expand_less` swap through
    // MaterialSymbol's own icon-change animation.
    component ExpandButton: IconToolbarButton {
        property bool expanded: false
        Layout.fillHeight: false
        implicitHeight: 36
        text: expanded ? "expand_less" : "expand_more"
    }

    component ActionButton: RippleButtonWithIcon {
        materialIconFill: false
        colBackground: Appearance.colors.colLayer2
        // The inherited ripple is tuned for colLayer1; on a colLayer2 button it
        // is nearly invisible, which reads as the button having no ripple.
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
    }

    property Component containerCard: Component {
        Card {
            id: container
            readonly property var containerData: container.itemData
            staggerTarget: containerActionFlow

            header: [
                MaterialSymbol {
                    text: container.containerData.isPaused ? "pause_circle"
                        : container.containerData.isRunning ? "check_circle" : "cancel"
                    color: container.containerData.isPaused ? Appearance.colors.colTertiary
                        : container.containerData.isRunning ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                },
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: container.containerData.name
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: `${container.containerData.status} · ${container.containerData.image}`
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                },
                ExpandButton {
                    expanded: container.expanded
                    onClicked: container.expanded = !container.expanded
                }
            ]

            StyledText {
                visible: root.showPorts && container.containerData.ports.length > 0
                text: Array.isArray(container.containerData.ports)
                    ? container.containerData.ports.join("\n") : container.containerData.ports
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            FlowButtonGroup {
                id: containerActionFlow
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50
                Repeater {
                    model: root.containerActions(container.containerData)
                    delegate: ActionButton {
                        required property var modelData
                        materialIcon: modelData.icon
                        mainText: modelData.label
                        enabled: modelData?.enabled === true
                        onClicked: root.runContainerAction(container.containerData, modelData.action)
                    }
                }
            }
        }
    }

    property Component projectCard: Component {
        Card {
            id: project
            readonly property var projectData: project.itemData
            staggerTarget: projectActionFlow

            header: [
                MaterialSymbol { text: "account_tree"; color: Appearance.colors.colPrimary },
                StyledText {
                    Layout.fillWidth: true
                    text: project.projectData.name
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                },
                StyledText {
                    text: `${project.projectData.runningCount}/${project.projectData.totalCount}`
                    color: Appearance.colors.colSubtext
                },
                ExpandButton {
                    expanded: project.expanded
                    onClicked: project.expanded = !project.expanded
                }
            ]

            FlowButtonGroup {
                id: projectActionFlow
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50
                ActionButton { materialIcon: "play_arrow"; mainText: "Up"; onClicked: DockerService.executeComposeAction(project.projectData, "up") }
                ActionButton { materialIcon: "stop"; mainText: "Stop"; onClicked: DockerService.executeComposeAction(project.projectData, "stop") }
                ActionButton { materialIcon: "restart_alt"; mainText: "Restart"; onClicked: DockerService.executeComposeAction(project.projectData, "restart") }
                ActionButton { materialIcon: "download"; mainText: "Pull"; onClicked: DockerService.executeComposeAction(project.projectData, "pull") }
                ActionButton { materialIcon: "description"; mainText: "Logs"; onClicked: DockerService.openComposeLogs(project.projectData) }
                ActionButton { materialIcon: "delete"; mainText: "Down"; onClicked: DockerService.executeComposeAction(project.projectData, "down") }
            }
        }
    }
}
