import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * One catalogue entry, built for real and measured.
 *
 * Every surface in the Components workbench needs the same three things from a
 * widget - build it, say so when it cannot be built, and read what it ended up
 * drawing - so they come from here rather than from three copies. The audit
 * table builds fifty of these with `showLabel: false` and reads only the
 * numbers; the detail page builds one and puts knobs on it.
 *
 * The build is a RUNTIME `Qt.createComponent`, which is what lets a type that
 * needs its surroundings fail as a line of text instead of as a compile error
 * that takes the cheatsheet down with it.
 */
Item {
    id: stage

    // { type, props, glyph } from the catalogue.
    required property var entry
    // Applied over `entry.props` - the detail page's knobs write here, so the
    // control is rebuilt from one merged set rather than poked afterwards.
    property var overrides: ({})

    // A tile is a PICTURE of a control, and every one of these is the real
    // wired thing: pressing the gallery's PowerButton opened the power menu,
    // and its LeftSidebarButton toggled the sidebar. A reference surface that
    // can log you out is not a reference surface.
    //
    // So nothing real reaches the control. The shield below eats every button
    // and every wheel event, and the press and hover VISUALS are driven
    // straight into `interactionMotion` instead - which is the same scalar the
    // control's own pointer state would have written, so the morph, the lift
    // and the ripple's state layer are exactly what they would be. Writing
    // those two properties replaces their bindings to the control's own
    // `hovered`/`down`, which is the point: this instance's pointer state is
    // the gallery's to say, and it has no other job.
    property bool inert: true

    // Some widgets are far bigger than a tile - the light/dark preference card
    // is 210px wide and 120 tall. Left alone they paint straight over the tiles
    // beside and below them, which is what the gallery did: two widgets
    // covering four of their neighbours. Scaled to fit and clipped, with the
    // factor shown, rather than cropped to a corner of themselves.
    readonly property real fitScale: {
        const control = builder.control;
        if (!control || width <= 0 || height <= 0)
            return 1;
        // The control's own width when it declares no implicit one: a row that
        // fills its parent reports 0 implicitly and 400px actually, and scaling
        // by the implicit number leaves it overflowing at full size.
        const own = Math.max(control.implicitWidth, control.width);
        const high = Math.max(control.implicitHeight, control.height);
        const wide = own > 0 ? width / own : 1;
        const tall = high > 0 ? height / high : 1;
        return Math.min(1, wide, tall);
    }
    readonly property bool scaledDown: fitScale < 0.999

    readonly property var control: builder.control
    readonly property string failure: builder.failure
    readonly property string typeName: (entry.type ?? "").split("/").pop().replace(".qml", "")

    implicitWidth: builder.control?.implicitWidth ?? 120
    implicitHeight: builder.control?.implicitHeight ?? 40

    // What the widget ended up being, as numbers. Everything a design audit
    // asks - is this the same height as that, does it round like its family -
    // is answered from here, live, rather than from the tokens the file names:
    // a control that computes its own height from a font does not report the
    // token anyone wrote down.
    readonly property var measurements: {
        const control = builder.control;
        if (!control)
            return null;
        const value = (name, fallback) => {
            const read = control[name];
            return read === undefined ? fallback : read;
        };
        return {
            width: control.implicitWidth,
            height: control.implicitHeight,
            radius: value("buttonRadius", undefined),
            radiusPressed: value("buttonRadiusPressed", undefined),
            cornerTopLeft: value("cornerTopLeft", undefined),
            cornerBottomRight: value("cornerBottomRight", undefined),
            horizontalPadding: value("horizontalPadding", undefined),
            verticalPadding: value("verticalPadding", undefined),
            fontSize: control.font?.pixelSize,
            background: value("colBackground", undefined),
            hasEnabled: control.enabled !== undefined,
        };
    }

    function rebuild() {
        builder.build();
    }

    onOverridesChanged: builder.build()

    Item {
        id: builder
        anchors.fill: parent
        // The tile is the widget's whole world here; nothing of it may reach
        // its neighbours.
        clip: true
        transform: Scale {
            origin.x: builder.width / 2
            origin.y: builder.height / 2
            xScale: stage.fitScale
            yScale: stage.fitScale
        }

        property var control: null
        property var symbol: null
        property string failure: ""

        Component {
            id: symbolComponent
            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }
        }

        // The WHOLE message, reduced to its most useful line. Taking the first
        // line and everything after its last colon left the empty string for a
        // QML build error - whose first line is "Error: Qt.createQmlObject():
        // failed to create object:" - so twenty tiles drew nothing and said
        // nothing about why, the reason having been formatted away.
        function explain(error) {
            const lines = `${error}`.split("\n")
                .map(line => line.trim()).filter(line => line.length > 0);
            const detail = lines.find(line =>
                /unavailable|is not a type|not installed|not initialized|Cannot assign/i.test(line));
            // The path is noise in a cell this size - "file:///home/…/inline:1:1:
            // module … is not installed" tells you nothing the last clause does
            // not, and it pushed the real sentence out of the tile.
            return (detail ?? lines[lines.length - 1] ?? `${error}`)
                .replace(/^.*\.qml:\d+:\d+:\s*/, "")
                .replace(/^(file:|qs:)\S*:\d+:\d+:\s*/, "")
                .replace(/^\S*inline:\d+:\d+:\s*/, "");
        }

        function moduleOf(path) {
            const parts = path.split("/");
            parts.pop();
            return "qs." + parts.join(".");
        }

        function build() {
            // Destroyed rather than re-propertied: a knob can change a value a
            // control only reads at construction (a required property, a
            // contentItem sized from an icon), and a control that quietly
            // ignored half the knobs would be worse than one that flickers.
            if (builder.control) {
                builder.control.destroy();
                builder.control = null;
            }
            builder.symbol = null;
            builder.failure = "";

            const path = stage.entry.type;
            const type = path.split("/").pop().replace(".qml", "");
            const props = Object.assign({}, stage.entry.props, stage.overrides);

            // Properties go in the OBJECT, not onto it afterwards.
            //
            // Assigning them after construction left a dozen tiles blank while
            // the same widget built declaratively drew perfectly: a control
            // whose size derives from its content measures that content once,
            // when it is built, and a text set a moment later never moves the
            // geometry that was computed around an empty one. Every real call
            // site declares its properties, so the gallery does too.
            //
            // It also makes a wrong property name a loud compile error rather
            // than a silently dropped assignment - which is how the catalogue
            // came to offer `buttonIcon` to three types that call it something
            // else.
            const literal = name => {
                const value = props[name];
                if (typeof value === "string")
                    return JSON.stringify(value);
                return `${value}`;
            };
            const body = Object.keys(props).map(name => `${name}: ${literal(name)}`).join("; ");

            // Two ways in, because neither reaches every type.
            //
            // A type reached by its MODULE gets that directory's other types
            // for free, which is what a file-path build cannot do - SearchItem
            // could not see its sibling CliphistImage and reported it as "not a
            // type", a lie about working code. But Quickshell only registers
            // SOME directories as modules, so the module route answers
            // `module "qs.modules.imi.sidebarLeft" is not installed` for a
            // dozen perfectly good widgets.
            //
            // So: module first, file second. Each covers the other's gap, and
            // only a type that fails BOTH ways has actually failed.
            try {
                builder.control = Qt.createQmlObject(
                    `import ${builder.moduleOf(path)}\n${type} { ${body} }`, builder);
            } catch (moduleError) {
                const component = Qt.createComponent(Quickshell.shellPath(path));
                let fileTrouble = "";
                if (component.status === Component.Error) {
                    fileTrouble = component.errorString();
                } else {
                    try {
                        builder.control = component.createObject(builder, props);
                    } catch (fileError) {
                        builder.control = null;
                        fileTrouble = `${fileError}`;
                    }
                    // createObject returns null WITHOUT throwing when a
                    // required property was never given - which is the whole
                    // reason a row fed by a service cannot be built here. Say
                    // that, rather than repeating the module lookup's
                    // complaint, which is about the gallery and not the widget.
                    if (!builder.control && fileTrouble === "")
                        fileTrouble = component.errorString() !== ""
                            ? component.errorString()
                            : Translation.tr("needs its data");
                }
                // The FILE route's complaint when it has one: it is the route
                // that actually reached the widget, so its answer is about the
                // widget. The module route's "not installed" is about this
                // gallery's own lookup and says nothing a reader can act on.
                if (!builder.control)
                    builder.failure = builder.explain(fileTrouble !== "" ? fileTrouble : moduleError);
                if (builder.failure !== "")
                    return;
            }
            if (!builder.control) {
                builder.failure = Translation.tr("needs its surroundings");
                return;
            }
            builder.control.anchors.centerIn = builder;

            // A widget with nothing to draw says so, instead of leaving an
            // empty cell that reads as a broken tile.
            //
            // `Qt.createQmlObject` does NOT throw on an uninitialised required
            // property - it warns and hands back an object - so the model-fed
            // rows (a Wi-Fi network, a tray entry, a search result) came back
            // alive and sized to nothing. Measuring the result is the honest
            // test: whatever the reason, a widget that lays out to nothing has
            // nothing to show here.
            if (builder.control.implicitWidth < 4 || builder.control.implicitHeight < 4)
                builder.failure = Translation.tr("needs its data");

            // A glyph only where the control has NO content of its own.
            //
            // The first version parented a MaterialSymbol into every control
            // that named one in the catalogue, as a plain child. For a type
            // that already draws something that is a SECOND thing on top of
            // the first, positioned at the origin rather than centred - which
            // is what the off-centre and doubled contents in the tiles were.
            // Assigned as `contentItem` instead, so the control lays it out
            // the way it lays out its own, and only when there is nothing to
            // displace.
            if (stage.entry.glyph) {
                const existing = builder.control.contentItem ?? null;
                const empty = !existing
                    || (existing.implicitWidth === 0 && existing.implicitHeight === 0);
                if (empty)
                    builder.control.contentItem = symbolComponent.createObject(
                        builder.control, { text: stage.entry.glyph });
            }
        }

        Component.onCompleted: builder.build()

        MouseArea {
            id: shield
            anchors.fill: parent
            z: 1000
            enabled: stage.inert
            visible: enabled
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            // Buttons only, NOT the wheel. Eating the wheel stopped a preview
            // slider changing under a scroll, and stopped the page scrolling
            // at all: the tiles cover most of the surface, so every scroll
            // landed on a shield and died there. A moved preview slider costs
            // nothing; a gallery that cannot be scrolled costs everything.

            readonly property var motion: builder.control?.interactionMotion ?? null

            // The cursor the control would show, since the shield is what the
            // pointer is actually over. RippleButton declares it as
            // `pointingHandCursor`; a control without that property, or a
            // tile with no control, keeps the arrow rather than promising a
            // press it does not draw.
            cursorShape: builder.control?.pointingHandCursor === true
                ? Qt.PointingHandCursor : Qt.ArrowCursor

            onContainsMouseChanged: if (motion) motion.hovered = containsMouse

            // A previewed press does everything a real one does EXCEPT act.
            //
            // Driving `interactionMotion` alone gave the lift and the corner
            // morph and left the ripple behind, because the ripple is the
            // control's own animation and the control never saw the press.
            // `startRipple` and `fadeRipple` are its public pair, so the
            // preview can spend them.
            onPressed: mouse => {
                if (motion) motion.down = true;
                if (builder.control?.startRipple)
                    builder.control.startRipple(mouse.x, mouse.y);
            }
            onReleased: {
                if (motion) motion.down = false;
                if (builder.control?.fadeRipple)
                    builder.control.fadeRipple();
                // Nothing else. A press is TRANSIENT - ripple, lift, corner
                // morph - and it ends where it started. Flipping the control's
                // `toggled` here was a state change dressed as a preview: it
                // outlived the press, left no way back except rebuilding, and
                // fought the Detail page's own `toggled` knob for ownership of
                // the same property. State belongs to the knobs; a tile is a
                // picture of a widget, and pressing a picture shows you the
                // press, not a different picture.
            }
            onCanceled: {
                if (motion) motion.down = false;
                if (builder.control?.fadeRipple)
                    builder.control.fadeRipple();
            }
        }

        StyledText {
            visible: builder.failure !== ""
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            // Bounded: a QML build error is a paragraph, and one of them ran
            // three lines past its tile and over the widget beside it.
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: builder.failure
        }
    }
}
