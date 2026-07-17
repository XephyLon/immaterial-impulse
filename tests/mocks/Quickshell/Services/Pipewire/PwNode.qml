import QtQuick

QtObject {
    property string description: ""
    property string nickname: ""
    property string name: ""
    property var properties: ({})
    property bool isSink: false
    property bool isStream: false
    property QtObject audio: QtObject {
        property real volume: 0.5
        property bool muted: false
    }
}
