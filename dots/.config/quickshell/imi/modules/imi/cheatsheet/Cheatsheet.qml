import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Hyprland
import "../../common/functions/cheatsheetFit.js" as CheatsheetFit

Scope { // Scope
    id: root
    // The tab bar and the SwipeView are indexed in lockstep, and a tab that
    // appears in one but not the other silently shows the wrong page - so
    // both are drawn from ONE list of pages, and every optional page is an
    // entry in it rather than a Loader parked in the view: two optional pages
    // as parked Loaders can never agree with a tab list that skips one of
    // them. The Components tab is developer-mode only, the typing test has a
    // switch of its own, plus the clamp below for the index that was
    // persisted while a tab existed.
    readonly property bool showComponents: Config.options?.developer?.enable ?? false
    readonly property bool showTypingTest: Config.options?.cheatsheet?.enableTypingTest ?? true
    readonly property var pages: {
        const list = [
            { "icon": "keyboard", "name": Translation.tr("Keybinds"), "component": keybindsPage },
            { "icon": "experiment", "name": Translation.tr("Elements"), "component": elementsPage },
        ];
        if (root.showTypingTest)
            list.push({ "icon": "speed", "name": Translation.tr("Typing test"), "component": typingTestPage });
        if (root.showComponents)
            list.push({ "icon": "widgets", "name": Translation.tr("Components"), "component": componentsPage });
        return list;
    }
    readonly property var tabButtonList: root.pages.map(page => ({ "icon": page.icon, "name": page.name }))

    Loader {
        id: cheatsheetLoader
        active: false

        // A real toplevel, like Settings, not an overlay layer. A layer-shell
        // surface takes keyboard input only with a keyboardFocus mode the
        // Hyprland focus grab could not coexist with, so the sheet had none -
        // and the Components workbench is a page you TYPE into: a filter, a
        // text knob, a number. As a window it is focused, moved and closed
        // by the compositor like any other, and its text fields just work.
        sourceComponent: FloatingWindow { // Window
            id: cheatsheetRoot
            visible: cheatsheetLoader.active
            title: Translation.tr("Cheatsheet")

            // The binding currently open in the keybind editor overlay, null
            // when the overlay is closed.
            property var editingBinding: null

            // The part of the screen a floating window may take, from the
            // monitor's own reserved area (the bar and the dock, as hyprctl
            // reports them), and what that leaves a page once the window's
            // chrome has taken its share. The window below is fixed-size and
            // as tall as its tallest page, so the pages have to fit the screen
            // by reading these: the Elements page was ~800px of fixed tiles on
            // any screen, which on a 1080p laptop at 1.25x sat under the bar
            // and the dock, and at 1.5x ran off both screen edges. Before
            // HyprlandData has answered the reserve reads as nothing and the
            // budget is the whole screen less the gaps, which is the same
            // window as before on any screen that never clipped.
            readonly property var monitorData: HyprlandData.monitors.find(m => m.name === cheatsheetRoot.screen?.name) ?? null
            readonly property real usableWidth: CheatsheetFit.usableWidth(
                cheatsheetRoot.screen?.width ?? 1920, cheatsheetRoot.monitorData?.reserved,
                Appearance.sizes.hyprlandGapsOut)
            readonly property real usableHeight: CheatsheetFit.usableHeight(
                cheatsheetRoot.screen?.height ?? 1080, cheatsheetRoot.monitorData?.reserved,
                Appearance.sizes.hyprlandGapsOut)
            readonly property real pageWidthBudget: CheatsheetFit.pageBudget(
                cheatsheetRoot.usableWidth,
                cheatsheetBackground.padding * 2 + Appearance.spacing.space250 * 2)
            readonly property real pageHeightBudget: CheatsheetFit.pageBudget(
                cheatsheetRoot.usableHeight,
                cheatsheetBackground.padding * 2 + cheatsheetToolbar.implicitHeight
                    + Appearance.spacing.space50 + Appearance.spacing.space125)

            function hide() {
                cheatsheetLoader.active = false;
            }

            // Constant on purpose - see Settings.qml: a clear colour that once
            // reaches alpha 255 costs the surface its compositor blur for the
            // session. The backdrop below carries the colour.
            color: "transparent"

            // Sized to the page, and fixed: equal minimum and maximum size
            // hints are what make Hyprland float and centre a toplevel on its
            // own (AGENT.md), with no rule matching on a title. The size
            // follows the tab, since the keybind table and the workbench are
            // nothing like each other.
            implicitWidth: cheatsheetBackground.implicitWidth
            implicitHeight: cheatsheetBackground.implicitHeight
            minimumSize.width: cheatsheetBackground.implicitWidth
            minimumSize.height: cheatsheetBackground.implicitHeight
            maximumSize.width: cheatsheetBackground.implicitWidth
            maximumSize.height: cheatsheetBackground.implicitHeight

            // Closing from the compositor (a kill, a titlebar it may grow)
            // has to feed back into the loader the IPC and shortcuts drive.
            onVisibleChanged: {
                if (!visible && cheatsheetLoader.active)
                    cheatsheetLoader.active = false;
            }

            Rectangle {
                id: cheatsheetBackground
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                // The window's corners are the compositor's; the border was
                // the card's edge against the wallpaper and there is no
                // wallpaper behind a window's own rectangle.
                radius: 0
                property real padding: Appearance.spacing.space250
                implicitWidth: cheatsheetColumnLayout.implicitWidth + padding * 2
                implicitHeight: cheatsheetColumnLayout.implicitHeight + padding * 2

                // Keyboard input lands here and bubbles up: a text field the
                // user clicks takes focus, and an Escape it does not consume
                // reaches the handler below.
                focus: true

                Keys.onPressed: event => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        // Peel the editor overlay first; only a second Esc
                        // closes the cheatsheet itself.
                        if (cheatsheetRoot.editingBinding !== null) {
                            cheatsheetRoot.editingBinding = null;
                            event.accepted = true;
                            return;
                        }
                        cheatsheetRoot.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_PageDown) {
                            tabBar.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            tabBar.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                            event.accepted = true;
                        }
                    }
                }

                RippleButton { // Close button
                    id: closeButton
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 20
                        rightMargin: 20
                    }

                    onClicked: {
                        cheatsheetRoot.hide();
                    }

                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.title
                        text: "close"
                    }
                }

                Component {
                    id: keybindsPage
                    CheatsheetKeybinds {
                        // The room the card may use before it starts growing
                        // past the screen - what decides the column count.
                        // Columns trade height for width, so a screen with
                        // height to spare but not width was asked for more
                        // columns than fit and the outer ones ran off both
                        // edges; both budgets come from the window, which
                        // reads the screen.
                        maxContentHeight: cheatsheetRoot.pageHeightBudget
                        maxContentWidth: cheatsheetRoot.pageWidthBudget
                        onEditRequested: bindingData => {
                            cheatsheetRoot.editingBinding = bindingData;
                        }
                    }
                }
                Component {
                    id: elementsPage
                    CheatsheetPeriodicTable {
                        maxContentHeight: cheatsheetRoot.pageHeightBudget
                        maxContentWidth: cheatsheetRoot.pageWidthBudget
                    }
                }
                Component {
                    id: typingTestPage
                    CheatsheetTypingTest {
                        maxContentHeight: cheatsheetRoot.pageHeightBudget
                        maxContentWidth: cheatsheetRoot.pageWidthBudget
                        // The loader the SwipeView holds is this page's parent.
                        tabActive: cheatsheetRoot.visible && (parent?.current ?? false)
                    }
                }
                // The gallery builds every shared widget in the library, and
                // doing that behind a tab nobody opened would cost the
                // cheatsheet its open time for a surface that is off by
                // default - which is why it is a page in the list only while
                // developer mode is on, and built only then.
                Component {
                    id: componentsPage
                    CheatsheetComponents {}
                }

                ColumnLayout { // Real content
                    id: cheatsheetColumnLayout
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space125

                    Toolbar {
                        id: cheatsheetToolbar
                        Layout.alignment: Qt.AlignHCenter
                        enableShadow: false
                        ToolbarTabBar {
                            id: tabBar
                            tabButtonList: root.tabButtonList

                            Synchronizer on currentIndex {
                                property alias source: swipeView.currentIndex
                            }
                        }
                    }

                    SwipeView { // Content pages
                        id: swipeView
                        Layout.topMargin: Appearance.spacing.space50
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Appearance.spacing.space125
                        // Clamped: the Components tab is the last one and it
                        // can go away under a persisted index that named it,
                        // which leaves a SwipeView pointing past its own end -
                        // an empty page and a tab bar highlighting nothing.
                        currentIndex: Math.min(Persistent.states.cheatsheet.tabIndex,
                                               root.pages.length - 1)
                        onCurrentIndexChanged: {
                            Persistent.states.cheatsheet.tabIndex = currentIndex;
                        }

                        implicitWidth: Math.max.apply(null, contentChildren.map(child => child.implicitWidth || 0))
                        implicitHeight: Math.max.apply(null, contentChildren.map(child => child.implicitHeight || 0))

                        clip: true
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: swipeView.width
                                height: swipeView.height
                                radius: Appearance.rounding.small
                            }
                        }

                        Repeater {
                            model: root.pages
                            delegate: Loader {
                                id: pageLoader
                                required property var modelData
                                // What a page reads to know it is the one on
                                // screen; the SwipeView attaches it to its
                                // items, which are these loaders.
                                readonly property bool current: pageLoader.SwipeView.isCurrentItem
                                sourceComponent: modelData.component
                            }
                        }
                    }
                }

                Rectangle { // Keybind editor overlay
                    id: keybindEditorScrim
                    anchors.fill: parent
                    radius: cheatsheetBackground.radius
                    color: Appearance.colors.colScrim
                    visible: cheatsheetRoot.editingBinding !== null
                    z: 10

                    MouseArea { // Click outside the card to dismiss
                        anchors.fill: parent
                        onClicked: cheatsheetRoot.editingBinding = null
                    }

                    Rectangle {
                        id: keybindEditorCard
                        anchors.centerIn: parent
                        property real padding: Appearance.spacing.space300
                        width: Math.min(560, keybindEditorScrim.width - Appearance.spacing.space800)
                        height: keybindEditorContent.implicitHeight + padding * 2
                        // colLayer1 carries the user's global transparency, which
                        // is right for a panel resting on the shell background and
                        // wrong for a modal resting on a dense keybind table: the
                        // rows underneath read straight through the dialog. The
                        // *Base* colour is the same surface, opaque.
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        radius: Appearance.rounding.normal

                        MouseArea { // Swallow clicks inside the card
                            anchors.fill: parent
                        }

                        KeybindEditor {
                            id: keybindEditorContent
                            overrides: HyprlandKeybindOverrides
                            submap: HyprlandSubmap
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: keybindEditorCard.padding
                            }
                            bindingData: cheatsheetRoot.editingBinding
                            onDone: cheatsheetRoot.editingBinding = null
                        }
                    }

                    onVisibleChanged: {
                        if (visible)
                            keybindEditorContent.focusCapture();
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            cheatsheetLoader.active = !cheatsheetLoader.active;
        }

        function close(): void {
            cheatsheetLoader.active = false;
        }

        function open(): void {
            cheatsheetLoader.active = true;
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"

        onPressed: {
            cheatsheetLoader.active = !cheatsheetLoader.active;
        }
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"

        onPressed: {
            cheatsheetLoader.active = true;
        }
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"

        onPressed: {
            cheatsheetLoader.active = false;
        }
    }
}
