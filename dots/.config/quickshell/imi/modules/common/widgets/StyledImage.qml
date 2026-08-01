import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Image {
    id: root
    asynchronous: true

    // `retainWhileLoading` is Qt 6.8+ (revision 1544 in QtQuick's qmltypes).
    // Assigning it declaratively makes this file fail to compile on anything
    // older, and a QML compile failure propagates: every file that
    // instantiates StyledImage fails with it. That is how a user on an older
    // Qt lost the entire Quick settings page - the only settings page that
    // reaches this component - with nothing in the log but a `WARN scene`.
    //
    // Set it imperatively behind an existence check instead. On 6.8+ the
    // behaviour is identical; below it the property is simply skipped and the
    // image loses only the retain-previous-frame nicety.
    Component.onCompleted: {
        if (typeof root.retainWhileLoading !== "undefined")
            root.retainWhileLoading = true;
    }

    visible: opacity > 0
    opacity: (status === Image.Ready) ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    property list<string> fallbacks: []
    property int currentFallbackIndex: 0

    onStatusChanged: {
        if (status === Image.Error && currentFallbackIndex < fallbacks.length) {
            source = fallbacks[currentFallbackIndex];
            currentFallbackIndex += 1;
        }
    }
}
