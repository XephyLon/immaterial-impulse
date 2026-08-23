import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.overlay
import qs.modules.imi.sidebarRight.volumeMixer

StyledOverlayWidget {
    id: root
    minimumWidth: 300
    minimumHeight: 380

    contentItem: OverlayBackground {
        radius: root.contentRadius
        property real padding: Appearance.spacing.space100

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: parent.padding
            }
            spacing: Appearance.spacing.space100

            SecondaryTabBar {
                id: tabBar

                currentIndex: Persistent.states.overlay.volumeMixer.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.volumeMixer.tabIndex = tabBar.currentIndex;
                }

                SecondaryTabButton {
                    buttonIcon: "media_output"
                    buttonText: Translation.tr("Output")
                }
                SecondaryTabButton {
                    buttonIcon: "mic"
                    buttonText: Translation.tr("Input")
                }
            }
            SwipeView {
                id: swipeView
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: Persistent.states.overlay.volumeMixer.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.volumeMixer.tabIndex = swipeView.currentIndex;
                }
                clip: true

                PaddedVolumeDialogContent { 
                    isSink: true 
                }
                PaddedVolumeDialogContent { 
                    isSink: false 
                }
            }
        }
    }

    component PaddedVolumeDialogContent: Item {
        id: paddedVolumeDialogContent
        property alias isSink: volDialogContent.isSink
        property real padding: Appearance.spacing.space150
        implicitWidth: volDialogContent.implicitWidth + padding * 2
        implicitHeight: volDialogContent.implicitHeight + padding * 2

        VolumeDialogContent {
            id: volDialogContent
            // The lists cancel the padding that actually wraps them, which
            // here is this Item's own. It used to cancel the dialog card's
            // corner radius in both places, so in this one it overshot its
            // container by 11px.
            contentPadding: paddedVolumeDialogContent.padding
            anchors {
                fill: parent
                margins: paddedVolumeDialogContent.padding
            }
        }
    }
}
