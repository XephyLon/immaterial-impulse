import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins

/**
 * Edit Mode's drawer: the catalogue of everything the mode can add, one
 * section per target surface - desktop widgets (`PluginManager.
 * availablePlugins`), bar widgets (`BarWidgets.offerFor`) and dock apps
 * (`DesktopEntries`, through AppSearch's prepared list). Sections rather
 * than three panels because the drawer's width is the viewport's reserved
 * slot and one reservation cannot be three widths.
 *
 * ---- how each section adds --------------------------------------------------
 *
 * The desktop section keeps stage 5's two gestures: click toggles presence,
 * drag carries the widget out to a drop point - the drop lands on the
 * desktop, which is on the surface this drawer draws over, so the geometry
 * works out on this side of the screen.
 *
 * The bar and dock sections add by CLICK only, deliberately. Their drop
 * targets live on OTHER layer surfaces, in other scene graphs, whose slot
 * geometry this surface cannot map (`mapToItem` does not cross windows) -
 * a drag-out whose landing zone is guessed from configuration would disagree
 * with the boundaries the bar draws, which is worse than no drag. Placement
 * is the in-place reorder those surfaces already carry in the mode: a click
 * appends (the bar section to a picked bucket, the dock to the end of the
 * strip), and the new widget arrives badged and draggable where it will be
 * arranged. The bar section's bucket picker names the buckets the way the
 * current orientation draws them.
 *
 * ---- what this file writes --------------------------------------------------
 *
 * Nothing, same as stage 5: every gesture is a signal, and the chrome surface
 * makes every store write - which is what keeps `lint_edit_mode_scope.py`'s
 * question answerable in one file per store.
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
    // The click-adds: a bar widget into a bucket, a dock app's pin toggled.
    signal barAddRequested(string widgetId, string bucket)
    signal dockToggleRequested(string appId)
    // The lock screen's presence toggles - which of the lock's pieces appear
    // while locked. A signal like everything else here; the surface makes the
    // write at the boolean's own literal path.
    signal lockToggleRequested(string key)

    // Which section is showing, and which bucket a bar-widget click appends
    // to. Session state of the drawer itself; neither survives the mode.
    property string section: "widgets"
    property string barBucket: "right"

    // Everything that can live on the desktop and can come up now. The
    // `startupSafe` term is the same one Background.qml's Repeater applies: a
    // manifest that declares itself unsafe to autoload is not offered a
    // gesture that would autoload it.
    readonly property var desktopManifests: PluginManager.availablePlugins.filter(manifest =>
        PluginManager.pluginSurfaces(manifest).includes("desktop-widget")
        && manifest.startupSafe !== false)

    readonly property var enabledIds: Config.options.plugins.enabled

    // The bar's offer, from the same function the settings dropdown asks -
    // one policy, two call sites, per the offerFor promotion.
    readonly property var barOffer: BarWidgets.offerFor([
        ...Config.options.bar.layouts.leftLayout,
        ...Config.options.bar.layouts.middleLayout,
        ...Config.options.bar.layouts.rightLayout
    ], Config.options.bar.borderless)

    readonly property bool barVertical: Config.options.bar.vertical

    // The drag that is currently out, or null. One ghost for the whole drawer
    // rather than one per row - only one pointer exists.
    property var dragManifest: null

    // The lock screen's three presence toggles (spec §12 stage 9: island
    // VISIBILITY is what the mode edits; where things sit inside an island is
    // its own stage). The keys are the lock.show* booleans LockIdleConfig
    // already offers - presence-on-a-surface, which §9's rule admits and the
    // scope lint's allowlist has carried since it was written. Translation.tr
    // in a binding, so a language change re-evaluates the rows.
    readonly property var lockIslandRows: [
        { key: "showToolbars", name: Translation.tr("Toolbars"),
            icon: "call_to_action",
            description: Translation.tr("The islands beside the password field") },
        { key: "showMedia", name: Translation.tr("Media player"),
            icon: "music_note",
            description: Translation.tr("Playback info while music is playing") },
        { key: "showWidgets", name: Translation.tr("Desktop widgets"),
            icon: "widgets",
            description: Translation.tr("Show every desktop widget while locked") }
    ]

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
                // A Layout nested in a Layout defaults to fillHeight TRUE, and
                // a row of chrome that fills is a row that competes with the
                // list below it for the column's height. Stated on every row
                // here, never inherited.
                Layout.fillHeight: false
                Layout.leftMargin: Appearance.spacing.space75
                Layout.rightMargin: Appearance.spacing.space75
                spacing: Appearance.spacing.space100

                MaterialSymbol {
                    text: "add_circle"
                    iconSize: 22
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurface
                }
            }

            // One chip per target surface.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.leftMargin: Appearance.spacing.space75
                spacing: Appearance.spacing.space25

                SelectionGroupButton {
                    leftmost: true
                    buttonText: Translation.tr("Widgets")
                    toggled: root.section === "widgets"
                    onClicked: root.section = "widgets"
                }
                SelectionGroupButton {
                    buttonText: Translation.tr("Bar")
                    toggled: root.section === "bar"
                    onClicked: root.section = "bar"
                }
                SelectionGroupButton {
                    buttonText: Translation.tr("Dock")
                    toggled: root.section === "dock"
                    onClicked: root.section = "dock"
                }
                SelectionGroupButton {
                    rightmost: true
                    buttonText: Translation.tr("Lock")
                    toggled: root.section === "lock"
                    onClicked: root.section = "lock"
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.leftMargin: Appearance.spacing.space75
                Layout.rightMargin: Appearance.spacing.space75
                text: root.section === "widgets"
                    ? Translation.tr("Drag a widget onto the desktop to place it, or click to add or remove it.")
                    : root.section === "bar"
                        ? Translation.tr("Click a widget to add it to the picked bar section, then drag it into place on the bar.")
                        : root.section === "dock"
                            ? Translation.tr("Click an app to pin or unpin it, then drag it into place on the dock.")
                            : Translation.tr("Choose what the lock screen shows. The Lockscreen tab previews it.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            // ---- desktop widgets (stage 5's list, unchanged) ---------------
            ListView {
                id: list
                visible: root.section === "widgets"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.spacing.space25
                model: root.section === "widgets" ? root.desktopManifests : []

                delegate: MouseArea {
                    id: entry
                    required property var modelData
                    readonly property bool widgetEnabled: root.enabledIds.includes(entry.modelData.id)

                    width: list.width
                    height: 60
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    // The ListView above is a Flickable, and a Flickable
                    // STEALS a mostly-vertical press-move from any child -
                    // overshoot dragging included, so it fires even while the
                    // content fits - which would end this row's grab with
                    // onCanceled and drop the ghost a few pixels into a
                    // down-then-left drag toward the desktop. The wheel still
                    // scrolls the list; what this declines is flicking it by
                    // dragging a row, which was never the row's gesture.
                    preventStealing: true

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
                        // The rows are not buttons (the drag needs the raw
                        // MouseArea), so the eased hover is declared rather
                        // than inherited - taken whole from the tier whose
                        // reference is the pointer, or the curve silently
                        // falls back to Easing.Linear.
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFaster.colorAnimation.createObject(this)
                        }
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

            // ---- bar widgets ----------------------------------------------
            RowLayout {
                visible: root.section === "bar"
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.leftMargin: Appearance.spacing.space75
                spacing: Appearance.spacing.space25

                SelectionGroupButton {
                    leftmost: true
                    buttonText: root.barVertical ? Translation.tr("Top") : Translation.tr("Left")
                    toggled: root.barBucket === "left"
                    onClicked: root.barBucket = "left"
                }
                SelectionGroupButton {
                    buttonText: Translation.tr("Middle")
                    toggled: root.barBucket === "middle"
                    onClicked: root.barBucket = "middle"
                }
                SelectionGroupButton {
                    rightmost: true
                    buttonText: root.barVertical ? Translation.tr("Bottom") : Translation.tr("Right")
                    toggled: root.barBucket === "right"
                    onClicked: root.barBucket = "right"
                }
            }

            ListView {
                id: barList
                visible: root.section === "bar"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.spacing.space25
                model: root.section === "bar" ? root.barOffer : []

                delegate: RippleButton {
                    required property var modelData
                    width: barList.width
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.large
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.barAddRequested(modelData.id, root.barBucket)

                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: Appearance.spacing.space100
                            rightMargin: Appearance.spacing.space100
                        }
                        spacing: Appearance.spacing.space100

                        MaterialSymbol {
                            text: modelData.icon || "extension"
                            iconSize: 22
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            text: "add"
                            iconSize: 20
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // ---- dock apps ------------------------------------------------
            MaterialTextField {
                id: appSearchField
                visible: root.section === "dock"
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search apps")
            }

            ListView {
                id: appList
                visible: root.section === "dock"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.spacing.space25
                model: root.section !== "dock" ? []
                    : appSearchField.text.length > 0
                        ? AppSearch.fuzzyQuery(appSearchField.text)
                        : AppSearch.list

                delegate: RippleButton {
                    id: appRow
                    required property var modelData
                    // The dock's store speaks lowercase app ids (TaskbarApps
                    // keys its map that way), so the pin is written and read
                    // in that spelling.
                    readonly property string appId: (modelData.id ?? "").toLowerCase()
                    // A binding on TaskbarApps' derived list - a PROPERTY, so
                    // the row follows a pin toggled anywhere (the
                    // LiveDesktopEntry lesson: an invokable like isPinned in
                    // a binding never re-evaluates). Through the service
                    // rather than Config.options.dock, because nothing in the
                    // mode's own files may read the dock's configuration -
                    // that is the one-derivation rule EditModeInsets exists
                    // for, and the contract holds every participant to it.
                    readonly property bool pinned: TaskbarApps.apps.some(
                        app => app.appId === appRow.appId && app.pinned)

                    width: appList.width
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.large
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.dockToggleRequested(appRow.appId)

                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: Appearance.spacing.space100
                            rightMargin: Appearance.spacing.space100
                        }
                        spacing: Appearance.spacing.space100

                        Image {
                            sourceSize.width: 26
                            sourceSize.height: 26
                            source: Quickshell.iconPath(appRow.modelData.icon, "image-missing")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: appRow.modelData.name ?? appRow.appId
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            text: appRow.pinned ? "check_circle" : "add"
                            iconSize: 20
                            color: appRow.pinned
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // ---- lock screen presence -------------------------------------
            ListView {
                id: lockList
                visible: root.section === "lock"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.spacing.space25
                model: root.section === "lock" ? root.lockIslandRows : []

                delegate: RippleButton {
                    id: lockRow
                    required property var modelData
                    // Read per key rather than bracket-indexed: the scope
                    // lint forbids a computed lock path even for a read's
                    // shape, and three keys do not need a lookup.
                    readonly property bool islandOn: lockRow.modelData.key === "showToolbars"
                        ? Config.options.lock.showToolbars
                        : lockRow.modelData.key === "showMedia"
                            ? Config.options.lock.showMedia
                            : Config.options.lock.showWidgets

                    width: lockList.width
                    implicitHeight: 60
                    buttonRadius: Appearance.rounding.large
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.lockToggleRequested(lockRow.modelData.key)

                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: Appearance.spacing.space100
                            rightMargin: Appearance.spacing.space100
                        }
                        spacing: Appearance.spacing.space100

                        MaterialSymbol {
                            text: lockRow.modelData.icon
                            iconSize: 22
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: lockRow.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: lockRow.modelData.description
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                        MaterialSymbol {
                            text: lockRow.islandOn ? "check_circle" : "add"
                            iconSize: 20
                            color: lockRow.islandOn
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
