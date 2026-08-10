import QtQuick
import "../services"
import "./shapes/rounded-polygon.js" as RoundedPolygon
import "./shapes/corner-rounding.js" as CornerRounding
import "./visualizer_bands.js" as VisualizerBands

// A Material cookie whose lobes each answer to their own level, so the outline
// ripples per frequency band instead of breathing as one shape.
Item {
    id: root

    property int lobes: 12
    // 0..1, one per lobe, lobe 0 at 3 o'clock and travelling clockwise. With
    // audioReactive set this component owns it, and a binding on it is lost.
    property list<real> levels: []
    property real baseRadius: 0.8
    property real reach: 0.14
    property color color: "#685496"
    property int implicitSize: 100

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    // The rounding the Material cookies are cut with (material-shapes.js).
    readonly property var cornerRounding: new CornerRounding.CornerRounding(0.5)
    property var polygon: null

    function lobeRadii(): var {
        const radii = [];
        for (let i = 0; i < root.lobes; i++) {
            const level = i < root.levels.length ? Math.max(0, Math.min(1, root.levels[i])) : 0;
            radii.push(root.baseRadius + level * root.reach);
        }
        return radii;
    }

    function rebuild() {
        root.polygon = RoundedPolygon.RoundedPolygon.starPerLobe(root.lobes, 1, lobeRadii(), root.cornerRounding);
        canvas.requestPaint();
    }

    onLevelsChanged: rebuild()
    onLobesChanged: rebuild()
    onBaseRadiusChanged: rebuild()
    onReachChanged: rebuild()
    onColorChanged: canvas.requestPaint()

    Component.onCompleted: {
        rebuild();
        holdCava(root.visualizing);
    }

    // --- audio -------------------------------------------------------------

    property bool audioReactive: false
    // CavaService is shared through a refcount, so the bands arrive at whatever
    // bar count everything else on screen is using and are folded here.
    property var bands: CavaService.values
    property real maxBandValue: 1000

    // Signal smoothing, not design tokens: raw cava values jitter at frame rate
    // and would make the outline boil, so a beat reads on the frame it lands
    // and the shape settles back over about a fifth of a second.
    readonly property real attack: 0.55
    readonly property real decay: 0.12
    // The envelope approaches its target geometrically and would never arrive,
    // so its tail is snapped: without this the shape rebuilds forever, and
    // rests a hair off the resting cookie.
    readonly property real settleEpsilon: 0.001

    readonly property bool visualizing: root.audioReactive && root.visible
    property bool settling: false
    property bool cavaHeld: false

    function holdCava(hold) {
        if (hold === root.cavaHeld)
            return;
        CavaService.refCount += hold ? 1 : -1;
        root.cavaHeld = hold;
    }

    function step() {
        // Not visualizing means an empty band list, which rests every lobe: the
        // same path decays the shape back down once playback stops.
        const targets = VisualizerBands.toLobes(root.visualizing ? root.bands : [], root.lobes, root.maxBandValue);
        const next = [];
        let moved = false;
        for (let i = 0; i < root.lobes; i++) {
            const current = i < root.levels.length ? root.levels[i] : 0;
            const level = VisualizerBands.envelope(current, targets[i], root.attack, root.decay);
            const settled = Math.abs(targets[i] - level) <= root.settleEpsilon ? targets[i] : level;
            if (settled !== current)
                moved = true;
            next.push(settled);
        }
        // A settled shape rebuilds nothing, so silence costs a comparison a
        // frame rather than a polygon.
        root.settling = moved;
        if (moved)
            root.levels = next;
    }

    onVisualizingChanged: {
        holdCava(root.visualizing);
        // A shape frozen mid-beat has settled, so the timer is stopped; kick it
        // or the lobes stay where the music left them.
        root.settling = true;
    }

    Component.onDestruction: holdCava(false)

    Timer {
        interval: 16
        repeat: true
        running: root.visible && (root.visualizing || root.settling)
        onTriggered: root.step()
    }

    // Not ShapeCanvas: that builds a Morph and runs a 350ms transition on every
    // polygon change, and a Morph of this shape measures ~1.3ms to construct -
    // a shape rebuilt per frame would spend more time matching features than
    // drawing, and would never reach the shape it was morphing to. The polygon
    // is drawn at a fixed scale rather than normalized() for the same class of
    // reason: normalizing refits every frame, so a lobe pushing out would
    // shrink the other eleven instead of standing out.
    Canvas {
        id: canvas
        anchors.fill: parent

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!root.polygon)
                return;
            const cubics = root.polygon.cubics;
            if (cubics.length === 0)
                return;

            ctx.save();
            ctx.translate(width / 2, height / 2);
            const scale = Math.min(width, height) / 2;
            ctx.scale(scale, scale);
            ctx.beginPath();
            ctx.moveTo(cubics[0].anchor0X, cubics[0].anchor0Y);
            for (const cubic of cubics)
                ctx.bezierCurveTo(cubic.control0X, cubic.control0Y, cubic.control1X, cubic.control1Y, cubic.anchor1X, cubic.anchor1Y);
            ctx.closePath();
            ctx.fillStyle = root.color;
            ctx.fill();
            ctx.restore();
        }
    }
}
