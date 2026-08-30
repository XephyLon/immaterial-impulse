import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common

// Measures the ScreencopyView -> average-colour path for the RGB ambient
// loop: correctness (a known colour fills a corner window; the sample must
// read it back), cost (wall time per sample), and whether a hidden view
// still captures.
ShellRoot {
    id: shellRoot

    PanelWindow {
        id: win
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:rgbsampler"
        anchors { left: true; bottom: true }
        mask: Region {}

        // The view under test. Invisible on purpose: the service will not
        // want to draw the screen inside a window, only sample it.
        ScreencopyView {
            id: copyView
            visible: false
            width: 64
            height: 36
            live: false
            paintCursor: false
            captureSource: Quickshell.screens[0]
        }

        Canvas {
            id: pixel
            // A Canvas that is not visible never paints; opacity keeps it
            // out of sight while leaving it in the render loop.
            opacity: 0.004
            width: 8
            height: 8
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            property var grabResult: null
            property string lastColor: "none"
            property real lastMs: -1
            property var pending: null
            property string status: "idle"
            onImageLoaded: { pixel.status = "imageLoaded"; pixel.requestPaint(); }
            onPaint: {
                if (bridge.status !== Image.Ready) return;
                pixel.status = "painting";
                const ctx = pixel.getContext("2d");
                ctx.clearRect(0, 0, 8, 8);
                ctx.drawImage(bridge, 0, 0, 8, 8);
                const data = ctx.getImageData(0, 0, 8, 8).data;
                let r = 0, g = 0, b = 0, n = data.length / 4;
                for (let i = 0; i < data.length; i += 4) {
                    r += data[i]; g += data[i + 1]; b += data[i + 2];
                }
                const hex = v => Math.round(v / n).toString(16).padStart(2, "0");
                pixel.lastColor = hex(r) + hex(g) + hex(b);
                if (pixel.pending) {
                    pixel.lastMs = Date.now() - pixel.pending;
                    pixel.pending = null;
                }
                pixel.status = "painted";
            }
        }

        Image {
            id: bridge
            opacity: 0.004
            width: 8
            height: 8
            cache: false
            property real grabbedAt: -1
            onStatusChanged: {
                if (status === Image.Ready) {
                    pixel.status = "bridge ready";
                    pixel.requestPaint();
                }
            }
        }

        ColorQuantizer {
            id: quant
            depth: 0
            rescaleSize: 8
            property string result: "none"
            property real ms: -1
            property var started: null
            onColorsChanged: {
                if (colors.length > 0) {
                    quant.result = colors[0].toString();
                    if (quant.started) { quant.ms = Date.now() - quant.started; quant.started = null; }
                }
            }
        }

        function sample() {
            pixel.pending = Date.now();
            copyView.captureFrame();
            // captureFrame is async; grab once the frame lands. hasContent
            // may already be true from a previous frame, so grab next tick.
            grabTimer.restart();
        }
        Timer {
            id: grabTimer
            interval: 16
            onTriggered: {
                const started = copyView.grabToImage(result => {
                    pixel.status = "grabbed " + result.url;
                    pixel.grabResult = result;
                    bridge.grabbedAt = Date.now();
                    bridge.source = "";
                    bridge.source = result.url;
                    // The file route: an 8x8 png to tmpfs, then the
                    // quantizer the grim path already uses.
                    const path = "/run/user/1000/imi-ambient.png";
                    if (result.saveToFile(path)) {
                        quant.started = Date.now();
                        quant.source = "";
                        quant.source = "file://" + path;
                    } else {
                        pixel.status = "saveToFile failed";
                    }
                }, Qt.size(8, 8));
                if (!started) pixel.status = "grabToImage refused";
            }
        }
        Timer {
            id: rateTimer
            interval: 200
            repeat: true
            running: false
            onTriggered: win.sample()
        }

        IpcHandler {
            target: "probe"
            function state(): string {
                return `status=${pixel.status} hasContent=${copyView.hasContent} sourceSize=${copyView.sourceSize.width}x${copyView.sourceSize.height} color=${pixel.lastColor} grabToPaintMs=${pixel.lastMs} quant=${quant.result} quantMs=${quant.ms}`;
            }
            function sample(): string { win.sample(); return "ok"; }
            function rate(on: string): string { rateTimer.running = on === "on"; return `rate ${on}`; }
            function winvis(on: string): string { win.visible = on === "on"; return `vis ${on}`; }
            function live(on: string): string { copyView.live = on === "on"; return `live ${on}`; }
        }
    }
}
