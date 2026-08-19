import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.bar as Bar
import "../bar/bar_widget_source.js" as BarWidgetSource

Item {
    id: root
    implicitWidth: Appearance.sizes.verticalBarWidth
    height: parent.height

    readonly property real barPadding: 0
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property bool trayHasItems: SystemTray.items.values.length > 0

    function filterLayout(layout) {
        return layout.filter(name => {
            if (name === "sysTray" && !trayHasItems) return false
            if (BarWidgetSource.isDisabledPlugin(name, Config.options.plugins.enabled)) return false
            return true
        })
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

    readonly property bool centerOnly: !root.isMaterial
        && root.effectiveLeftLayout.length === 0
        && root.effectiveRightLayout.length === 0
    readonly property real centerPillY: centerPill.y
    readonly property real centerPillHeight: centerPill.height

    function shouldPaintMaterialPill(name) {
        if (Config.options.bar.cornerStyle !== 3) return false;
        const blacklist = ["workspaces", "divisor", "powerButton", "media", "docktoPanel", "leftSidebarButton"];
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

    function getWidgetUrl(name) {
        const fileName = BarWidgetSource.fileNameFor(name);
        return fileName ? Qt.resolvedUrl("../bar/" + fileName) : "";
    }

    function getMirroredForIndex(layout, idx) {
        const prevCount = layout.slice(0, idx).filter(w => w === "visualizer").length
        return prevCount % 2 === 1
    }

    property var screen: root.QsWindow.window?.screen

    // The painted body shapes, exposed so the hosting window can scope its
    // compositor blur region to them (see WindowBlurRegion in VerticalBar.qml).
    // The "painted" flags mirror each shape's own color/visible condition: a
    // blur region is a plain rect, so covering an unpainted (transparent)
    // shape would frost the bare wallpaper behind it.
    readonly property Item backgroundItem: barBackground
    readonly property bool backgroundPainted: Config.options.bar.showBackground
        && Config.options.bar.cornerStyle !== 2 && !root.isMaterial && !root.centerOnly
    readonly property Item centerPillItem: centerPill
    readonly property bool centerPillPainted: centerPill.visible

    // Under cornerStyle 3 (M3) both of the above resolve to null - backgroundPainted
    // requires !isMaterial, and centerPill.visible requires centerOnly, which is
    // itself !isMaterial - so the window declared an EMPTY blur region against a
    // surface whose whole-surface layerrule blur is off (rules.lua). Nothing on an
    // M3 vertical bar was frosted, pills included. Same defect dc4e0662c fixed for
    // the horizontal bar; expose the three painted wrappers so the region can cover
    // exactly them and leave the gaps between them clear.
    readonly property Item topMaterialPillItem: topMaterialPill
    readonly property Item centerMaterialPillItem: centerMaterialPill
    readonly property Item bottomMaterialPillItem: bottomMaterialPill
    readonly property bool materialPillsPainted: root.isMaterial

    // Optional soft drop shadow under the bar background (Config.options.bar.shadow).
    // Only rendered when the background itself is painted (mirrors barBackground's color condition).
    Loader {
        active: Config.options.bar.shadow && !root.centerOnly && Config.options.bar.showBackground
            && Config.options.bar.cornerStyle !== 2 && !root.isMaterial
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        }
        color: (Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2 && !root.isMaterial && !root.centerOnly)
            ? Appearance.colors.colBarBackground : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: (!root.centerOnly && Config.options.bar.cornerStyle === 1) ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    // Shadow for the center-only pill (same option, mirrors centerPill's visible condition)
    Loader {
        active: Config.options.bar.shadow && centerPill.visible
        anchors.fill: centerPill
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: centerPill
        }
    }
    // centerOnly
    Rectangle {
        id: centerPill
        visible: root.centerOnly && Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: middleCol.implicitHeight + 7
        width: parent.width - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
        color: Appearance.colors.colBarBackground
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        bottomRightRadius: Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        topRightRadius:    Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        bottomLeftRadius:  Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
        topLeftRadius:     Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
    }

    Item {
        id: contentContainer
        anchors.fill: barBackground
        anchors.margins: root.barPadding

        // Top
        Item {
            id: topSection
            anchors.top: parent.top
            anchors.topMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (Config.options.bar.cornerStyle === 1 ? Appearance.spacing.space50 : Appearance.spacing.space125)
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial ? topMaterialPill.implicitHeight : topCol.implicitHeight

            Bar.BarBucketBoundary {
                id: leftBoundary
                z: 50
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Appearance.spacing.space50
                height: Math.max(parent.height, minRun)
            }

            Rectangle {
                id: topMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: topMaterialCol.implicitWidth
                implicitHeight: topMaterialCol.implicitHeight + 10
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarBackground

                ColumnLayout {
                    id: topMaterialCol
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    Repeater {
                        id: leftMaterialRepeater
                        model: root.effectiveLeftLayout
                        delegate: topMaterialGroupDelegate
                    }

                    Component {
                        id: topMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveLeftLayout.length
                            editController: barEditController
                            editBucket: "left"
                            widgetId: modelData
                            flipRegistry: flipRegistry
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && item.hasOwnProperty("pluginId")) item.pluginId = BarWidgetSource.pluginIdOf(modelData)
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: topCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: Config.options.bar.borderless === "transparent" ? -Appearance.spacing.space50 : Appearance.spacing.space25

                Repeater {
                    id: leftRepeater
                    model: root.effectiveLeftLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveLeftLayout.length
                        editController: barEditController
                        editBucket: "left"
                        widgetId: modelData
                        flipRegistry: flipRegistry
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && item.hasOwnProperty("pluginId")) item.pluginId = BarWidgetSource.pluginIdOf(modelData)
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                            }
                        }
                    }
                }
            }
        }

        // Center
        Item {
            id: absoluteCenter
            anchors.centerIn: parent
            width: parent.width
            height: root.isMaterial ? centerMaterialPill.implicitHeight : middleCol.implicitHeight

            Bar.BarBucketBoundary {
                id: middleBoundary
                z: 50
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Appearance.spacing.space50
                height: Math.max(parent.height, minRun)
            }

            Rectangle {
                id: centerMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: centerMaterialCol.implicitWidth 
                implicitHeight: centerMaterialCol.implicitHeight + 10
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarBackground

                ColumnLayout {
                    id: centerMaterialCol
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    Repeater {
                        id: centerMaterialRepeater
                        model: root.effectiveMiddleLayout
                        delegate: centerMaterialGroupDelegate
                    }

                    Component {
                        id: centerMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveMiddleLayout.length
                            editController: barEditController
                            editBucket: "middle"
                            widgetId: modelData
                            flipRegistry: flipRegistry
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && item.hasOwnProperty("pluginId")) item.pluginId = BarWidgetSource.pluginIdOf(modelData)
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: middleCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: Config.options.bar.borderless === "transparent" ? -Appearance.spacing.space50 : Appearance.spacing.space25

                Repeater {
                    id: middleRepeater
                    model: root.effectiveMiddleLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveMiddleLayout.length
                        editController: barEditController
                        editBucket: "middle"
                        widgetId: modelData
                        flipRegistry: flipRegistry
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && item.hasOwnProperty("pluginId")) item.pluginId = BarWidgetSource.pluginIdOf(modelData)
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                            }
                        }
                    }
                }
            }
        }

        // Bottom
        Item {
            id: bottomSection
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (Config.options.bar.cornerStyle === 1 ? Appearance.spacing.space50 : Appearance.spacing.space125)
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial ? bottomMaterialPill.implicitHeight : bottomCol.implicitHeight

            Bar.BarBucketBoundary {
                id: rightBoundary
                z: 50
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Appearance.spacing.space50
                height: Math.max(parent.height, minRun)
            }

            Rectangle {
                id: bottomMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: bottomMaterialCol.implicitWidth
                implicitHeight: bottomMaterialCol.implicitHeight + 10 
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarBackground

                ColumnLayout {
                    id: bottomMaterialCol
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    Repeater {
                        id: rightMaterialRepeater
                        model: root.effectiveRightLayout
                        delegate: bottomMaterialGroupDelegate
                    }

                    Component {
                        id: bottomMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveRightLayout.length
                            editController: barEditController
                            editBucket: "right"
                            widgetId: modelData
                            flipRegistry: flipRegistry
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && item.hasOwnProperty("pluginId")) item.pluginId = BarWidgetSource.pluginIdOf(modelData)
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: bottomCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: Config.options.bar.borderless === "transparent" ? -Appearance.spacing.space50 : Appearance.spacing.space25

                Repeater {
                    id: rightRepeater
                    model: root.effectiveRightLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveRightLayout.length
                        editController: barEditController
                        editBucket: "right"
                        widgetId: modelData
                        flipRegistry: flipRegistry
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && item.hasOwnProperty("pluginId")) item.pluginId = BarWidgetSource.pluginIdOf(modelData)
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                            }
                        }
                    }
                }
            }
        }
    }

    // Edit Mode's reorder coordinator - the same shared component the
    // horizontal bar instantiates, turned by one flag, so the two orientations
    // cannot run different edit logic.
    Bar.BarEditController {
        id: barEditController
        anchors.fill: parent
        z: 200
        vertical: true
        widgetVisible: name => root.widgetVisible(name)
        slotItemsFor: bucket => root.editSlotItems(bucket)
        leftZone: leftBoundary
        middleZone: middleBoundary
        rightZone: rightBoundary
    }

    // The same registry, in the vertical bar's own frame: the ids are shared
    // between the two bars and between screens, and the positions are not.
    Bar.BarFlipRegistry {
        id: flipRegistry
    }
}
