import QtQuick

QtObject {
    property var command
    property var environment
    property bool running: false
    property bool stdinEnabled: false
    property var stdout
    property var stderr

    signal started()
    signal exited(int exitCode, int exitStatus)

    function write(data) {}
}
