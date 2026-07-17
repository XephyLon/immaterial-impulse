pragma Singleton
import QtQuick

QtObject {
    function shellPath(relative) {
        return "/mock/quickshell/path/" + relative;
    }
    
    function execDetached(command) {
        console.log("Mock execDetached:", JSON.stringify(command));
    }
}
