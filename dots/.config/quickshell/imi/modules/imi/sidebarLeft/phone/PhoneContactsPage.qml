pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects

/**
 * The Phone tab's Contacts sub-page.
 *
 * Rooted on `PhoneSubPage`, which W5a owns: it draws the title bar and the
 * back button and gives this file a ColumnLayout content slot, so everything
 * here states its size with Layout.* rather than anchoring. The interface is
 * pinned by tests/imports/qs/modules/imi/sidebarLeft/phone/PhoneSubPage.qml -
 * a local stub, never a second copy under modules/.
 *
 * Everything on screen comes from PhoneContacts: `filtered` is already the
 * query, the hide-unnamed rule and the sort applied (all three are pure
 * functions the service keeps in sync with its double), and the search field
 * writes `query` rather than filtering here - one list, one set of rules.
 *
 * Avatars are the vCard's own inline `photo`, which arrives as a data URI, so
 * there is no avatar cache to sweep or bust. A contact with no photo gets its
 * first letter.
 */
PhoneSubPage {
    id: root

    title: Translation.tr("Contacts")

    // Which contact's details are open. One at a time: a list where every row
    // can be expanded is a list nobody can scan.
    property string expandedId: ""

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
                placeholderText: Translation.tr("Search contacts or numbers…")
                // The service owns the query so the count and the list cannot
                // disagree about what is being searched.
                onTextChanged: PhoneContacts.query = searchField.text
            }

            RippleButton {
                Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space200
                Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space200
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                // The vCards are watched, so this is for the case the watch
                // cannot see: a monitor that gave up, or a directory that
                // appeared after it started.
                onClicked: PhoneContacts.restartMonitor()

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer3
                }

                StyledToolTip {
                    text: Translation.tr("Re-read the phone's contacts")
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space50
            text: PhoneContacts.ready
                ? Translation.tr("%1 of %2 contacts").arg(PhoneContacts.filtered.length).arg(PhoneContacts.count)
                : Translation.tr("Syncing…")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        // The refusal a dialer or SMS intent came back with. It is a line
        // rather than a toast because it explains what to switch on, and a
        // toast is gone before the phone is in the user's hand.
        RowLayout {
            Layout.fillWidth: true
            visible: PhoneContacts.lastError.length > 0
            spacing: Appearance.spacing.space75

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "error"
                fill: 1
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colError
            }
            StyledText {
                Layout.fillWidth: true
                text: PhoneContacts.lastError
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
                wrapMode: Text.WordWrap
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: contactList
                anchors.fill: parent
                clip: true
                spacing: Appearance.spacing.space75
                model: PhoneContacts.filtered
                // The model is re-filtered on every keystroke, so an
                // appearance animation would pop every row on every letter.
                animateAppearance: false
                visible: PhoneContacts.filtered.length > 0

                delegate: Rectangle {
                    id: contactRow
                    required property var modelData

                    readonly property bool expanded: root.expandedId === contactRow.modelData.id
                    readonly property bool favourite: PhoneContacts.isFavorite(contactRow.modelData.id, PhoneContacts.favorites)
                    readonly property var phones: contactRow.modelData.phones ?? []

                    // The card's padding, spelled ONCE. It used to be two
                    // numbers - `space50` on the column's anchors and
                    // `space100` added to the height - which agree only while
                    // one happens to be exactly twice the other, so changing
                    // either leaves the card a different height from what is
                    // in it. Same coupling `WindowDialog.contentPadding`
                    // removed, one widget down.
                    readonly property real rowPadding: Appearance.spacing.space50

                    width: contactList.width
                    implicitHeight: rowColumn.implicitHeight + contactRow.rowPadding * 2
                    height: implicitHeight
                    radius: Appearance.rounding.normal
                    color: contactRow.expanded ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2

                    Behavior on height {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    ColumnLayout {
                        id: rowColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: contactRow.rowPadding
                        }
                        spacing: Appearance.spacing.space50

                        RippleButton {
                            // Named so a runtime harness can find the three
                            // boxes this card is supposed to contain by name,
                            // rather than by walking a tree whose shape is the
                            // thing being measured.
                            objectName: "contactHeader"
                            Layout.fillWidth: true
                            // No stated height, and the padding said out
                            // loud. A Control sizes itself from its content
                            // item, and what this row holds is a different
                            // height in every script: measured in a real
                            // window, the name-and-number column is 34px tall
                            // for a Latin name and 47 for an Arabic one at
                            // the same pixelSize, because the shell's font
                            // carries no Arabic and the fallback sets taller.
                            // `Layout.preferredHeight: huge * 2` therefore
                            // fitted one script - the avatar ended 6px above
                            // the card's own edge in Latin and 1px in Arabic,
                            // and the NUMBER 3px below it, outside the card.
                            // An aligned layout child answers a cell that is
                            // too small by overflowing it, not by shrinking,
                            // so nothing errors and nothing is logged.
                            verticalPadding: Appearance.spacing.space75
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: root.expandedId = contactRow.expanded ? "" : contactRow.modelData.id

                            contentItem: RowLayout {
                                spacing: Appearance.spacing.space125

                                Rectangle {
                                    id: avatar
                                    objectName: "contactAvatar"
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space200
                                    Layout.preferredHeight: avatar.Layout.preferredWidth
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colPrimaryContainer

                                    StyledText {
                                        anchors.centerIn: parent
                                        visible: photo.status !== Image.Ready
                                        text: String(contactRow.modelData.displayName || "?").charAt(0).toUpperCase()
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }

                                    // The vCard carries the photo inline as a
                                    // data URI, so this is the whole avatar
                                    // pipeline - no file, no cache, nothing to
                                    // invalidate when the phone re-syncs. The
                                    // mask is what rounds it: `clip` on a
                                    // rounded Rectangle clips to the box, not
                                    // to the corner.
                                    StyledImage {
                                        id: photo
                                        anchors.fill: parent
                                        source: contactRow.modelData.photo ?? ""
                                        sourceSize.width: avatar.width * 2
                                        sourceSize.height: avatar.height * 2
                                        fillMode: Image.PreserveAspectCrop
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: avatar.width
                                                height: avatar.height
                                                radius: avatar.width / 2
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    objectName: "contactIdentity"
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        // A contact's name is the phone's own;
                                        // never markup.
                                        textFormat: Text.PlainText
                                        text: contactRow.modelData.displayName || Translation.tr("Unknown")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: {
                                            if (contactRow.modelData.organization)
                                                return contactRow.modelData.organization;
                                            if (contactRow.phones.length > 0)
                                                return contactRow.phones[0].value;
                                            const emails = contactRow.modelData.emails ?? [];
                                            return emails.length > 0 ? emails[0].value : "";
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                RippleButton {
                                    Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer3Hover
                                    colRipple: Appearance.colors.colLayer3Active
                                    onClicked: PhoneContacts.toggleFavorite(contactRow.modelData.id)

                                    contentItem: MaterialSymbol {
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: contactRow.favourite ? "star" : "star_outline"
                                        fill: contactRow.favourite ? 1 : 0
                                        iconSize: Appearance.font.pixelSize.large
                                        color: contactRow.favourite ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                        animateChange: true
                                    }

                                    StyledToolTip {
                                        // Starring is also what keeps a
                                        // nameless card (a SIM import, a
                                        // blocked number) out of the
                                        // hide-unnamed filter.
                                        text: contactRow.favourite
                                            ? Translation.tr("Remove from favourites")
                                            : Translation.tr("Add to favourites")
                                    }
                                }

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: contactRow.expanded ? "expand_less" : "expand_more"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                    animateChange: true
                                }
                            }
                        }

                        ColumnLayout {
                            objectName: "contactDetails"
                            Layout.fillWidth: true
                            Layout.leftMargin: Appearance.spacing.space100
                            Layout.rightMargin: Appearance.spacing.space100
                            Layout.bottomMargin: Appearance.spacing.space50
                            visible: contactRow.expanded
                            spacing: Appearance.spacing.space75

                            Repeater {
                                model: contactRow.phones

                                delegate: RowLayout {
                                    id: phoneRow
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.space100

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: phoneRow.modelData.type === "mobile" ? "smartphone" : "call"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colPrimary
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            text: phoneRow.modelData.value
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer3
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: String(phoneRow.modelData.type || "").length > 0
                                            textFormat: Text.PlainText
                                            text: phoneRow.modelData.type
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                        }
                                    }

                                    RippleButton {
                                        Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colPrimaryContainer
                                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                        colRipple: Appearance.colors.colPrimaryContainerActive
                                        onClicked: PhoneContacts.openDialer(phoneRow.modelData.value)

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: "call"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }

                                        StyledToolTip {
                                            text: Translation.tr("Open the dialer on the phone")
                                        }
                                    }

                                    RippleButton {
                                        Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                        colRipple: Appearance.colors.colSecondaryContainerActive
                                        onClicked: PhoneContacts.composeSms(phoneRow.modelData.value)

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: "sms"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }

                                        StyledToolTip {
                                            text: Translation.tr("Write a message on the phone")
                                        }
                                    }

                                    RippleButton {
                                        Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colLayer4
                                        colBackgroundHover: Appearance.colors.colLayer4Hover
                                        colRipple: Appearance.colors.colLayer4Active
                                        onClicked: Quickshell.clipboardText = phoneRow.modelData.value

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: "content_copy"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer4
                                        }

                                        StyledToolTip {
                                            text: Translation.tr("Copy the number")
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: contactRow.modelData.emails ?? []

                                delegate: RowLayout {
                                    id: emailRow
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.space100

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: "mail"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: emailRow.modelData.value
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer3
                                        elide: Text.ElideRight
                                    }
                                    RippleButton {
                                        Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colLayer4
                                        colBackgroundHover: Appearance.colors.colLayer4Hover
                                        colRipple: Appearance.colors.colLayer4Active
                                        onClicked: Quickshell.clipboardText = emailRow.modelData.value

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: "content_copy"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer4
                                        }

                                        StyledToolTip {
                                            text: Translation.tr("Copy the address")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Three different nothings, and they ask for three different
            // things: wait, search for something else, or switch contact sync
            // on in KDE Connect on the phone.
            PagePlaceholder {
                anchors.fill: parent
                shown: PhoneContacts.filtered.length === 0
                dropIconWhenCramped: true
                icon: PhoneContacts.ready ? "person_search" : "sync"
                shape: MaterialShape.Shape.Ghostish
                title: {
                    if (!PhoneContacts.ready)
                        return Translation.tr("Syncing contacts…");
                    if (PhoneContacts.query.length > 0)
                        return Translation.tr("No contact matches");
                    return Translation.tr("No contacts yet");
                }
                description: {
                    if (!PhoneContacts.ready)
                        return Translation.tr("Reading the cards KDE Connect wrote for this phone.");
                    if (PhoneContacts.query.length > 0)
                        return Translation.tr("Try part of a name or a number.");
                    return Translation.tr("Switch Contacts on in KDE Connect on your phone, then sync.");
                }
            }
        }
    }
}
