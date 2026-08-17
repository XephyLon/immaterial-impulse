import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins

/**
 * Edit Mode's drawer: the catalogue of desktop widgets, fed by
 * `PluginManager.availablePlugins` - the same list Settings > Widgets reads,
 * because a second catalogue is a second list to go stale (spec §4.1's table:
 * "adding a widget means opening Settings › Widgets" becomes this panel).
 *
 * ---- how it reveals -------------------------------------------------------
 *
 * The item this file declares IS the reveal: the surface sizes it to
 * `edit_mode.js`'s `drawerRect`, whose right edge is pinned and whose WIDTH is
 * what animates. The panel inside is the drawer's full width anchored to the
 * LEFT edge, so the leading edge appears first and the panel slides in from
 * the screen's edge - and `clip: true` is what makes a closed drawer paint
 * nothing at all, which the pixel test's before/after comparison depends on.
 * The clip is also why the panel's shadow is not drawn here: it falls entirely
 * outside the reveal and the chrome content draws it around this item instead.
 *
 * ---- the two gestures -----------------------------------------------------
 *
 * A CLICK toggles the widget's presence on the desktop - the same
 * `plugins.enabled` write the Settings page makes, one writer with two call
 * sites rather than two meanings. A DRAG carries the widget out: past the
 * threshold a ghost chip follows the pointer, and the release hands the drop
 * point up as a request. Both are requests rather than writes, so every store
 * this mode touches is written on the surface that owns the geometry - which
 * is also what keeps `lint_edit_mode_scope.py`'s question answerable in one
 * file.
 *
 * The pointer areas in this file are the reason the drawer is IN the surface's
 * input mask: unlike the toolbar's buttons they must keep receiving events
 * after the pointer leaves the panel, which the implicit grab of the press
 * provides - a Wayland pointer grab follows the surface that took the press,
 * not the input region it took it in.
 */
Item {
    id: root
    clip: true

    // The drawer's full width - what the reveal grows toward, and the one
    // declared number the viewport's inset and this panel both read.
    property real panelWidth: Appearance.sizes.editModeDrawerWidth

    // Where the ghost chip is parented while a drag is out: the chrome
    // content's root, which fills the surface - the ghost has to survive the
    // pointer leaving this clipped item.
    property Item ghostParent: null

    // The drop, in the ghost parent's (= the surface's = the screen's)
    // coordinates. The surface maps it into the canvas and writes the store.
    signal addRequested(var manifest, real dropX, real dropY)
    signal toggleRequested(var manifest)

    // Everything that can live on the desktop and can come up now. The
    // `startupSafe` term is the same one Background.qml's Repeater applies: a
    // manifest that declares itself unsafe to autoload is not offered a
    // gesture that would autoload it.
    readonly property var desktopManifests: PluginManager.availablePlugins.filter(manifest =>
        PluginManager.pluginSurfaces(manifest).includes("desktop-widget")
        && manifest.startupSafe !== false)

    readonly property var enabledIds: Config.options.plugins.enabled

    // The drag that is currently out, or null. One ghost for the whole drawer
    // rather than one per row - only one pointer exists.
    property var dragManifest: null

    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.panelWidth
        // The toolbar bodies' own opaque surface: this namespace carries
        // `ignore_alpha = 1`, so an opaque body is the thing that stays
        // blurred and a translucent one is the thing that goes flat.
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.verylarge

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Appearance.spacing.space150
            spacing: Appearance.spacing.space100

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space75
                Layout.rightMargin: Appearance.spacing.space75
                spacing: Appearance.spacing.space100

                MaterialSymbol {
                    text: "widgets"
                    iconSize: 22
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Widgets")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurface
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space75
                Layout.rightMargin: Appearance.spacing.space75
                text: Translation.tr("Drag a widget onto the desktop to place it, or click to add or remove it.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.spacing.space25
                model: root.desktopManifests

                delegate: MouseArea {
                    id: entry
                    required property var modelData
                    readonly property bool widgetEnabled: root.enabledIds.includes(entry.modelData.id)

                    width: list.width
                    height: 60
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton

                    // The same by-hand drag as AbstractWidget's, for the same
                    // reason at a smaller scale: the row does not move, so all
                    // this needs is the press point and a threshold.
                    property real pressX: 0
                    property real pressY: 0
                    property bool dragActive: false

                    onPressed: (mouse) => {
                        entry.pressX = mouse.x;
                        entry.pressY = mouse.y;
                        entry.dragActive = false;
                    }
                    onPositionChanged: (mouse) => {
                        if (!entry.pressed) return;
                        if (!entry.dragActive
                                && Math.abs(mouse.x - entry.pressX) < drag.threshold
                                && Math.abs(mouse.y - entry.pressY) < drag.threshold)
                            return;
                        entry.dragActive = true;
                        root.dragManifest = entry.modelData;
                        const point = entry.mapToItem(root.ghostParent ?? root, mouse.x, mouse.y);
                        ghost.x = point.x - ghost.width / 2;
                        ghost.y = point.y - ghost.height / 2;
                    }
                    onReleased: (mouse) => {
                        const wasDrag = entry.dragActive;
                        entry.dragActive = false;
                        root.dragManifest = null;
                        if (wasDrag) {
                            const point = entry.mapToItem(root.ghostParent ?? root, mouse.x, mouse.y);
                            root.addRequested(entry.modelData, point.x, point.y);
                        } else {
                            root.toggleRequested(entry.modelData);
                        }
                    }
                    onCanceled: {
                        entry.dragActive = false;
                        root.dragManifest = null;
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.large
                        color: entry.pressed ? Appearance.colors.colLayer2Active
                            : entry.containsMouse ? Appearance.colors.colLayer2Hover
                            : "transparent"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.spacing.space100
                        anchors.rightMargin: Appearance.spacing.space100
                        spacing: Appearance.spacing.space100

                        MaterialSymbol {
                            text: "widgets"
                            iconSize: 22
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: (entry.modelData.description ?? "").length > 0
                                text: entry.modelData.description ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                        MaterialSymbol {
                            text: entry.widgetEnabled ? "check_circle" : "add"
                            iconSize: 20
                            color: entry.widgetEnabled
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    // The chip that rides the pointer while a widget is being carried out.
    // Parented to the surface-filling chrome root, because this item clips to
    // the reveal and the whole point of the gesture is leaving it.
    Rectangle {
        id: ghost
        parent: root.ghostParent ?? root
        visible: root.dragManifest !== null
        width: ghostRow.implicitWidth + Appearance.spacing.space200
        height: 40
        radius: height / 2
        color: Appearance.colors.colSecondaryContainer

        RowLayout {
            id: ghostRow
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50

            MaterialSymbol {
                text: "widgets"
                iconSize: 20
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: root.dragManifest?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }
}
