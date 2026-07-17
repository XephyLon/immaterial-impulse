import QtQuick

QtObject {
    property var command
    property var environment
    property bool running: false
    property var stdout
    
    signal exited(int exitCode, int exitStatus)
}
