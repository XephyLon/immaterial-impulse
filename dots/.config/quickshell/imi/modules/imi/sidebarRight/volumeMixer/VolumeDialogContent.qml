import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

ColumnLayout {
    id: root
    required property bool isSink
    // The lists below run to the edge of whatever pads this block, and it is a
    // grandchild of that padding rather than a child of it - so the number is
    // handed in rather than read off a parent.
    //
    // NOT `required`, and the default is the answer for every surface that is
    // not a dialog card: the overlay volume mixer builds this inside its own
    // padded Item, where there is no card edge to reach and the question does
    // not arise. Declared required, that call site could not answer it and the
    // component failed to build there - a break the suite never saw, because
    // it constructs this through the dialog and the overlay's own window is
    // what surfaced it.
    property real contentPadding: 0
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property bool hasApps: appPwNodes.length > 0
    spacing: Appearance.spacing.space200

    DialogSectionListView {
        Layout.fillHeight: true
        topMargin: 14

        model: ScriptModel {
            values: root.appPwNodes
        }
        delegate: VolumeMixerEntry {
            anchors {
                left: parent?.left
                right: parent?.right
            }
            required property var modelData
            node: modelData
        }
        PagePlaceholder {
            icon: "widgets"
            title: Translation.tr("No applications")
            shown: !root.hasApps
            shape: MaterialShape.Shape.Cookie7Sided
        }
    }

    StyledComboBox {
        id: deviceSelector
        Layout.fillHeight: false
        Layout.fillWidth: true
        Layout.bottomMargin: Appearance.spacing.space100
        model: root.devices.map(node => Audio.friendlyDeviceName(node))
        currentIndex: root.devices.findIndex(item => {
            if (root.isSink) {
                return item.id === Pipewire.defaultAudioSink?.id
            } else {
                return item.id === Pipewire.defaultAudioSource?.id
            }
        })
        onActivated: (index) => {
            print(index)
            const item = root.devices[index]
            if (root.isSink) {
                Audio.setDefaultSink(item)
            } else {
                Audio.setDefaultSource(item)
            }
        }
    }

    component DialogSectionListView: StyledListView {
        Layout.fillWidth: true
        Layout.topMargin: -Appearance.spacing.space300
        Layout.bottomMargin: -Appearance.spacing.space200
        Layout.leftMargin: -root.contentPadding
        Layout.rightMargin: -root.contentPadding
        topMargin: Appearance.spacing.space150
        bottomMargin: Appearance.spacing.space150
        leftMargin: Appearance.spacing.space250
        rightMargin: Appearance.spacing.space250

        clip: true
        spacing: Appearance.spacing.space50
        animateAppearance: false
    }

    Component {
        id: listElementComp
        ListElement {}
    }
}
