pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.cheatsheet.typing
import qs.services
import "../../common/functions/cheatsheetFit.js" as CheatsheetFit

/**
 * The typing test as a cheatsheet page.
 *
 * The test itself is TypingTestSurface (ported from the p3drovfx fork, where
 * the launcher hosts the same surface; here the cheatsheet is its only host).
 * This file is only the frame: the page's size against the window's budget,
 * the key hint bar under the stage, and the focus and Escape wiring the
 * cheatsheet expects from a page.
 */
Item {
    id: root

    // The room the page may take - Cheatsheet.qml derives both from the
    // screen the window is on. The surface lays itself out in whatever it is
    // given - the test is the one page whose content stretches rather than
    // having a natural size - so its size is a choice, not a fit: a share of
    // the budget, held to a 16:9 stage, so the window scales with the screen
    // without becoming the screen and the stage keeps one shape on every
    // monitor. 0 means the window has not said, which falls back to a fixed
    // stage of the same aspect.
    property real maxContentWidth: 0
    property real maxContentHeight: 0
    // Whether this page is the one on screen. The host says so, because a
    // page cannot see the SwipeView it sits in, and the test wants the focus
    // on its own input sink when it comes up or the first keystroke goes
    // nowhere.
    property bool tabActive: false

    readonly property real budgetShare: 0.85
    readonly property real stageAspect: 16 / 9
    readonly property real fallbackHeight: 640
    readonly property var stageBox: CheatsheetFit.aspectBox(
        root.maxContentWidth, root.maxContentHeight, root.budgetShare, root.stageAspect)
    implicitWidth: root.stageBox.width > 0 ? root.stageBox.width
        : root.fallbackHeight * root.stageAspect
    implicitHeight: root.stageBox.height > 0 ? root.stageBox.height : root.fallbackHeight

    onTabActiveChanged: {
        if (root.tabActive)
            Qt.callLater(surface.focusInput);
    }
    Component.onCompleted: {
        if (root.tabActive)
            Qt.callLater(surface.focusInput);
    }

    // Escape closes an open settings, history or stats page before it reaches
    // the cheatsheet and closes the whole window.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && surface.handleEscape())
            event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        spacing: Appearance.spacing.space50

        TypingTestSurface {
            id: surface
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            visible: surface.statusText.length > 0
                || surface.hints.length > 0 || Object.keys(surface.primaryHint).length > 0

            StyledText {
                Layout.fillWidth: true
                visible: surface.statusText.length > 0
                text: surface.statusText
                elide: Text.ElideRight
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            Item {
                Layout.fillWidth: true
                visible: surface.statusText.length === 0
            }

            KeyHintBar {
                hints: surface.primaryHint.label
                    ? [surface.primaryHint].concat(surface.hints) : surface.hints
                surface: Appearance.colors.colSurfaceContainerHigh
                onSurface: Appearance.colors.colOnSurface
            }
        }
    }
}
