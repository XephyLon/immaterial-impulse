pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io

import qs.modules.common.plugins
import qs.modules.common.plugins.designsystem.widgets as Expressive

// A subdirectory of a bundled package is its own module: it needs its own
// `qmldir` and an explicit import here. Same-directory siblings need no
// import - the `qmldir` alone is what makes them types. See
// docs/PLUGINS.md, "Multi-file packages".
import "dateIndicator"
import "minuteMarks"

Item {
    id: root

    property real implicitSize: 230

    // The package wrapper forwards the host's drag; the cookie lifts on it the
    // same way every card does.
    property bool dragging: false

    // The cookie style owns every `cookie*` option: nothing outside this
    // subtree reads one, and each child that needs one is handed it. That
    // keeps a single reader (and so a single default) per option.
    readonly property bool aiStyling: PluginState.option("clock", "cookieAiStyling", false)
    readonly property int sides: PluginState.option("clock", "cookieSides", 14)
    readonly property string dialNumberStyle: PluginState.option("clock", "cookieDialNumberStyle", "full")
    readonly property string hourHandStyle: PluginState.option("clock", "cookieHourHandStyle", "fill")
    readonly property string minuteHandStyle: PluginState.option("clock", "cookieMinuteHandStyle", "medium")
    readonly property string secondHandStyle: PluginState.option("clock", "cookieSecondHandStyle", "dot")
    readonly property string dateStyle: PluginState.option("clock", "cookieDateStyle", "bubble")
    readonly property bool timeIndicators: PluginState.option("clock", "cookieTimeIndicators", true)
    readonly property bool hourMarks: PluginState.option("clock", "cookieHourMarks", false)
    readonly property bool constantlyRotate: PluginState.option("clock", "cookieConstantlyRotate", false)
    readonly property bool useSineCookie: PluginState.option("clock", "cookieUseSineCookie", false)

    property color colShadow: Appearance.colors.colShadow
    property color colBackground: Appearance.colors.colPrimaryContainer
    property color colOnBackground: ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colPrimaryContainer, 0.15)
    property color colBackgroundInfo: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.55)
    property color colHourHand: Appearance.colors.colPrimary
    property color colMinuteHand: Appearance.colors.colTertiary
    property color colSecondHand: Appearance.colors.colPrimary

    readonly property list<string> clockNumbers: DateTime.time.split(/[: ]/)
    readonly property int clockHour: parseInt(clockNumbers[0]) % 12
    readonly property int clockMinute: DateTime.clock.minutes
    // The clock owns its seconds: DateTime's shared SystemClock ticks
    // minutes unless the BAR asks for second precision, and a second hand
    // gated on that knob is a hand the style row promises but a format
    // setting silently hides - which is exactly how it shipped broken.
    // Local, and at Seconds only while a hand is drawn, so a hidden hand
    // costs nothing.
    readonly property var secondsClock: SystemClock {
        precision: root.secondHandStyle !== "hide" ? SystemClock.Seconds
                                                   : SystemClock.Minutes
    }
    readonly property int clockSecond: root.secondsClock.seconds

    // Continuous motion - the body's spin and the second hand's sweep - is
    // sampled from the wall clock at this rate rather than animated per
    // vsync. See the body's `rotation` for the measurement behind the number.
    readonly property int motionTickHz: 30
    readonly property int spinPeriodMs: 30000
    property real motionClockMs: 0

    // Where the second hand is within the current second, shaped the way its
    // old per-second Behavior shaped it (InOutQuad): it leaves one mark, eases
    // across, and settles on the next. Zero when not sweeping, so the hand
    // sits on the mark.
    readonly property real secondSweep: {
        if (!root.constantlyRotate)
            return 0;
        const f = (root.motionClockMs % 1000) / 1000;
        return f < 0.5 ? 2 * f * f : 1 - Math.pow(-2 * f + 2, 2) / 2;
    }

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    // Gap 12 does not bite here: every writer goes through PluginState, and
    // nothing in this widget ever assigns one of the option properties above
    // directly, so their bindings survive and the preset shows up live.
    function applyStyle(newSides, newDialStyle, newHourHandStyle, newMinuteHandStyle, newSecondHandStyle, newDateStyle) {
        PluginState.setOption("clock", "cookieSides", newSides)
        PluginState.setOption("clock", "cookieDialNumberStyle", newDialStyle)
        PluginState.setOption("clock", "cookieHourHandStyle", newHourHandStyle)
        PluginState.setOption("clock", "cookieMinuteHandStyle", newMinuteHandStyle)
        PluginState.setOption("clock", "cookieSecondHandStyle", newSecondHandStyle)
        PluginState.setOption("clock", "cookieDateStyle", newDateStyle)
    }

    function setClockPreset(category) {
        if (!root.aiStyling) return;
        if (category === "") return;
        print("[Cookie clock] Setting clock preset for category: " + category)
        // "abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space"
        if (category == "abstract") {
            applyStyle(9, "none", "fill", "medium", "dot", "bubble")
        } else if (category == "anime") {
            applyStyle(7, "none", "fill", "bold", "dot", "bubble")
        } else if (category == "city" || category == "space") {
            applyStyle(23, "full", "hollow", "thin", "classic", "bubble")
        } else if (category == "minimalist") {
            applyStyle(6, "none", "fill", "bold", "dot", "hide")
        } else if (category == "landscape") {
            applyStyle(14, "full", "hollow", "medium", "classic", "bubble")
        } else if (category == "plants") {
            applyStyle(9, "dots", "fill", "bold", "dot", "border")
        } else if (category == "person") {
            applyStyle(14, "full", "classic", "classic", "classic", "rect")
        }
    }

    FileView {
        id: categoryFileView
        path: Config.ready ? Directories.generatedWallpaperCategoryPath : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.setClockPreset(categoryFileView.text().trim())
        }
    }

    // The tokens, not the component: what casts the shadow here is a twelve-
    // or fourteen-lobed cookie, and a WidgetCard is a rounded rectangle with
    // the dial's hands and numerals inside it - every one of which would cast
    // a shadow of its own. The elevation shadows painted alpha, so the cookie
    // casts a cookie.
    //
    // The rotation belongs to this item because it is the drawn one. The old
    // drop shadow was the only renderer (both loaders were `visible: false`)
    // and carried the rotation itself; the loaders are drawn again now, so the
    // spin has to be on what contains them.
    Expressive.WidgetElevation {
        id: cookieBody
        anchors.fill: parent
        dragging: root.dragging

        Timer {
            running: root.constantlyRotate && cookieBody.visible
            interval: Math.round(1000 / root.motionTickHz)
            repeat: true
            triggeredOnStart: true
            onTriggered: root.motionClockMs = Date.now()
        }

        // The spin is a function of the wall clock, advanced by the tick below
        // - not a RotationAnimation. An animation advances every vsync, and on
        // this surface every advance is a commit with whole-surface damage
        // (Qt's GL path reports no less), which is the compositor re-rendering
        // all 5120x1440 and re-blurring every surface over it, 240 times a
        // second, for a rotation that takes 30 seconds. Measured at idle on
        // the user's machine, GPU utilisation: 38% spinning at vsync, 28% at
        // a 60Hz tick, 20% at 30Hz, 10-12% with the spin off. At 30Hz the rim
        // of a 230px cookie moves 0.8px per tick, which is under where a step
        // reads, so that is the rate.
        //
        // Still gated on the item being ON SCREEN, for the reason the old
        // animation was: `visible` is EFFECTIVE visibility, false while any
        // ancestor is hidden, so a desktop behind a fullscreen game spends
        // nothing here. Measured against FFXIV's own counter: 52 fps with the
        // spin ungated, 94 gated, 108 with the shell not running at all.
        rotation: 360 - (root.motionClockMs % root.spinPeriodMs) / root.spinPeriodMs * 360

        Loader {
            id: sineCookieLoader
            z: 0
            active: root.useSineCookie
            sourceComponent: SineCookie {
                implicitSize: root.implicitSize
                sides: root.sides
                color: root.colBackground
            }
        }
        Loader {
            id: roundedPolygonCookieLoader
            z: 0
            active: !root.useSineCookie
            sourceComponent: MaterialCookie {
                implicitSize: root.implicitSize
                sides: root.sides
                color: root.colBackground
            }
        }
    }

    // Hour/minutes numbers/dots/lines
    MinuteMarks {
        anchors.fill: parent
        color: root.colOnBackground
        style: root.dialNumberStyle
    }

    // Stupid extra hour marks in the middle
    FadeLoader {
        id: hourMarksLoader
        anchors.centerIn: parent
        shown: root.hourMarks
        sourceComponent: HourMarks {
            implicitSize: 135 * (1.75 - 0.75 * hourMarksLoader.opacity)
            color: root.colOnBackground
            colOnBackground: ColorUtils.mix(root.colBackgroundInfo, root.colOnBackground, 0.5)
        }
    }

    // Number column in the middle
    FadeLoader {
        id: timeColumnLoader
        anchors.centerIn: parent
        shown: root.timeIndicators
        scale: 1.4 - 0.4 * timeColumnLoader.shown
        Behavior on scale {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        sourceComponent: TimeColumn {
            color: root.colBackgroundInfo
            hourMarksEnabled: root.hourMarks
        }
    }

    // Minute hand
    FadeLoader {
        anchors.fill: parent
        z: 1
        shown: root.minuteHandStyle !== "hide"
        sourceComponent: MinuteHand {
            anchors.fill: parent
            clockMinute: root.clockMinute
            style: root.minuteHandStyle
            color: root.colMinuteHand
        }
    }

    // Hour hand
    FadeLoader {
        anchors.fill: parent
        z: item?.style === "hollow" ? 0 : 2
        shown: root.hourHandStyle !== "hide"
        sourceComponent: HourHand {
            clockHour: root.clockHour
            clockMinute: root.clockMinute
            style: root.hourHandStyle
            color: root.colHourHand
        }
    }

    // Second hand
    FadeLoader {
        id: secondHandLoader
        z: (root.secondHandStyle === "line") ? 2 : 3
        shown: root.secondHandStyle !== "hide"
        anchors.fill: parent
        sourceComponent: SecondHand {
            id: secondHand
            clockSecond: root.clockSecond
            style: root.secondHandStyle
            // Sampled, not animated: see `motionTickHz`.
            animateRotation: false
            sweep: root.secondSweep
            color: root.colSecondHand
        }
    }

    // Center dot
    FadeLoader {
        z: 4
        anchors.centerIn: parent
        shown: root.minuteHandStyle !== "bold"
        sourceComponent: Rectangle {
            color: root.minuteHandStyle === "medium" ? root.colBackground : root.colMinuteHand
            implicitWidth: 6
            implicitHeight: implicitWidth
            radius: width / 2
        }
    }

    // Date
    FadeLoader {
        anchors.fill: parent
        shown: root.dateStyle !== "hide"

        sourceComponent: DateIndicator {
            color: root.colBackgroundInfo
            style: root.dateStyle
        }
    }
}
