import qs
import qs.services
import qs.modules.imi.sidebarLeft.phone
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: Appearance.spacing.space125
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property bool mediaEnabled: Config.options.sidebar.media.enable
    property bool phoneEnabled: Config.options.sidebar.phone.enable
    property var tabButtonList: [
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...(root.mediaEnabled ? [{"icon": "music_note", "name": Translation.tr("Media")}] : []),
        ...(root.phoneEnabled ? [{"icon": "smartphone", "name": Translation.tr("Phone")}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
    ]
    property int tabCount: swipeView.count

    // The tab bar's entries by untranslated id, index-aligned with
    // tabButtonList and so with the SwipeView's pages - the ONE thing that
    // makes GlobalStates.sidebarLeftTab resolvable. It cannot be derived
    // from tabButtonList, because every `name` in there is a
    // Translation.tr(...) call and resolving a deep link against a label
    // breaks the moment the user changes language (1c674c8f5's defect, in
    // a second place). Keep the two lists edited together, and watch the
    // asymmetry below them: the placeholder page sits BETWEEN Media/Phone
    // and Anime with no tab-bar entry of its own, and closet mode puts an
    // Anime page in the SwipeView with no entry either - so a page list
    // and a tab list of different lengths is the normal state here, and
    // only the entries before the placeholder are index-aligned.
    // tests/test_sidebar_left_tabs.py pins the pair.
    property var tabIdList: [
        ...(root.aiChatEnabled ? ["intelligence"] : []),
        ...(root.translatorEnabled ? ["translator"] : []),
        ...(root.mediaEnabled ? ["media"] : []),
        ...(root.phoneEnabled ? ["phone"] : []),
        ...((root.animeEnabled && !root.animeCloset) ? ["anime"] : [])
    ]

    // A deep link is consumed, not merely read: the right sidebar's phone
    // toggle writes the id and opens the panel, and leaving it set would
    // send the sidebar back to that tab on every later open. Same shape as
    // GlobalStates.settingsPage.
    function showTab(id) {
        const index = root.tabIdList.indexOf(id);
        if (index < 0) return;
        // The tab bar follows: its currentIndex is bound to the view's, and
        // its own change handler writes the same value straight back.
        swipeView.currentIndex = index;
    }

    function consumeTabRequest() {
        if (GlobalStates.sidebarLeftTab === "") return;
        root.showTab(GlobalStates.sidebarLeftTab);
        GlobalStates.sidebarLeftTab = "";
    }

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    // The entrance runs UNDER the slide, ungated - the fork's grammar, read
    // off its re-recorded sidebars: the surface carries the panel already
    // composed and only the last-ranked members visibly land after (see the
    // right sidebar's fuller comment). Keyed to the OPEN flag, which a
    // detach does not flip, so undocking the chat to keep reading never
    // re-runs the entrance.
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                root.consumeTabRequest();
                leftEntrance.park();
                leftEntrance.enter();
            }
        }
        // A toggle pressed while the panel is already open writes the id
        // with no open edge behind it, so the request is honoured on the
        // write as well.
        function onSidebarLeftTabChanged() {
            if (GlobalStates.sidebarLeftOpen)
                root.consumeTabRequest();
        }
    }

    ColumnLayout {
        id: leftColumn
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: verticalTabBar.expanded ? -Appearance.spacing.space25 : 0

        StaggerWave {
            id: leftEntrance
            target: leftColumn
        }
        StaggerEntrance {
            target: leftColumn
            reference: root.width
        }

        VerticalTabBar {
            id: verticalTabBar
            property real appear: 1
            visible: tabButtonList.length > 0
            Layout.fillWidth: true
            tabButtonList: root.tabButtonList
            // One source of truth, one direction each way: the bar DRAWS the
            // view's index and ASKS for a new one. It used to write
            // `swipeView.currentIndex` from its own `onCurrentIndexChanged`
            // while the view bound `currentIndex: tabBar.currentIndex` - an id
            // declared inside VerticalTabBar.qml and so not in scope here, so
            // that binding threw a ReferenceError on every evaluation and the
            // view was really driven by the handler alone.
            currentIndex: swipeView.currentIndex
            onCurrentIndexRequested: index => {
                swipeView.currentIndex = Math.max(0, Math.min(swipeView.count - 1, index));
            }
        }

        Rectangle {
            // Not a wave member: the AI pane's members animate inside this
            // card, and a fading card over fading members is the compound
            // the right sidebar's toggle section already paid for.
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            topLeftRadius: 0
            bottomLeftRadius: Appearance.rounding.normal
            topRightRadius: 0
            bottomRightRadius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: Appearance.spacing.space150

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [
                    ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
                    ...(root.translatorEnabled ? [translator.createObject()] : []),
                    ...(root.mediaEnabled ? [media.createObject()] : []),
                    ...(root.phoneEnabled ? [phone.createObject()] : []),
                    ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []),
                    ...(root.animeEnabled ? [anime.createObject()] : []),
                ]
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: media
            SidebarPlayerControl {}
        }
        Component {
            id: phone
            Phone {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}