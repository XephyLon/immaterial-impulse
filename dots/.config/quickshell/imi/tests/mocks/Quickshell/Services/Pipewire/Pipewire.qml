pragma Singleton
import QtQuick

QtObject {
    property var defaultAudioSink: null
    property var defaultAudioSource: null
    property var preferredDefaultAudioSink: null
    property var preferredDefaultAudioSource: null
    property var nodes: QtObject {
        property var values: []
    }
}
