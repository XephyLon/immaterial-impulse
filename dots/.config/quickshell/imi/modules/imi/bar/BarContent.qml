import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets
import qs.modules.common.functions
import "bar_widget_source.js" as BarWidgetSource

Item {
    id: root
    implicitHeight: Appearance.sizes.barHeight
    width: parent.width
    readonly property real barPadding: 0
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3
    // Float Islands: M3's three sections, each drawn as Float's plate - the
    // window rounding, the layer border, a gap off the edge and the windows -
    // with the groups inside them exactly as Float draws them. The full-width
    // plate goes transparent and three islands take its place.
    readonly property bool isFloatIslands: Config.options.bar.cornerStyle === 4
    readonly property bool floatPlate: Config.options.bar.cornerStyle === 1 || root.isFloatIslands
    readonly property real centerPillX: centerPill.x
    readonly property real centerPillWidth: centerPill.width
    property bool suppressDockerForMemoryTest: false

    readonly property bool trayHasItems: SystemTray.items.values.length > 0

    // The painted body shapes, exposed so the hosting window can scope its
    // compositor blur region to them (see WindowBlurRegion in Bar.qml). The
    // "painted" flags mirror each shape's own color/visible condition: a blur
    // region is a plain rect, so covering an unpainted (transparent) shape
    // would frost the bare wallpaper behind it.
    readonly property Item backgroundItem: barBackground
    readonly property bool backgroundPainted: !centerOnly && Config.options.bar.showBackground
        && Config.options.bar.cornerStyle !== 2 && !root.isMaterial && !root.isFloatIslands
    readonly property Item centerPillItem: centerPill
    readonly property bool centerPillPainted: centerPill.visible

    // M3 paints no full-width strip - it draws three rounded wrappers instead,
    // and those are the only painted shapes on the bar. They were never handed
    // to the blur region, so an M3 bar declared an empty region and the
    // compositor frosted nothing at all, pills included. Exposed here so the
    // region can cover exactly them and leave the gaps between them clear.
    readonly property Item leftMaterialPillItem: leftMaterialPill
    readonly property Item centerMaterialPillItem: centerMaterialPill
    readonly property Item rightMaterialPillItem: rightMaterialPill
    readonly property bool materialPillsPainted: root.isMaterial
    // Float Islands' plates, handed to the blur region the same way.
    readonly property Item leftIslandItem: leftIsland
    readonly property Item centerIslandItem: centerIsland
    readonly property Item rightIslandItem: rightIsland
    readonly property bool leftIslandPainted: leftIsland.visible
    readonly property bool centerIslandPainted: centerIsland.visible
    readonly property bool rightIslandPainted: rightIsland.visible

    function filterLayout(layout) {
        return layout.filter(name => {
            if (name === "sysTray" && !trayHasItems) return false;
            if (root.suppressDockerForMemoryTest
                    && (name === "dockerPlugin" || name === "plugin:docker_plugin")) return false;
            if (BarWidgetSource.isDisabledPlugin(name, Config.options.plugins.enabled)) return false;
            return true;
        });
    }

    readonly property var effectiveLeftLayout:   filterLayout(Config.options.bar.layouts.leftLayout)
    readonly property var effectiveMiddleLayout: filterLayout(Config.options.bar.layouts.middleLayout)
    readonly property var effectiveRightLayout:  filterLayout(Config.options.bar.layouts.rightLayout)

    // Edit Mode's per-entry read of the same rule filterLayout applies - THE
    // same rule by construction, not a copy: the reorder maps its visible
    // indices back to stored ones with these answers, and a predicate that
    // drifted from the filter would shift a drag by one hidden entry.
    function widgetVisible(name) {
        return root.filterLayout([name]).length > 0;
    }

    // The drawn slot items per bucket, for the edit controller: whichever
    // style is on screen owns the geometry, so the pick follows isMaterial.
    function editSlotItems(bucket) {
        const repeaters = root.isMaterial
            ? { left: leftMaterialRepeater, middle: centerMaterialRepeater, right: rightMaterialRepeater }
            : { left: leftRepeater, middle: middleRepeater, right: rightRepeater };
        const repeater = repeaters[bucket];
        const items = [];
        for (let i = 0; i < repeater.count; i++) items.push(repeater.itemAt(i));
        return items;
    }

    function getWidgetUrl(name) {
        const fileName = BarWidgetSource.fileNameFor(name);
        return fileName ? Qt.resolvedUrl("./" + fileName) : "";
    }

    function getMirroredForIndex(layout, idx) {
        const prevCount = layout.slice(0, idx).filter(w => w === "visualizer").length
        return prevCount % 2 === 1
    }

    function shouldPaintMaterialPill(name) {
        if (Config.options.bar.cornerStyle !== 3) return false;
        const blacklist = ["workspaces", "divisor", "powerButton", "docktoPanel", "leftSidebarButton", "activeWindow", "timerPill", "privacyIndicator", "submapIndicator"];
        if (blacklist.includes(name)) {
            return false;
        }
        return true;
    }

    function getMaterialPillColor(name) {
        if (Config.options.bar.cornerStyle !== 3) return Appearance.colors.colPrimaryContainer;
        switch(name) {
            case "media":
            case "sysTray":
                return Appearance.colors.colSecondaryContainer;
            case "resources":
                return Appearance.colors.colTertiaryContainer;
            case "systemIcons":
                return Appearance.colors.colPrimary; 
            default:
                return Appearance.colors.colPrimaryContainer;
        }
    }

    property var screen: root.QsWindow.window?.screen
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0


    // Optional soft drop shadow under the bar background (Config.options.bar.shadow).
    // Only rendered when the background itself is painted (mirrors barBackground's color condition).
    Loader {
        active: Config.options.bar.shadow && !centerOnly && Config.options.bar.showBackground
            && Config.options.bar.cornerStyle !== 2 && !root.isMaterial && !root.isFloatIslands
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    Rectangle {
        id: barBackground
        anchors.fill: parent
        anchors.margins: root.floatPlate ? Appearance.sizes.hyprlandGapsOut : 0
        color: (!centerOnly && Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2 && !root.isMaterial && !root.isFloatIslands)
            ? Appearance.colors.colBarBackground : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: (!centerOnly && Config.options.bar.cornerStyle === 1) ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    // center-only
    readonly property bool centerOnly: !root.isMaterial
        && root.effectiveLeftLayout.length === 0
        && root.effectiveRightLayout.length === 0

    // Shadow for the center-only pill (same option, mirrors centerPill's visible condition)
    Loader {
        active: Config.options.bar.shadow && centerPill.visible
        anchors.fill: centerPill
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: centerPill
        }
    }
    Rectangle {
        id: centerPill
        visible: centerOnly && Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: middleRow.implicitWidth + 10
        height: parent.height - (root.floatPlate ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
        color: Appearance.colors.colBarBackground
        radius: root.floatPlate ? Appearance.rounding.windowRounding : 0
        border.width: root.floatPlate ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        bottomLeftRadius:  Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        bottomRightRadius: Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        topLeftRadius:     Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
        topRightRadius:    Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
    }

    Item {
        id: contentContainer
        anchors.fill: barBackground
        anchors.margins: root.barPadding

        // Float Islands: one plate behind each populated section, declared
        // before the sections so they paint under them. A section's inset
        // from the container is the plate's own padding, so the plate reaches
        // the container's edge (hyprlandGapsOut off the screen) exactly as
        // Float's whole plate does.
        readonly property real islandPad: Appearance.spacing.space125
        component Island: Rectangle {
            required property bool populated
            visible: root.isFloatIslands && Config.options.bar.showBackground && !root.centerOnly && populated
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: Appearance.colors.colBarBackground
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
        component IslandShadow: Loader {
            required property Item island
            active: Config.options.bar.shadow && island.visible
            anchors.fill: island
            sourceComponent: StyledRectangularShadow {
                anchors.fill: undefined
                target: island
            }
        }
        IslandShadow { island: leftIsland }
        IslandShadow { island: centerIsland }
        IslandShadow { island: rightIsland }
        Island {
            id: leftIsland
            populated: root.effectiveLeftLayout.length > 0
            anchors.left: leftSection.left
            anchors.right: leftSection.right
            anchors.leftMargin: -contentContainer.islandPad
            anchors.rightMargin: -contentContainer.islandPad
        }
        Island {
            id: centerIsland
            populated: root.effectiveMiddleLayout.length > 0
            anchors.left: absoluteCenter.left
            anchors.right: absoluteCenter.right
            anchors.leftMargin: -contentContainer.islandPad
            anchors.rightMargin: -contentContainer.islandPad
        }
        Island {
            id: rightIsland
            populated: root.effectiveRightLayout.length > 0
            anchors.left: rightSection.left
            anchors.right: rightSection.right
            anchors.leftMargin: -contentContainer.islandPad
            anchors.rightMargin: -contentContainer.islandPad
        }

        // Left
        Item {
            id: leftSection
            anchors.left: parent.left
            anchors.leftMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (Config.options.bar.cornerStyle === 1 ? Appearance.spacing.space50 : Appearance.spacing.space125)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.isMaterial ? leftMaterialPill.implicitWidth : leftRow.implicitWidth

            BarBucketBoundary {
                id: leftBoundary
                z: 50
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height - Appearance.spacing.space50
                width: Math.max(parent.width, minRun)
            }

            // Material pill wrapper
            Rectangle {
                id: leftMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: leftMaterialRow.implicitWidth + 10
                implicitHeight: leftMaterialRow.implicitHeight
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarBackground

                RowLayout {
                    id: leftMaterialRow
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    Repeater {
                        id: leftMaterialRepeater
                        model: root.effectiveLeftLayout
                        delegate: leftMaterialGroupDelegate
                    }

                    Component {
                        id: leftMaterialGroupDelegate
                        BarGroup {
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: root.effectiveLeftLayout.length
                            editController: barEditController
                            editBucket: "left"
                            widgetId: modelData
                            flipRegistry: barFlipRegistry
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillHeight: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                                    if (item && modelData === "visualizer")
                                        item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            // Non-material layout
            RowLayout {
                id: leftRow
                visible: !root.isMaterial
                anchors.fill: parent
                spacing: Config.options.bar.borderless === "transparent" ? -Appearance.spacing.space100 : Appearance.spacing.space25

                Repeater {
                    id: leftRepeater
                    model: root.effectiveLeftLayout
                    delegate: leftBarGroupDelegate
                }

                Component {
                    id: leftBarGroupDelegate
                    BarGroup {
                        Layout.fillHeight: true
                        currentIndex: index
                        totalCount: root.effectiveLeftLayout.length
                        editController: barEditController
                        editBucket: "left"
                        widgetId: modelData
                        flipRegistry: barFlipRegistry
                        Loader {
                            Layout.fillHeight: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                                if (item && modelData === "visualizer")
                                    item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                            }
                        }
                    }
                }

                Component {
                    id: leftNoGroupDelegate
                    Loader {
                        Layout.fillHeight: false
                        Layout.topMargin: Config.options.bar.bottom ? -Appearance.spacing.space50 : Appearance.spacing.space50
                        Layout.alignment: Qt.AlignVCenter
                        source: root.getWidgetUrl(modelData)
                        onLoaded: {
                            if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                            if (item && modelData === "visualizer")
                                item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                        }
                    }
                }
            }
        }

        // Center
        Item {
            id: absoluteCenter
            anchors.centerIn: parent
            width: root.isMaterial ? centerMaterialPill.implicitWidth : middleRow.implicitWidth
            height: parent.height

            BarBucketBoundary {
                id: middleBoundary
                z: 50
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height - Appearance.spacing.space50
                width: Math.max(parent.width, minRun)
            }

            // Material pill wrapper
            Rectangle {
                id: centerMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: centerMaterialRow.implicitWidth + 10
                implicitHeight: centerMaterialRow.implicitHeight 
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarBackground

                RowLayout {
                    id: centerMaterialRow
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    Repeater {
                        id: centerMaterialRepeater
                        model: root.effectiveMiddleLayout
                        delegate: middleMaterialGroupDelegate
                    }

                    Component {
                        id: middleMaterialGroupDelegate
                        BarGroup {
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: root.effectiveMiddleLayout.length
                            editController: barEditController
                            editBucket: "middle"
                            widgetId: modelData
                            flipRegistry: barFlipRegistry
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillHeight: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                                    if (item && modelData === "visualizer")
                                        item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            // Non-material layout
            RowLayout {
                id: middleRow
                visible: !root.isMaterial
                anchors.fill: parent
                spacing: Config.options.bar.borderless === "transparent" ? -Appearance.spacing.space100 : Appearance.spacing.space25

                Repeater {
                    id: middleRepeater
                    model: root.effectiveMiddleLayout
                    delegate: middleBarGroupDelegate
                }

                Component {
                    id: middleBarGroupDelegate
                    BarGroup {
                        Layout.fillHeight: true
                        currentIndex: index
                        totalCount: root.effectiveMiddleLayout.length
                        editController: barEditController
                        editBucket: "middle"
                        widgetId: modelData
                        flipRegistry: barFlipRegistry
                        Loader {
                            Layout.fillHeight: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                                if (item && modelData === "visualizer")
                                    item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                            }
                        }
                    }
                }

                Component {
                    id: middleNoGroupDelegate
                    Loader {
                        Layout.fillHeight: false
                        Layout.topMargin: Config.options.bar.bottom ? -Appearance.spacing.space50 : Appearance.spacing.space50
                        source: root.getWidgetUrl(modelData)
                        onLoaded: {
                            if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                            if (item && modelData === "visualizer")
                                item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                        }
                    }
                }
            }
        }

        // Right
        Item {
            id: rightSection
            anchors.right: parent.right
            anchors.rightMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (Config.options.bar.cornerStyle === 1 ? Appearance.spacing.space50 : Appearance.spacing.space125)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.isMaterial ? rightMaterialPill.implicitWidth : rightRow.implicitWidth

            BarBucketBoundary {
                id: rightBoundary
                z: 50
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height - Appearance.spacing.space50
                width: Math.max(parent.width, minRun)
            }

            // Material pill wrapper
            Rectangle {
                id: rightMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: rightMaterialRow.implicitWidth + 10
                implicitHeight: rightMaterialRow.implicitHeight 
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarBackground

                RowLayout {
                    id: rightMaterialRow
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    Repeater {
                        id: rightMaterialRepeater
                        model: root.effectiveRightLayout
                        delegate: rightMaterialGroupDelegate
                    }

                    Component {
                        id: rightMaterialGroupDelegate
                        BarGroup {
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: root.effectiveRightLayout.length
                            editController: barEditController
                            editBucket: "right"
                            widgetId: modelData
                            flipRegistry: barFlipRegistry
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillHeight: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                                    if (item && modelData === "visualizer")
                                        item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            // Non-material layout
            RowLayout {
                id: rightRow
                visible: !root.isMaterial
                anchors.fill: parent
                spacing: Config.options.bar.borderless === "transparent" ? -Appearance.spacing.space100 : Appearance.spacing.space25

                Repeater {
                    id: rightRepeater
                    model: root.effectiveRightLayout
                    delegate: rightBarGroupDelegate
                }

                Component {
                    id: rightBarGroupDelegate
                    BarGroup {
                        Layout.fillHeight: true
                        currentIndex: index
                        totalCount: root.effectiveRightLayout.length
                        editController: barEditController
                        editBucket: "right"
                        widgetId: modelData
                        flipRegistry: barFlipRegistry
                        Loader {
                            Layout.fillHeight: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                                if (item && modelData === "visualizer")
                                    item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                            }
                        }
                    }
                }

                Component {
                    id: rightNoGroupDelegate
                    Loader {
                        Layout.fillHeight: false
                        Layout.topMargin: Config.options.bar.bottom ? -Appearance.spacing.space50 : Appearance.spacing.space50
                        source: root.getWidgetUrl(modelData)
                        onLoaded: {
                            if (item && modelData.startsWith("plugin:") && item.hasOwnProperty("pluginId")) item.pluginId = modelData.substring(7)
                            if (item && modelData === "visualizer")
                                item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                        }
                    }
                }
            }
        }
    }

    // Edit Mode's reorder coordinator: the indicator, the ghost and every
    // layout commit. One shared component, so the vertical bar runs the same
    // logic off the same file rather than a copy that can drift.
    BarEditController {
        id: barEditController
        anchors.fill: parent
        z: 200
        vertical: false
        widgetVisible: name => root.widgetVisible(name)
        slotItemsFor: bucket => root.editSlotItems(bucket)
        leftZone: leftBoundary
        middleZone: middleBoundary
        rightZone: rightBoundary
    }

    // Where each widget was drawn, so the slot that replaces it after a reflow
    // has a First to invert from. Declared as a child of this root because
    // that is the frame every position is measured in - see BarFlipRegistry.
    BarFlipRegistry {
        id: barFlipRegistry
    }
}
