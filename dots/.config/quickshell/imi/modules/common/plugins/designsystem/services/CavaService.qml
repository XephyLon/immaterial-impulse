pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property int refCount: 0
    property int barCount: 32
    property list<int> values: []
}
