pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.cheatsheet.typing
import qs.services

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
    // given, so the page asks for a comfortable stage and never more than
    // the budget; 0 means the window has not said, which is the stage alone.
    property real maxContentWidth: 0
    property real maxContentHeight: 0
    // Whether this page is the one on screen. The host says so, because a
    // page cannot see the SwipeView it sits in, and the test wants the focus
    // on its own input sink when it comes up or the first keystroke goes
    // nowhere.
    property bool tabActive: false

    readonly property real preferredWidth: 1100
    readonly property real preferredHeight: 640
    implicitWidth: root.maxContentWidth > 0
        ? Math.min(root.preferredWidth, root.maxContentWidth) : root.preferredWidth
    implicitHeight: root.maxContentHeight > 0
        ? Math.min(root.preferredHeight, root.maxContentHeight) : root.preferredHeight

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
