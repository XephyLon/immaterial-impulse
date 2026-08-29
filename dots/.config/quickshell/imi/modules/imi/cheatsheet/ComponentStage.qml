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
            hasToggled: control.toggled !== undefined,
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

            const url = Quickshell.shellPath(stage.entry.type);
            const component = Qt.createComponent(url);
            if (component.status === Component.Error) {
                builder.failure = component.errorString().split("\n")[0].split(":").pop().trim();
                return;
            }
            try {
                const props = Object.assign({}, stage.entry.props, stage.overrides);
                builder.control = component.createObject(builder, props);
                if (!builder.control) {
                    builder.failure = Translation.tr("needs its surroundings");
                    return;
                }
                builder.control.anchors.centerIn = builder;
                // Several take their content as a CHILD rather than a
                // property - the toolbars, the badges, the expanders. Bare
                // they collapse to an empty box and read as broken rather
                // than as empty, so they get the glyph their call sites give
                // them.
                if (stage.entry.glyph)
                    builder.symbol = symbolComponent.createObject(
                        builder.control, { text: stage.entry.glyph });
            } catch (error) {
                builder.failure = `${error}`.split("\n")[0];
            }
        }

        Component.onCompleted: builder.build()

        StyledText {
            visible: builder.failure !== ""
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            text: builder.failure
        }
    }
}
