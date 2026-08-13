import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: rootNode
    property var manifestNode
    property string pluginId: ""
    property var optionDefinitions: []
    property string basePath: ""
    // Name of the monitor the host widget lives on. Forwarded to a
    // component-backed Widget.qml that declares a `screenName` property, so a
    // widget can size or place itself against its own real screen (the
    // visualiser is full-bleed). Declarative nodes never need it.
    property string screenName: ""

    // Host context handed down to a component-backed Widget.qml, and the
    // opt-ins it can hand back. Both directions are optional and named on the
    // loaded item, exactly like blurRegions/managesBlurTint: a widget that
    // declares none of these properties is completely unaffected.
    //
    // These exist because the ported built-ins were direct AbstractBackground-
    // Widget subclasses and could set these themselves. A plugin widget is a
    // grandchild of one instead, so anything that has to influence the host's
    // own geometry, visibility or wallpaper sampling has to travel through
    // here. See docs/PLUGINS.md.
    property real hostX: 0
    property real hostY: 0
    property color hostColText: Appearance.colors.colOnLayer0
    property bool hostWallpaperSafetyTriggered: false
    // The host's *resolved* lock: AbstractBackgroundWidget.interactionLocked,
    // i.e. per-widget lock OR click-through OR the global switch. Widgets that
    // draw their own resize/toggle grips gate them on this, so a grip is dead
    // for exactly the reasons dragging is. Deliberately the resolved value
    // rather than the three terms - a grip has no business caring which of them
    // is holding it.
    property bool hostInteractionLocked: false

    readonly property bool wantsVisibleWhenLocked: componentLoader.item
        ? componentLoader.item.visibleWhenLocked === true : false
    readonly property bool wantsForceCenter: componentLoader.item
        ? componentLoader.item.forceCenter === true : false
    // A one-tree widget repositions its own elements through a span change,
    // so the host's midpoint cross-fade would put a dissolve over elements
    // that deliberately never disappear.
    readonly property bool wantsOwnSpanTransition: componentLoader.item
        ? componentLoader.item.handlesSpanTransition === true : false
    readonly property bool wantsAdaptiveTextColor: componentLoader.item
        ? componentLoader.item.needsColText === true : false

    // When the host declares a component-grid span (docs/widget-grid.md), it sets
    // these to the span size in px. The node then takes that size instead of the
    // loaded item's implicit size, and the item is stretched to fill so Widget.qml
    // can anchor.fill its host. Zero means "no grid" - fall back to content sizing.
    property real gridWidth: 0
    property real gridHeight: 0
    readonly property bool hasGrid: gridWidth > 0 && gridHeight > 0
    // The same span as a "<cols>x<rows>" string, for a widget that has a
    // different LAYOUT per size rather than one layout that stretches. The host
    // owns which size; the widget owns what that size looks like. Empty when the
    // manifest declares no grid. It tracks the resize grip's live preview, so a
    // drag reshapes the content as it goes instead of on release.
    property string gridSize: ""
    // The resize grip's live edge distortion, forwarded to widgets whose cards
    // bow under tension. A point of pixels; (0,0) at rest.
    property point resizeBow: Qt.point(0, 0)
    // Whether the host is currently being dragged, for a widget that lifts
    // its cards while handled.
    property bool hostDragging: false
    // Whether the host's own box is animating. A widget uses it to stop
    // re-rendering effects that cost a frame each while it moves.
    property bool hostBoxInMotion: false

    readonly property string effectiveBasePath: manifestNode?._basePath || basePath
    readonly property string componentPath: manifestNode?.component && effectiveBasePath
        ? (String(manifestNode.component).startsWith("/")
            ? String(manifestNode.component)
            : effectiveBasePath + "/" + String(manifestNode.component).replace(/^\.\//, ""))
        : ""

    implicitWidth: hasGrid ? gridWidth
        : (componentLoader.item ? (componentLoader.item.implicitWidth || componentLoader.item.width) : 0)
    implicitHeight: hasGrid ? gridHeight
        : (componentLoader.item ? (componentLoader.item.implicitHeight || componentLoader.item.height) : 0)
    // Component plugins may expose several local blur surfaces. Coordinates are
    // relative to this node. An empty list means "blur the complete widget".
    readonly property bool hasCustomBlurRegions: componentLoader.item
        ? componentLoader.item.blurRegions !== undefined : false
    readonly property var blurRegions: hasCustomBlurRegions ? componentLoader.item.blurRegions : []
    readonly property bool managesBlurTint: componentLoader.item
        ? componentLoader.item.managesBlurTint === true : false
    width: implicitWidth
    height: implicitHeight

    function resolveBinding(bindingString) {
        switch (bindingString) {
            case "DateTime.time": return DateTime.time;
            case "DateTime.date": return DateTime.date;
            case "DateTime.shortDate": return DateTime.shortDate;
            case "Battery.percentage": return Battery.percentage;
            case "Battery.charging": return Battery.charging;
            case "Battery.pluggedIn": return Battery.pluggedIn;
            case "Network.networkName": return Network.networkName;
            case "Network.primaryIp": return Network.primaryIp;
            case "SystemInfo.cpuUsage": return SystemInfo.cpuUsage;
            case "SystemInfo.ramUsage": return SystemInfo.ramUsage;
            case "Audio.volume": return Audio.volume;
            case "Audio.muted": return Audio.muted;
            default: return undefined;
        }
    }

    function optionDefinition(propertyName) {
        for (const definition of rootNode.optionDefinitions) {
            if (definition.key === propertyName) return definition;
        }
        return null;
    }

    function declarativeComponent() {
        if (!manifestNode) return null;
        switch (manifestNode.type) {
        case "StyledText": return styledTextComponent;
        case "MaterialSymbol": return materialSymbolComponent;
        case "ResourceCard": return resourceCardComponent;
        case "StyledImage": return styledImageComponent;
        case "MaterialShape": return materialShapeComponent;
        case "Row": return rowComponent;
        case "Column": return columnComponent;
        case "Item": return itemComponent;
        case "Rectangle": return rectangleComponent;
        case "RippleButton": return rippleButtonComponent;
        case "StyledRectangularShadow": return styledRectangularShadowComponent;
        case "GroupedList": return groupedListComponent;
        case "ConfigSwitch": return configSwitchComponent;
        case "NoticeBox": return noticeBoxComponent;
        case "StyledPopup": return styledPopupComponent;
        default: return null;
        }
    }

    Loader {
        id: componentLoader
        // No anchors.fill in the content-sized case: rootNode's own size is
        // *derived from* this loaded item's implicit size (see implicitWidth/
        // implicitHeight above), so forcing the Loader to fill rootNode would
        // force the item to match rootNode's size right back - a circular binding
        // ("binding loop detected for property implicitWidth"). Let the Loader
        // mirror the item's natural size instead; explicit width/height come from
        // the manifest's own props (assigned directly onto the item in onLoaded).
        //
        // With a declared grid span rootNode's size comes from gridWidth/Height
        // (constant, not the item), so there is no loop: fill the node so the
        // Widget.qml root can anchor.fill parent into the full span.
        anchors.fill: rootNode.hasGrid ? rootNode : undefined
        source: rootNode.componentPath
        sourceComponent: rootNode.componentPath ? null : rootNode.declarativeComponent()

        onLoaded: {
            if (!item) return;
            if (rootNode.componentPath) {
                if (item.screenName !== undefined)
                    item.screenName = Qt.binding(() => rootNode.screenName);
                if (item.hostX !== undefined)
                    item.hostX = Qt.binding(() => rootNode.hostX);
                if (item.hostY !== undefined)
                    item.hostY = Qt.binding(() => rootNode.hostY);
                if (item.hostColText !== undefined)
                    item.hostColText = Qt.binding(() => rootNode.hostColText);
                if (item.wallpaperSafetyTriggered !== undefined)
                    item.wallpaperSafetyTriggered = Qt.binding(() => rootNode.hostWallpaperSafetyTriggered);
                if (item.hostInteractionLocked !== undefined)
                    item.hostInteractionLocked = Qt.binding(() => rootNode.hostInteractionLocked);
                if (item.hostGridSize !== undefined)
                    item.hostGridSize = Qt.binding(() => rootNode.gridSize);
                if (item.hostResizeBow !== undefined)
                    item.hostResizeBow = Qt.binding(() => rootNode.resizeBow);
                if (item.hostDragging !== undefined)
                    item.hostDragging = Qt.binding(() => rootNode.hostDragging);
                if (item.hostBoxInMotion !== undefined)
                    item.hostBoxInMotion = Qt.binding(() => rootNode.hostBoxInMotion);
                return;
            }
            if (manifestNode.props) {
                for (let prop in manifestNode.props) {
                    let val = manifestNode.props[prop];
                    let finalVal = val;

                    const option = rootNode.optionDefinition(prop);
                    if (option) {
                        finalVal = Qt.binding(function() {
                            return PluginState.option(rootNode.pluginId, prop, option.default);
                        });
                    } else if (typeof val === "string" && val.startsWith("Appearance.colors.")) {
                        let colorName = val.substring(18);
                        finalVal = Qt.binding(function() { return Appearance.colors[colorName]; });
                    } else if (typeof val === "string" && val.startsWith("Appearance.rounding.")) {
                        let rName = val.substring(20);
                        finalVal = Qt.binding(function() { return Appearance.rounding[rName]; });
                    } else if (typeof val === "string" && val === "parent" && prop.startsWith("anchors")) {
                        finalVal = item.parent;
                    }
                    
                    let parts = prop.split('.');
                    let obj = item;
                    for (let i = 0; i < parts.length - 1; i++) {
                        if (obj[parts[i]] === undefined) break;
                        obj = obj[parts[i]];
                    }
                    obj[parts[parts.length - 1]] = finalVal;
                }
            }
            if (manifestNode.bindings) {
                for (let prop in manifestNode.bindings) {
                    let bindTarget = manifestNode.bindings[prop];
                    let finalVal = Qt.binding(function() {
                        return rootNode.resolveBinding(bindTarget);
                    });
                    
                    let parts = prop.split('.');
                    let obj = item;
                    for (let i = 0; i < parts.length - 1; i++) {
                        if (obj[parts[i]] === undefined) break;
                        obj = obj[parts[i]];
                    }
                    obj[parts[parts.length - 1]] = finalVal;
                }
            }
        }
    }

    Component { id: styledTextComponent; StyledText {} }
    Component { id: materialSymbolComponent; MaterialSymbol {} }
    Component { id: resourceCardComponent; ResourceCard {} }
    Component { id: styledImageComponent; StyledImage {} }

    Component { id: materialShapeComponent; MaterialShape {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}

    Component { id: rowComponent; Row {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}

    Component { id: columnComponent; Column {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}

    Component { id: itemComponent; Item {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}

    Component { id: rectangleComponent; Rectangle {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}
    
    Component { id: rippleButtonComponent; RippleButton {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}

    Component { id: styledRectangularShadowComponent; StyledRectangularShadow {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}

    Component { id: groupedListComponent; GroupedList {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}

    Component { id: configSwitchComponent; ConfigSwitch {} }
    Component { id: noticeBoxComponent; NoticeBox {} }
    Component { id: styledPopupComponent; StyledPopup {
        Repeater {
            model: manifestNode.children || []
            Loader {
                source: "PluginNode.qml"
                onLoaded: { if (item) { item.manifestNode = modelData; item.pluginId = rootNode.pluginId; item.optionDefinitions = rootNode.optionDefinitions; item.basePath = rootNode.basePath } }
            }
        }
    }}
}
