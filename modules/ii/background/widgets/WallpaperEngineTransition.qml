import QtQuick

// One transition implementation shared by the lock overlay and the live-
// wallpaper switch. Both jobs are identical: reveal a "to" texture over a
// "from" texture with the shader chosen in Settings > Desktop > Wallpaper >
// Transition (peel is only one of several).
//
// Both sides are fed monitor-shaped cached stills (with the project preview only
// as a fallback for a wallpaper whose still is not cached yet). A still already
// has the monitor's aspect baked in, so the shader samples it 1:1 and nothing
// stretches - the fix for the incoming wallpaper appearing stretched was to stop
// feeding the raw, often-square Workshop preview into the shader.
Item {
    id: transition

    // Primary source is the sharp still; fallback is the smaller preview used
    // when a still has not been cached yet. A missing/empty primary degrades to
    // the fallback instead of showing blank.
    property string fromSource: ""
    property string fromFallback: ""
    property string toSource: ""
    property string toFallback: ""

    property real progress: 0
    // Any shader under background/shaders. The caller passes the configured one.
    property string shader: "transition"
    // Show the transitioned result. Callers hold it back until their first frame
    // is ready (the switch) or gate it on the animation being enabled (the lock).
    property bool contentVisible: true
    // Decode synchronously when the caller is about to replace the runtime and
    // cannot afford an async decode flashing through a transparent layer.
    property bool preload: false

    // Emitted whenever the "to" image finishes loading, so a caller can start
    // its animation only once there is something shaped to reveal.
    signal toReady()
    readonly property int toStatus: toView.status

    function setSources(from, fromFb, to, toFb) {
        transition.fromFallback = fromFb
        transition.toFallback = toFb
        fromView.usedFallback = false
        toView.usedFallback = false
        transition.fromSource = from
        transition.toSource = to
    }

    Image {
        id: fromView
        anchors.fill: parent
        source: transition.fromSource
        property bool usedFallback: false
        fillMode: Image.PreserveAspectCrop
        asynchronous: !transition.preload
        cache: false
        layer.enabled: true
        visible: false
        onStatusChanged: {
            if (status === Image.Error && transition.fromFallback && !usedFallback) {
                usedFallback = true
                source = transition.fromFallback
            }
        }
    }

    Image {
        id: toView
        anchors.fill: parent
        source: transition.toSource
        property bool usedFallback: false
        fillMode: Image.PreserveAspectCrop
        asynchronous: !transition.preload
        cache: false
        layer.enabled: true
        visible: false
        onStatusChanged: {
            if (status === Image.Error && transition.toFallback && !usedFallback) {
                usedFallback = true
                source = transition.toFallback
                return
            }
            if (status === Image.Ready)
                transition.toReady()
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: transition.contentVisible
        property var fromImage: fromView
        property var toImage: toView
        property real progress: transition.progress
        property real aspectX: width / height
        property real aspectY: 1.0
        property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
        property vector2d origin: Qt.vector2d(0.5, 0.5)
        fragmentShader: Qt.resolvedUrl(`../shaders/${transition.shader}.frag.qsb`)
    }
}
