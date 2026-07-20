import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    property bool colorize: false
    property color color
    property string source: ""
    property string iconFolder: Qt.resolvedUrl(Quickshell.shellPath("assets/icons"))  // The folder to check first
    width: 30
    height: 30
    
    IconImage {
        id: iconImage
        anchors.fill: parent
        source: {
            // Without this the empty source resolves to the icon folder itself,
            // and IconImage logs a failed open for the directory.
            if (!root.source) return "";
            if (iconFolder) return iconFolder + "/" + root.source;
            return root.source
        }
        implicitSize: root.height
    }

    Loader {
        active: root.colorize
        anchors.fill: iconImage
        sourceComponent: ColorOverlay {
            source: iconImage
            color: root.color
        }
    }
}
