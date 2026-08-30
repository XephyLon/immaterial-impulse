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
 * ---- what a row is ----------------------------------------------------------
 *
 * `CatalogueRow` - the icon/name/description/affordance shape this file used to
 * spell out once per row shape, shared with every settings row and the widget
 * store. Counting them here is what went stale the first time a row was added,
 * so the rule is stated instead: EVERY row body in this file is that component,
 * and `test_edit_mode_contract.py` reads them one by one. The rows' INTERACTION
 * is still each section's own, and deliberately: the desktop section's rows are
 * `MouseArea`s (see above), every other row is a `RippleButton`, and the shared
 * component is not interactive at all so it can sit inside either.
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
    // One widget's presence on the lock screen. The first one forks the lock's
    // widget choice from the desktop's, the same way the first move forks the
    // layout - the drawer never forks by itself, a pick does.
    signal lockWidgetToggleRequested(string pluginId)
    // The lock layout's re-link: this screen's widgets go back to following
    // the desktop's arrangement. Only offered while the screen is forked.
    signal lockLayoutResetRequested()
    // The same, for the widget choice. Two questions, two re-links: a user who
    // arranged the lock screen apart from the desktop has not necessarily
    // picked a different set of widgets for it, and re-linking one must not
    // silently discard the other.
    signal lockPresenceResetRequested()

    // The chrome surface reads this to take OnDemand keyboard focus while
    // the search field is being typed into - and only then.
    readonly property bool searchTakesKeys: appSearchField.activeFocus
    onSectionChanged: appSearchField.focus = false

    // Which screen this drawer is arranging - handed in by the surface, so
    // the fork question below is asked about the right monitor.
    property string screenName: ""
    readonly property bool lockLayoutForked: PluginState.lockLayoutForked(root.screenName)
    // Presence is one global choice, not a per-screen one: `plugins.enabled`
    // is one list drawn on every monitor, so the lock's fork of it is too.
    readonly property bool lockPresenceForked: PluginState.lockPresenceForked()

    // A desktop widget is being carried over this screen's drawer, so letting
    // go will REMOVE it rather than move it. Written by the widget, because the
    // pointer and the grab are on the background surface; drawn here, because
    // the widget itself is under this panel by then and cannot show anything.
    //
    // Deliberately not gated on the SECTION showing. The reveal is one
    // rectangle and the abandon check on the way out does not ask which section
    // it is either: the section filters the CATALOGUE, it does not decide what
    // the panel is. A gesture that silently did nothing on three sections out
    // of four would be the quiet failure this repo keeps paying for.
    readonly property bool dropWouldRemove: root.screenName !== ""
        && GlobalStates.editDrawerDropScreen === root.screenName

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
        { kind: "island", key: "showToolbars", name: Translation.tr("Toolbars"),
            icon: "call_to_action",
            description: Translation.tr("The islands beside the password field") },
        { kind: "island", key: "showMedia", name: Translation.tr("Media player"),
            icon: "music_note",
            description: Translation.tr("Playback info while music is playing") },
        { kind: "island", key: "showWidgets", name: Translation.tr("Desktop widgets"),
            icon: "widgets",
            // The master gate's own caption has to say which of the two states
            // the choice below it is in, or "every" goes on claiming something
            // the picked rows have stopped doing.
            description: root.lockPresenceForked
                ? Translation.tr("Show the widgets picked below while locked")
                : Translation.tr("Show every desktop widget while locked") }
    ]

    // The per-widget presence rows, under the master gate: with
    // `lock.showWidgets` off the lock screen shows no desktop widget at all,
    // so a picker there would be a row of controls that change nothing. The
    // gate is the row directly above them.
    readonly property var lockWidgetRows: Config.options.lock.showWidgets
        ? root.desktopManifests.map(manifest => ({
            kind: "widget",
            id: manifest.id,
            name: manifest.name,
            icon: "widgets",
            description: manifest.description ?? ""
        }))
        : []

    // One list, two kinds of row: the islands, then the widgets they sit
    // among. Two ListViews would each want the column's height and would put
    // the picker's own scroll position somewhere the islands are not.
    readonly property var lockRows: root.lockIslandRows.concat(root.lockWidgetRows)

    // ---- the entrance --------------------------------------------------------
    //
    // The panel arrives as a surface and THEN fills, rather than sliding in with
    // everything already in it. That is the one grammar the motion survey found
    // measured off the sibling fork and missing here
    // (docs/p3drovfx-motion-measured-2026-08-22.md §2.1, §4.2): their container
    // is at 90% by 133ms and its first child does not reach 50% until 233ms,
    // while every group in this shell arrived all at once because nothing asked
    // it not to.
    //
    // Three rules, none of them this file's. The wave itself is a `StaggerWave`
    // declared beside the column it walks - the ranking, the clamp, the scaled
    // step and the cancellation are the shared runner's, so this file decides
    // only WHEN.
    //
    //  - the contents wait for the container (`Appearance.animation.contentGate`),
    //  - they are ranked by VISIBLE position, which matters more here than
    //    anywhere else that staggers: only one of the four sections is drawn at
    //    a time, so most of the column is hidden on any given open and an
    //    unranked wave would spend most of its clamped slots on nothing,
    //  - and they do NOT leave on the close. `contentsIn` stays true for the
    //    whole exit, so the rows ride the panel off as one rigid transform, and
    //    the reset happens once the reveal has no width left - off screen, where
    //    nobody sees a member snap back to its start.
    readonly property bool opening: GlobalStates.editDrawerOpen
    readonly property bool contentsIn: Appearance.animation.contentsArrived(
        GlobalStates.editDrawerProgress, root.opening)

    // A member arrives with three properties moving together, not as a fade:
    // opacity, a scale, and a small rise, all on one `appear` scalar so they
    // cannot finish on different schedules (docs/M3_GUIDELINES.md §2,
    // "Component Entrance and Exit"). That dressing used to be spelled out
    // here once per member; it is the shared `StaggerEntrance` beside the wave
    // now, and the derivation this file carried - the scale's excursion
    // matched to the rise, floored at the survey's 0.85 - lives in
    // motion_policy.js where a test can hold it still. A member's whole opt-in
    // is `property real appear: 1`.

    // Arming and running are two events, not one, and measuring showed why.
    // Setting the members to zero inside the wave meant they were drawn at full
    // strength inside the first 100ms of reveal - the whole run up to the gate -
    // and then blinked out to cascade back in. Nothing about a gate implies
    // "and the contents were visible until now": they have to be put away when
    // the gesture starts, which is the intent flipping, and let out when the
    // container has arrived, which is the gate.
    onOpeningChanged: {
        if (root.opening)
            entrance.park();
    }

    onContentsInChanged: {
        if (root.contentsIn)
            entrance.enter();
        else
            entrance.settle();
    }

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

        // "Let go here and this widget leaves the desktop", in the drawer's
        // OWN row vocabulary rather than a new one: a row that is being pressed
        // paints `colLayer2Active` over this same body, and the pointer IS down
        // for the whole of the gesture this answers, so the panel takes the
        // pressed tone the way one of its rows would. Declared before the
        // column so it tints the body and not the rows, and it takes the same
        // tier whole - the one whose reference is the pointer.
        Rectangle {
            anchors.fill: parent
            radius: panel.radius
            color: root.dropWouldRemove
                ? Appearance.colors.colLayer2Active : "transparent"
            Behavior on color {
                animation: Appearance.animation.elementMoveFaster.colorAnimation.createObject(this)
            }
        }

        ColumnLayout {
            id: drawerColumn
            anchors.fill: parent
            anchors.margins: Appearance.spacing.space150
            spacing: Appearance.spacing.space100

            // The group's arrival, through the one runner every staggered
            // surface in this shell asks - the ranking, the clamp, the scaled
            // step and the cancellation are all its, so the drawer cannot
            // disagree with the sidebar about any of them.
            //
            // No `leadIn`, deliberately, and it is the one thing this adopter
            // does differently: every other container's motion is something
            // QML has no scalar for - a settings page's cross-fade, a layer
            // surface the compositor slides - so a fixed head start is the
            // best available guess at "the container is there now". This
            // drawer's reveal IS `GlobalStates.editDrawerProgress`, so the
            // gate above asks the real question and the wave is simply not
            // started until it answers. A lead-in as well would be two waits
            // in front of one wave, only one of them answerable.
            StaggerWave {
                id: entrance
                target: drawerColumn
            }

            // ...and what arriving looks like: the shared three-channel
            // dressing, walking the same column. The reference is the PANEL's
            // width, not the column's - the column is inset by its margins and
            // the derivation's input has been the panel since the drawer first
            // dressed its members. The lock section's two re-link rows are
            // `RippleButton`s and are skipped by the dresser itself: a control
            // owns `scale` through the interaction model and folds `appear`
            // into the opacity binding that carries its disabled dim, so it
            // rides the wave through the property the runner writes.
            StaggerEntrance {
                target: drawerColumn
                reference: root.panelWidth
            }

            RowLayout {
                id: addHeaderRow
                property real appear: 1
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
                id: sectionChipRow
                property real appear: 1
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
                id: sectionHint
                property real appear: 1
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
                property real appear: 1
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

                    CatalogueRow {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.spacing.space100
                        anchors.rightMargin: Appearance.spacing.space100
                        rowSpacing: Appearance.spacing.space100

                        rowIcon: "widgets"
                        rowIconSize: 22
                        rowIconColor: Appearance.colors.colOnSurfaceVariant
                        title: entry.modelData.name
                        titleFont.pixelSize: Appearance.font.pixelSize.normal
                        titleColor: Appearance.colors.colOnSurface
                        titleFillsWidth: true
                        titleElides: true
                        description: entry.modelData.description ?? ""
                        descriptionColor: Appearance.colors.colOnSurfaceVariant
                        descriptionWraps: false

                        affordance: [
                            MaterialSymbol {
                                text: entry.widgetEnabled ? "check_circle" : "add"
                                iconSize: 20
                                color: entry.widgetEnabled
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOnSurfaceVariant
                            }
                        ]
                    }
                }
            }

            // ---- bar widgets ----------------------------------------------
            RowLayout {
                id: barBucketRow
                property real appear: 1
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
                property real appear: 1
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

                    contentItem: CatalogueRow {
                        anchors {
                            fill: parent
                            leftMargin: Appearance.spacing.space100
                            rightMargin: Appearance.spacing.space100
                        }
                        rowSpacing: Appearance.spacing.space100

                        rowIcon: modelData.icon || "extension"
                        rowIconSize: 22
                        rowIconColor: Appearance.colors.colOnSurfaceVariant
                        title: modelData.name
                        titleFont.pixelSize: Appearance.font.pixelSize.normal
                        titleColor: Appearance.colors.colOnSurface
                        titleFillsWidth: true
                        titleElides: true

                        affordance: [
                            MaterialSymbol {
                                text: "add"
                                iconSize: 20
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        ]
                    }
                }
            }

            // ---- dock apps ------------------------------------------------
            //
            // The filled search row every other list in the shell carries
            // (the phone apps page is the reference) - the outlined field
            // that stood here read as a stranger. Typing works because the
            // chrome surface takes OnDemand keyboard focus for exactly as
            // long as this field holds focus (see EditModeChromeSurface):
            // the surface is None by default so the canvas keeps Escape.
            RowLayout {
                id: dockSearchRow
                property real appear: 1
                visible: root.section === "dock"
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "search"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                }
                ToolbarTextField {
                    id: appSearchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search apps")
                    // First Escape leaves the field (and returns the
                    // surface to None); the next one walks the mode's own
                    // ladder on the canvas.
                    Keys.onEscapePressed: appSearchField.focus = false
                }
            }

            ListView {
                id: appList
                property real appear: 1
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

                    contentItem: CatalogueRow {
                        anchors {
                            fill: parent
                            leftMargin: Appearance.spacing.space100
                            rightMargin: Appearance.spacing.space100
                        }
                        rowSpacing: Appearance.spacing.space100

                        // An app's leading visual is its own icon, not a
                        // glyph - the one thing in this catalogue that is not
                        // a Material Symbol, and what iconComponent is for.
                        iconComponent: Image {
                            sourceSize.width: 26
                            sourceSize.height: 26
                            source: Quickshell.iconPath(appRow.modelData.icon, "image-missing")
                        }
                        title: appRow.modelData.name ?? appRow.appId
                        titleFont.pixelSize: Appearance.font.pixelSize.normal
                        titleColor: Appearance.colors.colOnSurface
                        titleFillsWidth: true
                        titleElides: true

                        affordance: [
                            MaterialSymbol {
                                text: appRow.pinned ? "check_circle" : "add"
                                iconSize: 20
                                color: appRow.pinned
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOnSurfaceVariant
                            }
                        ]
                    }
                }
            }

            // ---- lock screen presence -------------------------------------
            ListView {
                id: lockList
                property real appear: 1
                visible: root.section === "lock"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.spacing.space25
                model: root.section === "lock" ? root.lockRows : []

                delegate: RippleButton {
                    id: lockRow
                    required property var modelData
                    readonly property bool isWidget: lockRow.modelData.kind === "widget"
                    // Read per key rather than bracket-indexed: the scope
                    // lint forbids a computed lock path even for a read's
                    // shape, and three keys do not need a lookup.
                    readonly property bool islandOn: lockRow.modelData.key === "showToolbars"
                        ? Config.options.lock.showToolbars
                        : lockRow.modelData.key === "showMedia"
                            ? Config.options.lock.showMedia
                            : Config.options.lock.showWidgets
                    // A widget row's check follows the lock's own choice,
                    // which reads through to the desktop's enabled set until
                    // the first pick forks it - so the rows open showing
                    // exactly what the lock screen shows today.
                    readonly property bool rowOn: lockRow.isWidget
                        ? PluginState.lockWidgetEnabled(lockRow.modelData.id)
                        : lockRow.islandOn

                    width: lockList.width
                    implicitHeight: 60
                    buttonRadius: Appearance.rounding.large
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: lockRow.isWidget
                        ? root.lockWidgetToggleRequested(lockRow.modelData.id)
                        : root.lockToggleRequested(lockRow.modelData.key)

                    contentItem: CatalogueRow {
                        anchors {
                            fill: parent
                            // The widget rows are the master gate's contents,
                            // and the indent is what says so - they follow it
                            // in one list and would otherwise read as three
                            // more things the lock screen has.
                            leftMargin: lockRow.isWidget
                                ? Appearance.spacing.space300
                                : Appearance.spacing.space100
                            rightMargin: Appearance.spacing.space100
                        }
                        rowSpacing: Appearance.spacing.space100

                        rowIcon: lockRow.modelData.icon
                        rowIconSize: 22
                        rowIconColor: Appearance.colors.colOnSurfaceVariant
                        title: lockRow.modelData.name
                        titleFont.pixelSize: Appearance.font.pixelSize.normal
                        titleColor: Appearance.colors.colOnSurface
                        titleFillsWidth: true
                        titleElides: true
                        // A widget row carries the manifest's own
                        // description, which a manifest may omit - the shared
                        // row draws the label only when it has one, so the
                        // `?? ""` is about not assigning undefined to a
                        // string, not about the empty row's height.
                        description: lockRow.modelData.description ?? ""
                        descriptionColor: Appearance.colors.colOnSurfaceVariant
                        descriptionWraps: false

                        affordance: [
                            MaterialSymbol {
                                text: lockRow.rowOn ? "check_circle" : "add"
                                iconSize: 20
                                color: lockRow.rowOn
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOnSurfaceVariant
                            }
                        ]
                    }
                }
            }

            // ---- lock screen widget choice: forked or following -----------
            //
            // The same row the layout gets below, for the other half of the
            // fork: which widgets the lock screen shows inherits the desktop's
            // set until the first pick above, and this says which state it is
            // in and offers the way back. Only while the master gate is on -
            // with the lock showing no widgets at all, "follows the desktop"
            // is a claim about a set nobody can see.
            //
            // Neither this row nor the layout re-link below it is dressed by
            // the StaggerEntrance above - the dresser itself skips a member
            // that owns an `interactionMotion` - and both still arrive with
            // the wave. A `RippleButton` declares `appear` itself and folds it
            // into its own opacity and a 6px rise, so the runner reaches it
            // like any other member - measured, these two land one and two
            // steps behind the list. What it must not be handed is a second
            // writer of either channel: `scale` is `interactionMotion`'s (a
            // scale here replaces the control's rather than composing with it
            // - lint_interaction_motion_double.py) and that same opacity
            // binding carries the disabled dim (a second one draws this row as
            // enabled while it is not - lint_disabled_opacity.py, and the bug
            // ExpandablePanel's `appear` indirection exists for).
            RippleButton {
                id: lockPresenceRow
                visible: root.section === "lock" && Config.options.lock.showWidgets
                enabled: root.lockPresenceForked
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 60
                buttonRadius: Appearance.rounding.large
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.lockPresenceResetRequested()

                contentItem: CatalogueRow {
                    anchors {
                        fill: parent
                        leftMargin: Appearance.spacing.space100
                        rightMargin: Appearance.spacing.space100
                    }
                    rowSpacing: Appearance.spacing.space100

                    rowIcon: root.lockPresenceForked ? "call_split" : "link"
                    rowIconSize: 22
                    rowIconColor: Appearance.colors.colOnSurfaceVariant
                    title: root.lockPresenceForked
                        ? Translation.tr("Widget choice is separate")
                        : Translation.tr("Widget choice follows the desktop")
                    titleFont.pixelSize: Appearance.font.pixelSize.normal
                    titleColor: Appearance.colors.colOnSurface
                    titleFillsWidth: true
                    titleElides: true
                    description: root.lockPresenceForked
                        ? Translation.tr("Click to show the desktop's widgets again")
                        : Translation.tr("Pick a widget above to choose the lock screen's own")
                    descriptionColor: Appearance.colors.colOnSurfaceVariant
                    descriptionWraps: false

                    affordance: [
                        MaterialSymbol {
                            visible: root.lockPresenceForked
                            text: "restart_alt"
                            iconSize: 20
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    ]
                }
            }

            // ---- lock screen layout: forked or following ------------------
            //
            // The widgets' arrangement on the lock screen inherits the
            // desktop's until the first move on the Lockscreen tab forks it
            // (spec §4.3 as amended). This row says which state the screen is
            // in, and while forked offers the way back - the drawer never
            // forks by itself; a drag does that.
            //
            // Undressed (the StaggerEntrance skips it), for the reason stated
            // on the widget-choice row above: this is a `RippleButton` and it
            // rides the wave through its own `appear`.
            RippleButton {
                id: lockLayoutRow
                visible: root.section === "lock"
                enabled: root.lockLayoutForked
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 60
                buttonRadius: Appearance.rounding.large
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.lockLayoutResetRequested()

                contentItem: CatalogueRow {
                    anchors {
                        fill: parent
                        leftMargin: Appearance.spacing.space100
                        rightMargin: Appearance.spacing.space100
                    }
                    rowSpacing: Appearance.spacing.space100

                    rowIcon: root.lockLayoutForked ? "call_split" : "link"
                    rowIconSize: 22
                    rowIconColor: Appearance.colors.colOnSurfaceVariant
                    title: root.lockLayoutForked
                        ? Translation.tr("Widget layout is separate")
                        : Translation.tr("Widget layout follows the desktop")
                    titleFont.pixelSize: Appearance.font.pixelSize.normal
                    titleColor: Appearance.colors.colOnSurface
                    titleFillsWidth: true
                    titleElides: true
                    description: root.lockLayoutForked
                        ? Translation.tr("Click to use the desktop layout again")
                        : Translation.tr("Move a widget here to arrange the lock screen on its own")
                    descriptionColor: Appearance.colors.colOnSurfaceVariant
                    descriptionWraps: false

                    affordance: [
                        MaterialSymbol {
                            visible: root.lockLayoutForked
                            text: "restart_alt"
                            iconSize: 20
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    ]
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
