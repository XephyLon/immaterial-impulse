pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common

Scope {
    id: root
    
    Variants {
        model: Quickshell.screens
        
        delegate: AccentPickerOverlay {
            id: picker
            required property var modelData
            screen: picker.modelData
        }
    }
}
