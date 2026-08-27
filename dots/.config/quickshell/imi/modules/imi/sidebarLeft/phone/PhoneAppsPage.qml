pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "phone_cards.js" as PhoneCards

/**
 * The Phone tab's Android Apps sub-page: scrcpy's App Mode.
 *
 * Rooted on `PhoneSubPage` (W5a's; the interface is pinned by the stub at
 * tests/imports/qs/modules/imi/sidebarLeft/phone/PhoneSubPage.qml).
 *
 * Every app draws the generic `android` glyph. Pulling launcher icons off the
 * phone is explicitly out of scope this round (spec, "Non-goals"), and the
 * glyph is what the fork falls back to anyway whenever its extractor cannot
 * resolve one.
 *
 * The search query lives HERE rather than on PhoneScrcpy: a text field on one
 * page writing a property on a singleton makes the query global state, and the
 * filter itself is phone_cards.js's `filterApps` (tests/tst_phone_cards.qml).
 */
PhoneSubPage {
    id: root

    title: Translation.tr("Android Apps")

    property string query: ""

    readonly property var filteredApps: PhoneCards.filterApps(PhoneScrcpy.apps, root.query)

    // The live sessions, as a plain list. PhoneScrcpy.sessions is a ListModel,
    // which is not a binding source - `sessionCount` is read so this
    // re-evaluates when a window opens or closes.
    readonly property var appSessions: {
        const rows = [];
        const count = PhoneScrcpy.sessionCount;
        for (let index = 0; index < count; index++) {
            const row = PhoneScrcpy.sessions.get(index);
            if (row.type === "app")
                rows.push({ id: row.id, package: row.package, title: row.title });
        }
        return rows;
    }

    // The list is asked for once, when the page opens with nothing in it.
    // Never on a timer and never from a binding: `--list-apps` starts a scrcpy
    // against the phone.
    Component.onCompleted: {
        if (PhoneScrcpy.appModeSupported && PhoneScrcpy.apps.length === 0 && !PhoneScrcpy.appsLoading)
            PhoneScrcpy.refreshApps();
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Appearance.spacing.space100

        // The search row is content-height, stated rather than left to the
        // default: `ToolbarTextField` declares `Layout.fillHeight: true` of
        // its own, which makes this row's maximum height unbounded, and a
        // nested layout defaults to filling - so the row would take the
        // column's whole leftover and leave the list eight pixels.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "search"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }

            ToolbarTextField {
                id: searchField
                Layout.fillWidth: true
                enabled: PhoneScrcpy.appModeSupported
                placeholderText: Translation.tr("Search apps…")
                onTextChanged: root.query = searchField.text
            }

            RippleButton {
                Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space200
                Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space200
                enabled: PhoneScrcpy.appModeSupported && !PhoneScrcpy.appsLoading
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: PhoneScrcpy.refreshApps()

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer3
                }

                StyledToolTip {
                    text: Translation.tr("Ask the phone for its app list")
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space50
            text: {
                if (!PhoneScrcpy.appModeSupported)
                    return Translation.tr("App Mode needs scrcpy 4.0 or newer");
                if (PhoneScrcpy.appsLoading)
                    return Translation.tr("Reading the phone's app list…");
                if (PhoneScrcpy.appsError.length > 0)
                    return PhoneScrcpy.appsError;
                return Translation.tr("%1 of %2 apps").arg(root.filteredApps.length).arg(PhoneScrcpy.apps.length);
            }
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: PhoneScrcpy.appsError.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        // ---- what is running right now ----
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.appSessions.length > 0
            spacing: Appearance.spacing.space50

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.spacing.space50
                    text: Translation.tr("Active sessions (%1)").arg(root.appSessions.length)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                RippleButton {
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space50
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.colors.colErrorContainerActive
                    onClicked: PhoneScrcpy.stopAllApps()

                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Stop all")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colError
                    }
                }
            }

            Repeater {
                model: root.appSessions

                delegate: Rectangle {
                    id: sessionRow
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: sessionLayout.implicitHeight + Appearance.spacing.space100
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimaryContainer

                    RowLayout {
                        id: sessionLayout
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Appearance.spacing.space125
                            rightMargin: Appearance.spacing.space75
                        }
                        spacing: Appearance.spacing.space100

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "play_circle"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            // A package name is the phone's own; never markup.
                            textFormat: Text.PlainText
                            text: PhoneCards.appLabel({ package: sessionRow.modelData.package })
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                            elide: Text.ElideRight
                        }

                        RippleButton {
                            Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space125
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            onClicked: PhoneScrcpy.focusApp(sessionRow.modelData.package)

                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Focus")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }

                        RippleButton {
                            Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space125
                            Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space125
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colErrorContainer
                            colBackgroundHover: Appearance.colors.colErrorContainerHover
                            colRipple: Appearance.colors.colErrorContainerActive
                            onClicked: PhoneScrcpy.stopApp(sessionRow.modelData.package)

                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "close"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnErrorContainer
                            }

                            StyledToolTip {
                                text: Translation.tr("Close this session")
                            }
                        }
                    }
                }
            }
        }

        // ---- the starred apps, as a strip ----
        ColumnLayout {
            Layout.fillWidth: true
            visible: favouriteRepeater.count > 0
            spacing: Appearance.spacing.space50

            StyledText {
                Layout.leftMargin: Appearance.spacing.space50
                text: Translation.tr("Favourites")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }

            Flow {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50

                Repeater {
                    id: favouriteRepeater
                    model: PhoneCards.filterApps(PhoneScrcpy.apps, "")
                        .filter(app => PhoneScrcpy.isFavorite(app.package))

                    delegate: RippleButton {
                        id: favouriteChip
                        required property var modelData

                        readonly property bool running: PhoneScrcpy.isAppRunning(favouriteChip.modelData.package)
                        implicitHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                        buttonRadius: Appearance.rounding.full
                        colBackground: favouriteChip.running ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                        colBackgroundHover: favouriteChip.running ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer3Hover
                        colRipple: favouriteChip.running ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer3Active
                        onClicked: PhoneScrcpy.launchApp(favouriteChip.modelData.package)

                        contentItem: RowLayout {
                            spacing: Appearance.spacing.space50

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "android"
                                iconSize: Appearance.font.pixelSize.small
                                color: favouriteChip.running
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer3
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                textFormat: Text.PlainText
                                text: PhoneCards.appLabel(favouriteChip.modelData)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: favouriteChip.running
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer3
                            }
                        }
                    }
                }
            }
        }

        // ---- every app on the phone ----
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: appList
                anchors.fill: parent
                clip: true
                spacing: Appearance.spacing.space50
                model: root.filteredApps
                animateAppearance: false
                visible: root.filteredApps.length > 0

                delegate: Rectangle {
                    id: appRow
                    required property var modelData

                    readonly property bool running: PhoneScrcpy.isAppRunning(appRow.modelData.package)

                    width: appList.width
                    // A constant off the token scale rather than the content's
                    // own height: the row's content is the fill-anchored
                    // button's contentItem, so deriving the row from it is a
                    // cycle QtQuick never converges on.
                    height: Appearance.font.pixelSize.huge * 2 + Appearance.spacing.space100
                    radius: Appearance.rounding.normal
                    color: appRow.running ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    RippleButton {
                        anchors.fill: parent
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        // launchApp() focuses an app that is already up, so
                        // there is no second copy of that decision here.
                        onClicked: PhoneScrcpy.launchApp(appRow.modelData.package)

                        contentItem: RowLayout {
                            spacing: Appearance.spacing.space125

                            MaterialShapeWrappedMaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                // The generic glyph, deliberately: pulling
                                // launcher icons off the phone is a follow-up
                                // (spec, "Non-goals").
                                text: "android"
                                wrappedShape: MaterialShape.Shape.Cookie9Sided
                                iconSize: Appearance.font.pixelSize.small
                                padding: Appearance.spacing.space75
                                color: appRow.running
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSecondaryContainer
                                colSymbol: appRow.running
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnSecondaryContainer
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: PhoneCards.appLabel(appRow.modelData)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: appRow.running
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: appRow.modelData.package
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }

                            RippleButton {
                                id: starButton
                                readonly property bool favourite: PhoneScrcpy.isFavorite(appRow.modelData.package)

                                Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                colRipple: Appearance.colors.colLayer3Active
                                onClicked: PhoneScrcpy.toggleFavorite(appRow.modelData.package)

                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: starButton.favourite ? "star" : "star_outline"
                                    fill: starButton.favourite ? 1 : 0
                                    iconSize: Appearance.font.pixelSize.large
                                    color: starButton.favourite ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    animateChange: true
                                }

                                StyledToolTip {
                                    text: starButton.favourite
                                        ? Translation.tr("Remove from favourites")
                                        : Translation.tr("Add to favourites")
                                }
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: appRow.running ? "open_in_new" : "play_arrow"
                                iconSize: Appearance.font.pixelSize.larger
                                color: appRow.running ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

            PagePlaceholder {
                anchors.fill: parent
                shown: root.filteredApps.length === 0
                dropIconWhenCramped: true
                icon: PhoneScrcpy.appModeSupported ? "apps" : "warning"
                shape: MaterialShape.Shape.Ghostish
                title: {
                    if (!PhoneScrcpy.appModeSupported)
                        return Translation.tr("App Mode is not available");
                    if (PhoneScrcpy.appsLoading)
                        return Translation.tr("Reading the app list…");
                    if (root.query.length > 0)
                        return Translation.tr("No app matches");
                    return Translation.tr("No apps yet");
                }
                description: {
                    if (!PhoneScrcpy.appModeSupported)
                        return Translation.tr("scrcpy 4.0 or newer is needed to start one app on a display of its own.");
                    if (PhoneScrcpy.appsLoading)
                        return Translation.tr("scrcpy is asking the phone what it has installed.");
                    if (root.query.length > 0)
                        return Translation.tr("Try part of a name or a package.");
                    return Translation.tr("Connect the phone over USB or wireless debugging, then refresh.");
                }
            }
        }
    }
}
