pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.background
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../../common/functions/clockDepth.js" as ClockDepthLogic

/**
 * One screen's worth of the subject selector: a transparent layer surface over
 * the desktop, its chrome, and the cutout it is authoring.
 *
 * TRANSPARENT is the whole design. The wallpaper is already on screen at
 * exactly the size and crop the mask has to line up with, and the desktop
 * widgets are already drawn under it - so a click here lands on the pixels the
 * depth layer will mask, by construction rather than by arithmetic, and the
 * cutout drawn over them is the real occlusion rather than a picture of one.
 * Redrawing either would be a second copy, and a second copy is a second chance
 * to be misaligned in a feature that has already spent an evening chasing a
 * misalignment that turned out not to exist.
 *
 * The one thing this surface cannot see is where the wallpaper's box sits: the
 * background is a different window, its viewport is oversized and offset by the
 * parallax pan, and reconstructing that pan here would be a second derivation
 * of the number ClockDepthCutout exists to have only one of. It is published
 * per screen instead (GlobalStates.clockDepthViewports, written by
 * Background.qml while this mode is armed), and everything geometric follows
 * from it: the cutout is drawn into that box and the click is measured against
 * the rectangle that same cutout publishes.
 */
PanelWindow {
    id: root

    signal cancelled()
    signal accepted()
    signal declined()

    color: "transparent"
    WlrLayershell.namespace: "quickshell:clockDepthSelect"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand, not Exclusive: this surface exists once per output, and an
    // Exclusive grab is session-wide rather than scoped to the screen it was
    // taken on - it would swallow what the user types on any other monitor.
    // Same choice, for the same reason, as the region selector.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Where the wallpaper's whole box sits on THIS screen, published by the
    // background. Null until it arrives, and null again the moment the mode
    // disarms - so nothing here draws against a guessed geometry.
    readonly property var viewport: GlobalStates.clockDepthViewports?.[root.screen.name] ?? null
    readonly property string modelName: ClockDepth.promptedModel
    // The CANDIDATE, not ClockDepth.maskPath: that one is only ever the
    // accepted mask, and the whole point of this surface is judging something
    // before it is accepted.
    readonly property string maskPath: ClockDepth.candidates?.[root.modelName] ?? ""
    readonly property string maskRevision: ClockDepth.revisions?.[root.modelName] ?? ""
    readonly property var points: ClockDepth.points ?? []
    readonly property bool busy: ClockDepth.running !== ""

    // Off by default, exactly as it is in the picker. At full size the veil
    // dims the widgets as well - which is right for reading the mask's edge and
    // wrong for judging whether the cutout occludes the clock, and those are
    // two different questions asked at two different moments.
    property bool inspect: false
    // Gated on the mask having DECODED rather than on a path: the veil is the
    // INVERSE of the mask surface, so a mask that has not loaded is a
    // transparent surface whose inverse blacks out the entire desktop - a
    // failure that reads as the model having claimed nothing.
    readonly property bool inspecting: root.inspect && root.maskPath !== ""
        && cutout.maskStatus === Image.Ready

    WindowBlurRegion {
        targetWindow: root
        regionItem: chromeCard
        regionRadius: Appearance.rounding.normal
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.cancelled()
                event.accepted = true
                return
            }
            // Handled here rather than as a `Shortcut`: a Shortcut is scoped to
            // its window and this surface is one per output, so the same chord
            // would be declared on every screen and Qt would call the match
            // ambiguous. Keys go to whichever surface holds focus, which is the
            // screen the user is picking on.
            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_Z) {
                    if (event.modifiers & Qt.ShiftModifier)
                        ClockDepth.redoPoint()
                    else
                        ClockDepth.undoPoint()
                    event.accepted = true
                } else if (event.key === Qt.Key_Y) {
                    ClockDepth.redoPoint()
                    event.accepted = true
                }
            }
        }

        // Everything registered to the picture lives in here, at the wallpaper
        // box's own geometry, so each child can anchor to it and no child needs
        // its own copy of the offset. The box always covers the screen (the
        // parallax viewport is the screen scaled up), so a veil filling it
        // reaches every pixel a veil filling the screen would.
        Item {
            id: pictureFrame
            visible: root.viewport !== null
            x: root.viewport?.x ?? 0
            y: root.viewport?.y ?? 0
            width: root.viewport?.width ?? root.width
            height: root.viewport?.height ?? root.height

            // INSPECT: everything the model did NOT claim, dimmed. Masked by
            // the inverse of the SAME registered surface the cutout is masked
            // by, so the lit region and the drawn region cannot be a pixel
            // apart.
            Rectangle {
                id: veilSource
                anchors.fill: parent
                color: "black"
                visible: false
            }
            Loader {
                anchors.fill: parent
                active: root.inspecting
                visible: active
                sourceComponent: OpacityMask {
                    source: veilSource
                    maskSource: cutout.maskSurface
                    invert: true
                    opacity: 0.66
                }
            }

            // INSPECT: the silhouette traced. The veil says WHAT was claimed;
            // this says where the boundary runs and how hard it is. Drawn under
            // the cutout so only its outer half shows.
            Loader {
                anchors.fill: parent
                active: root.inspecting
                visible: active
                sourceComponent: Glow {
                    source: cutout.maskSurface
                    // Hardcoded, and this is the one place in the shell that is
                    // right: every Appearance colour is generated FROM this
                    // wallpaper, so a token here is guaranteed to be a colour
                    // the picture already contains.
                    color: "#ff00c8"
                    radius: 8
                    samples: 17
                    spread: 0.45
                    // Without it the blur clamps at the item's edge and a
                    // subject touching the bottom of the frame smears into a
                    // band across it, which reads as a defect in the mask being
                    // judged rather than in the instrument judging it.
                    transparentBorder: true
                }
            }

            // The subject, cut out exactly the way the desktop cuts it out -
            // the same component, on the same box, so this cannot show a
            // registration the desktop does not use. It is the real occlusion:
            // the widgets underneath are the live ones.
            ClockDepthCutout {
                id: cutout
                anchors.fill: parent
                wallpaperSource: root.viewport?.source ?? ""
                maskPath: root.maskPath
                maskRevision: root.maskRevision
            }

            // Where the clicks landed, drawn back onto the picture through the
            // cutout's OWN mask rectangle. Anything else would put the disc
            // somewhere other than where the click was sent, which is the one
            // thing that would make this gesture unteachable.
            Repeater {
                model: root.points.filter(entry => !entry.lasso)

                Item {
                    id: marker
                    required property var modelData
                    readonly property rect frame: cutout.maskRect
                    readonly property bool include: (marker.modelData.label ?? 1) === 1

                    width: 22
                    height: 22
                    x: marker.frame.x + marker.modelData.x * marker.frame.width - width / 2
                    y: marker.frame.y + marker.modelData.y * marker.frame.height - height / 2

                    // Black and white, and hardcoded, for the same reason the
                    // contour is: a disc against its own outline reads on any
                    // image, and every generated token is a colour this picture
                    // is guaranteed to contain.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: marker.include ? "#ffffff" : "#101010"
                        border.width: 2
                        border.color: marker.include ? "#101010" : "#ffffff"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: marker.include ? "add" : "remove"
                            iconSize: 14
                            color: marker.include ? "#101010" : "#ffffff"
                        }
                    }
                }
            }
        }

        // The loops, live and committed - drawn in screen space through the
        // cutout's own mask rectangle, exactly as the discs are placed, so a
        // loop renders where it was drawn. Committed loops are dashed (white
        // over black for an include, black over white for a cut, the same
        // any-image palette as the discs); the trace being drawn is solid.
        // A Canvas takes no input, so the gesture area behind it still sees
        // every event.
        Canvas {
            id: lassoCanvas
            anchors.fill: parent
            visible: root.viewport !== null
            readonly property rect frame: cutout.maskRect
            onFrameChanged: requestPaint()
            Connections {
                target: ClockDepth
                function onPointsChanged() { lassoCanvas.requestPaint() }
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const frameRect = lassoCanvas.frame;
                const stroke = (include, dashed) => {
                    ctx.setLineDash(dashed ? [6, 4] : []);
                    ctx.lineWidth = 4;
                    ctx.strokeStyle = include ? "#101010" : "#ffffff";
                    ctx.stroke();
                    ctx.lineWidth = 2;
                    ctx.strokeStyle = include ? "#ffffff" : "#101010";
                    ctx.stroke();
                };
                root.points.forEach(entry => {
                    if (!entry.lasso)
                        return;
                    ctx.beginPath();
                    entry.lasso.forEach((v, i) => {
                        const x = pictureFrame.x + frameRect.x + v[0] * frameRect.width;
                        const y = pictureFrame.y + frameRect.y + v[1] * frameRect.height;
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    });
                    ctx.closePath();
                    stroke((entry.label ?? 1) === 1, true);
                });
                if (pointArea.lassoTrace.length > 1) {
                    ctx.beginPath();
                    pointArea.lassoTrace.forEach((sample, i) => {
                        if (i === 0) ctx.moveTo(sample.x, sample.y); else ctx.lineTo(sample.x, sample.y);
                    });
                    stroke(pointArea.pressButton === Qt.LeftButton, false);
                }
            }
        }

        // The gesture. Screen-sized rather than box-sized because the box
        // overflows the screen and a click can only ever arrive inside it
        // anyway; the conversion takes the box as its origin.
        MouseArea {
            id: pointArea
            anchors.fill: parent
            // Gated on the wallpaper having DECODED, not merely on a path: an
            // Image's implicit size reads 0 until its source resolves, and
            // `coverRect` answers a zero-sized source with the box itself - so
            // a click arriving in that window would be measured against a frame
            // the picture does not occupy and sent to the producer as a point
            // somewhere else entirely.
            enabled: root.viewport !== null && cutout.wallpaperStatus === Image.Ready
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.CrossCursor

            // A drag is a lasso, a click is a point - no mode to switch,
            // because the two gestures cannot be confused: a lasso only
            // starts once the press has travelled, and a completed lasso
            // swallows the click its release would otherwise plant.
            property var lassoTrace: []
            property bool lassoing: false
            property int pressButton: Qt.LeftButton
            property real pressX: 0
            property real pressY: 0

            onPressed: mouse => {
                pointArea.pressButton = mouse.button;
                pointArea.pressX = mouse.x;
                pointArea.pressY = mouse.y;
                pointArea.lassoing = false;
                pointArea.lassoTrace = [];
            }
            onPositionChanged: mouse => {
                if (!pointArea.pressed)
                    return;
                if (!pointArea.lassoing) {
                    // The same slack a click's own jitter gets: a press that
                    // has moved less than this is still a click.
                    const dx = mouse.x - pointArea.pressX;
                    const dy = mouse.y - pointArea.pressY;
                    if (dx * dx + dy * dy < 144)
                        return;
                    pointArea.lassoing = true;
                    pointArea.lassoTrace = [{ x: pointArea.pressX, y: pointArea.pressY }];
                }
                const trace = pointArea.lassoTrace;
                const last = trace[trace.length - 1];
                const gx = mouse.x - last.x;
                const gy = mouse.y - last.y;
                if (gx * gx + gy * gy < 16)
                    return;
                pointArea.lassoTrace = trace.concat([{ x: mouse.x, y: mouse.y }]);
                lassoCanvas.requestPaint();
            }
            onReleased: {
                if (!pointArea.lassoing)
                    return;
                const box = Qt.rect(pictureFrame.x, pictureFrame.y,
                    pictureFrame.width, pictureFrame.height);
                const vertices = [];
                pointArea.lassoTrace.forEach(sample => {
                    const point = ClockDepthLogic.promptFromScreen(
                        box, cutout.maskRect, sample.x, sample.y);
                    if (point)
                        vertices.push([point.x, point.y]);
                });
                pointArea.lassoTrace = [];
                lassoCanvas.requestPaint();
                if (vertices.length >= 3)
                    ClockDepth.addLasso(vertices, pointArea.pressButton === Qt.LeftButton);
            }
            onClicked: mouse => {
                if (pointArea.lassoing) {
                    // The release that finished a lasso, not a click.
                    pointArea.lassoing = false;
                    return;
                }
                const point = ClockDepthLogic.promptFromScreen(
                    Qt.rect(pictureFrame.x, pictureFrame.y,
                        pictureFrame.width, pictureFrame.height),
                    cutout.maskRect, mouse.x, mouse.y)
                if (!point)
                    return
                ClockDepth.addPoint(point.x, point.y, mouse.button === Qt.LeftButton)
            }
        }

        Rectangle {
            id: chromeCard
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Appearance.spacing.space300
            implicitWidth: chromeRow.implicitWidth + Appearance.spacing.space300
            implicitHeight: chromeRow.implicitHeight + Appearance.spacing.space200
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0

            // The chrome is a set of controls, so it keeps its own clicks
            // instead of letting them fall through to the point gesture behind
            // it - pressing "Use this" must not also plant a point under it.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }

            RowLayout {
                id: chromeRow
                anchors.centerIn: parent
                spacing: Appearance.spacing.space150

                MaterialSymbol {
                    text: "layers"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer0
                }

                ColumnLayout {
                    spacing: 0
                    // Bounded, and both lines elide: a wallpaper's file name is
                    // arbitrary and the instruction is a sentence, so without a
                    // ceiling the toolbar grows past the screen it is centred
                    // on and its buttons leave with it.
                    Layout.maximumWidth: 420

                    StyledText {
                        // Which picture is being cut, said outright. The mode is
                        // entered from a surface that has just closed, and the
                        // clicks are stored against this file's cache key.
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: Translation.tr("Depth for %1")
                            .arg(ClockDepth.wallpaperPath.split("/").pop())
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        // The whole instruction set, on the surface the gesture
                        // is aimed at, because there is nowhere else a person
                        // would look for it.
                        text: {
                            if (ClockDepth.lastError !== "")
                                return ClockDepth.lastError
                            if (root.busy)
                                return Translation.tr("Cutting…")
                            if (root.points.length === 0)
                                return Translation.tr("Left-click the thing that should stand in front of your widgets.")
                            if (root.maskPath === "")
                                return Translation.tr("Nothing there — click on the subject itself.")
                            return Translation.tr("Right-click anything it grabbed that it should not have. Drag a loop to add or cut a region by hand.")
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ClockDepth.lastError !== ""
                            ? Appearance.m3colors.m3error
                            : Appearance.colors.colSubtext
                    }
                }

                // Gated on the history rather than on the points, so "Start
                // over" stays undoable - after it there are no points left, and
                // a button reading `points.length` would disable itself exactly
                // when the user most wants it back.
                DialogButton {
                    id: undoButton
                    enabled: !root.busy && ClockDepth.pointHistory.length > 0
                    buttonText: Translation.tr("Undo")
                    onClicked: ClockDepth.undoPoint()
                }
                DialogButton {
                    id: redoButton
                    enabled: !root.busy && ClockDepth.pointFuture.length > 0
                    buttonText: Translation.tr("Redo")
                    onClicked: ClockDepth.redoPoint()
                }
                DialogButton {
                    id: clearButton
                    enabled: !root.busy && root.points.length > 0
                    buttonText: Translation.tr("Start over")
                    onClicked: ClockDepth.clearPoints()
                }
                DialogButton {
                    id: inspectButton
                    toggled: root.inspect
                    // RippleButton fills a toggled button with colPrimary and
                    // DialogButton writes its label in colPrimary, so a toggle
                    // left to the defaults reads its own text off its own
                    // background. Set through colEnabled rather than colText,
                    // which is the alias that would take the disabled dim with
                    // it.
                    colEnabled: root.inspect
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colPrimary
                    buttonText: Translation.tr("Inspect")
                    onClicked: root.inspect = !root.inspect
                }
                DialogButton {
                    id: declineButton
                    buttonText: Translation.tr("No depth for this wallpaper")
                    onClicked: root.declined()
                }
                DialogButton {
                    id: acceptButton
                    enabled: !root.busy && root.maskPath !== ""
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colText: Appearance.colors.colOnPrimary
                    buttonText: Translation.tr("Use this")
                    onClicked: root.accepted()
                }
                DialogButton {
                    id: cancelButton
                    buttonText: Translation.tr("Cancel (Esc)")
                    onClicked: root.cancelled()
                }
            }
        }
    }
}
