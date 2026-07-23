import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    signal projectSelected(var project)

    property int columns: Config.options.wallpaperSelector.columns || 4
    property real previewCellAspectRatio: 4 / 3
    property string searchQuery: ""
    property string typeFilter: "all"
    // Distinct wallpaper types present in the library (scene/video/web/...),
    // sorted, used to build the filter chip row. Blank types are ignored.
    readonly property var availableTypes: {
        const seen = ({});
        for (const p of WallpaperEngine.projects) {
            const t = (p.type ?? "").toString().trim();
            if (t) seen[t] = true;
        }
        return Object.keys(seen).sort();
    }
    readonly property var filteredProjects: WallpaperEngine.projects.filter(project => {
        if (root.typeFilter !== "all" && (project.type ?? "") !== root.typeFilter) return false;
        const query = root.searchQuery.trim().toLowerCase();
        if (!query) return true;
        const tags = Array.isArray(project.tags) ? project.tags.join(" ") : "";
        return `${project.title} ${project.id} ${project.type} ${tags}`.toLowerCase().includes(query);
    })
    property real cellWidth: grid.cellWidth
    property real cellHeight: grid.cellHeight

    function typeIcon(t) {
        return t === "video" ? "movie" : (t === "web" ? "web" : "animation");
    }

    function moveSelection(delta) { grid.moveSelection(delta); }
    function activateCurrent() { grid.activateCurrent(); }

    // Type filter chips (All / Scene / Video / Web / ...). Only shown when the
    // library actually spans more than one type. Combined with searchQuery.
    RowLayout {
        id: filterRow
        visible: root.availableTypes.length > 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Appearance.sizes.wallpaperSelectorItemMargins
        spacing: 0

        Repeater {
            model: [({ value: "all", text: Translation.tr("All"), icon: "filter_list" })].concat(
                root.availableTypes.map(t => ({
                    value: t,
                    text: t.charAt(0).toUpperCase() + t.slice(1),
                    icon: root.typeIcon(t)
                })))
            delegate: SelectionGroupButton {
                required property var modelData
                required property int index
                leftmost: index === 0
                rightmost: index === root.availableTypes.length
                toggled: root.typeFilter === modelData.value
                buttonIcon: modelData.icon
                buttonText: modelData.text
                onClicked: root.typeFilter = modelData.value
            }
        }
        Item { Layout.fillWidth: true }
    }

    GridView {
        id: grid
        anchors.top: filterRow.visible ? filterRow.bottom : parent.top
        anchors.topMargin: filterRow.visible ? Appearance.spacing.space100 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        model: root.filteredProjects
        cellWidth: width / root.columns
        cellHeight: cellWidth / root.previewCellAspectRatio
        clip: true
        interactive: true
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: 0
        ScrollBar.vertical: StyledScrollBar {}

        function moveSelection(delta) {
            currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
            positionViewAtIndex(currentIndex, GridView.Contain);
        }

        function activateCurrent() {
            if (currentIndex >= 0 && currentIndex < root.filteredProjects.length)
                root.projectSelected(root.filteredProjects[currentIndex]);
        }

        delegate: MouseArea {
            id: delegateRoot
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: grid.currentIndex = index
            onClicked: root.projectSelected(modelData)

            Rectangle {
                anchors.fill: parent
                anchors.margins: Appearance.sizes.wallpaperSelectorItemMargins
                radius: Appearance.rounding.normal
                color: delegateRoot.modelData.id === Config.options.wallpaperSelector.wallpaperEngine.activeProject
                    ? Appearance.colors.colSecondaryContainer
                    : (delegateRoot.containsMouse || delegateRoot.index === grid.currentIndex)
                        ? Appearance.colors.colPrimaryContainer
                        : ColorUtils.transparentize(Appearance.colors.colLayer1)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.wallpaperSelectorItemPadding
                    spacing: Appearance.spacing.space50

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        clip: true

                        StyledImage {
                            anchors.fill: parent
                            source: delegateRoot.modelData.preview
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: Appearance.spacing.space75
                            implicitWidth: typeRow.implicitWidth + Appearance.spacing.space150
                            implicitHeight: typeRow.implicitHeight + Appearance.spacing.space75
                            radius: height / 2
                            color: Appearance.colors.colSurfaceContainerHigh

                            RowLayout {
                                id: typeRow
                                anchors.centerIn: parent
                                spacing: Appearance.spacing.space50
                                MaterialSymbol {
                                    text: delegateRoot.modelData.type === "video" ? "movie" : "animation"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    text: delegateRoot.modelData.type
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                        }

                        MaterialSymbol {
                            visible: delegateRoot.modelData.id === Config.options.wallpaperSelector.wallpaperEngine.activeProject
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Appearance.spacing.space75
                            text: "check_circle"
                            fill: 1
                            color: Appearance.colors.colPrimary
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.spacing.space100
                        Layout.rightMargin: Appearance.spacing.space100
                        text: delegateRoot.modelData.title
                        color: Appearance.colors.colOnLayer1
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    ColumnLayout {
        visible: !WallpaperEngine.loading && root.filteredProjects.length === 0
        anchors.centerIn: parent
        spacing: Appearance.spacing.space100
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "wallpaper"
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: WallpaperEngine.error || Translation.tr("No Wallpaper Engine projects found")
            color: Appearance.colors.colSubtext
        }
    }

    StyledIndeterminateProgressBar {
        visible: WallpaperEngine.loading
        anchors.centerIn: parent
        width: parent.width / 3
    }
}
