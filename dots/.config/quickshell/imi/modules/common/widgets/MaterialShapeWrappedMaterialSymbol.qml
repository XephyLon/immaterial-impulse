import QtQuick
import qs.modules.common
import qs.modules.common.widgets

MaterialShape {
    id: root
    property alias fill: symbol.fill
    property alias text: symbol.text
    property alias iconSize: symbol.iconSize
    property alias font: symbol.font
    property alias colSymbol: symbol.color
    // The designsystem plugin's copy of this widget has always carried
    // this alias and this one had not, so a call site written against
    // that one assigns a property this component does not have. QML
    // reports that only when the file is COMPILED, which for the Phone
    // tab's cards is the first time someone opens the tab.
    property alias animateChange: symbol.animateChange
    property real padding: Appearance.spacing.space100
    property var wrappedShape: MaterialShape.Shape.Clover4Leaf

    color: Appearance.colors.colSecondaryContainer
    colSymbol: Appearance.colors.colOnSecondaryContainer
    shape: root.wrappedShape
    implicitSize: Math.max(symbol.implicitWidth, symbol.implicitHeight) + padding * 2

    MaterialSymbol {
        id: symbol
        anchors.centerIn: parent
        color: root.colSymbol
        fill: root.fill
    }
}