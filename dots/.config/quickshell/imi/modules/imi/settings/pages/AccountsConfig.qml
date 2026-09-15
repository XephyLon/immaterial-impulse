import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings > Accounts (docs/proposals/accounts-integration.md): the Google
 * account (the user's own OAuth client, connect / disconnect, which features
 * read it), Proton (VPN through the official app's session; what has no API),
 * and the calendar feeds every account's ICS link can join.
 */
ContentPage {
    id: page
    forceWidth: true

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.scrollToY(pos.y)
        }
    }
    readonly property var google: Config.options.accounts.google
    property string clientIdDraft: GoogleAccount.clientId
    property string clientSecretDraft: GoogleAccount.clientSecret
    readonly property bool clientDirty: page.clientIdDraft.trim() !== GoogleAccount.clientId || page.clientSecretDraft.trim() !== GoogleAccount.clientSecret

    ContentSection {
        icon: "account_circle"
        shape: MaterialShape.Shape.Cookie9Sided
        title: Translation.tr("Google")

        NoticeBox {
            Layout.fillWidth: true
            visible: !GoogleAccount.configured
            materialIcon: "key"
            text: Translation.tr("Google needs an OAuth client of your own: in the Google Cloud console create a Desktop app client (APIs & Services > Credentials), enable the Calendar, Tasks and Gmail APIs, and paste its ID and secret here. They are stored in the keyring.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: GoogleAccount.lastError.length > 0
            materialIcon: "error"
            colBackground: Appearance.colors.colErrorContainer
            colOnBackground: Appearance.m3colors.m3onErrorContainer
            text: GoogleAccount.lastError
        }

        ContentSubsection {
            title: Translation.tr("Sign in")

            GroupedList {
                ConfigTextArea {
                    buttonIcon: "badge"
                    singleLine: true
                    placeholderText: Translation.tr("OAuth client ID")
                    value: page.clientIdDraft
                    onValueChanged: page.clientIdDraft = value
                }
                ConfigTextArea {
                    buttonIcon: "password"
                    singleLine: true
                    placeholderText: Translation.tr("OAuth client secret")
                    value: page.clientSecretDraft
                    onValueChanged: page.clientSecretDraft = value
                    password: true
                    confirmButtonVisible: page.clientDirty && page.clientIdDraft.trim().length > 0 && page.clientSecretDraft.trim().length > 0
                    confirmButtonIcon: "save"
                    onConfirmClicked: GoogleAccount.setClient(page.clientIdDraft, page.clientSecretDraft)
                }
                ConfigRow {
                    MaterialSymbol {
                        text: GoogleAccount.connected ? "verified_user" : "person_off"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: GoogleAccount.connected
                            ? (GoogleAccount.email.length > 0 ? Translation.tr("Signed in as %1").arg(GoogleAccount.email) : Translation.tr("Signed in"))
                            : GoogleAccount.connecting ? Translation.tr("Finish the sign-in in your browser…")
                            : Translation.tr("Not signed in")
                        color: Appearance.colors.colOnLayer1
                    }
                    RippleButtonWithIcon {
                        enabled: GoogleAccount.configured && !GoogleAccount.connecting
                        opacity: enabled ? 1 : 0.5
                        materialIcon: GoogleAccount.connected ? "logout" : "login"
                        mainText: GoogleAccount.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                        onClicked: GoogleAccount.connected ? GoogleAccount.disconnect() : GoogleAccount.connect()
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("What the shell reads")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "calendar_month"
                    text: Translation.tr("Calendar")
                    checked: page.google.calendar
                    onToggleRequested: Config.options.accounts.google.calendar = !Config.options.accounts.google.calendar
                    description: GoogleCalendar.enabled && GoogleCalendar.calendars.length > 0
                        ? Translation.tr("%1 calendar(s), %2 event(s) in the next %3 days - in the sidebar calendar and for the assistant").arg(GoogleCalendar.calendars.length).arg(GoogleCalendar.eventCount).arg(GoogleCalendar.days)
                        : Translation.tr("Your selected calendars' events, in the sidebar calendar and for the assistant")
                }
                ConfigSwitch {
                    buttonIcon: "task_alt"
                    text: Translation.tr("Tasks")
                    checked: page.google.tasks
                    onToggleRequested: Config.options.accounts.google.tasks = !Config.options.accounts.google.tasks
                    description: Translation.tr("Your task lists in the sidebar to-do, next to the local one")
                }
                ConfigSwitch {
                    buttonIcon: "mail"
                    text: Translation.tr("Mail")
                    checked: page.google.mail
                    onToggleRequested: Config.options.accounts.google.mail = !Config.options.accounts.google.mail
                    description: Translation.tr("The inbox's unread count, for the bar's Mail widget")
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Refresh every (min)")
                    value: page.google.refreshMinutes
                    from: 1
                    to: 60
                    stepSize: 1
                    onValueModified: Config.options.accounts.google.refreshMinutes = newValue
                }
                ConfigSpinBox {
                    property bool rowVisible: page.google.calendar
                    icon: "date_range"
                    text: Translation.tr("Calendar days ahead")
                    value: page.google.calendarDays
                    from: 1
                    to: 90
                    stepSize: 1
                    onValueModified: Config.options.accounts.google.calendarDays = newValue
                }
            }
        }
    }

    ContentSection {
        icon: "shield"
        shape: MaterialShape.Shape.Clover4Leaf
        title: Translation.tr("Proton")

        ContentSubsection {
            title: Translation.tr("VPN")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "vpn_lock"
                    text: Translation.tr("Proton VPN in the quick panel")
                    checked: Config.options.accounts.proton.vpn.enable
                    onToggleRequested: Config.options.accounts.proton.vpn.enable = !Config.options.accounts.proton.vpn.enable
                    description: !ProtonVpn.probed ? Translation.tr("Checking…")
                        : !ProtonVpn.installed ? Translation.tr("Needs the official app (proton-vpn-gtk-app) and its Python API")
                        : !ProtonVpn.loggedIn ? Translation.tr("Sign in once in the Proton VPN app; the shell uses that session")
                        : ProtonVpn.connected ? Translation.tr("Connected to %1 as %2").arg(ProtonVpn.server).arg(ProtonVpn.account)
                        : Translation.tr("Signed in as %1 - the toggle connects to the fastest server").arg(ProtonVpn.account)
                }
                ConfigSpinBox {
                    property bool rowVisible: Config.options.accounts.proton.vpn.enable
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (s)")
                    value: Config.options.accounts.proton.vpn.pollInterval / 1000
                    from: 5
                    to: 120
                    stepSize: 5
                    onValueModified: Config.options.accounts.proton.vpn.pollInterval = newValue * 1000
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Calendar, Mail and Pass")

            GroupedList {
                ConfigRow {
                    MaterialSymbol { text: "event"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Proton Calendar has no API; share a calendar as a link in Proton Calendar and add it to the feeds below.")
                        color: Appearance.colors.colOnLayer1
                    }
                }
                ConfigRow {
                    MaterialSymbol { text: "mail"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Proton Mail reaches the desktop only through Proton Bridge; an unread count over it is planned, not built.")
                        color: Appearance.colors.colOnLayer1
                    }
                }
                ConfigRow {
                    MaterialSymbol { text: "key_off"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Proton Pass has no Linux API or command line, so the shell offers nothing for it.")
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "rss_feed"
        shape: MaterialShape.Shape.Pill
        title: Translation.tr("Calendar feeds")

        ContentSubsection {
            title: Translation.tr("ICS links")

            GroupedList {
                visible: (Config.options.calendar.ics.urls ?? []).length > 0
                model: Config.options.calendar.ics.urls
                rowDelegate: Component {
                    RowLayout {
                        id: urlRow
                        property var modelData: null
                        spacing: Appearance.spacing.space200
                        MaterialSymbol {
                            Layout.leftMargin: Appearance.spacing.space100
                            text: "link"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(urlRow.modelData ?? "")
                            elide: Text.ElideMiddle
                            color: Appearance.colors.colOnLayer1
                        }
                        RippleButton {
                            Layout.rightMargin: Appearance.spacing.space100
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colRipple: Appearance.colors.colErrorActive
                            onClicked: {
                                const gone = String(urlRow.modelData ?? "");
                                Config.options.calendar.ics.urls = (Config.options.calendar.ics.urls ?? []).filter(u => u !== gone);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "delete"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colError
                            }
                            StyledToolTip { text: Translation.tr("Remove feed") }
                        }
                    }
                }
            }

            GroupedList {
                ConfigTextArea {
                    buttonIcon: "add_link"
                    singleLine: true
                    placeholderText: Translation.tr("Add an ICS link (Google's secret address, a Proton share link, …)")
                    confirmButtonVisible: /^https?:\/\//.test(value.trim())
                    confirmButtonIcon: "add"
                    onConfirmClicked: {
                        const url = value.trim();
                        const next = (Config.options.calendar.ics.urls ?? []).slice();
                        if (next.indexOf(url) === -1) next.push(url);
                        Config.options.calendar.ics.urls = next;
                        value = "";
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Refresh every (min)")
                    value: Config.options.calendar.ics.refreshInterval
                    from: 5
                    to: 720
                    stepSize: 5
                    onValueModified: Config.options.calendar.ics.refreshInterval = newValue
                }
            }
        }
    }
}
