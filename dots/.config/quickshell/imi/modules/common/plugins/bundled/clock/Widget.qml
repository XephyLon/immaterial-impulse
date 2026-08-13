import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins

Item {
    id: root

    // No manifest `grid`, and deliberately no `anchors.fill: parent`. Every
    // style is a different shape - a 230px dial, a digital readout whose width
    // follows a user-set font size, a 276x252 or 420x150 pixel grid - so there
    // is no span that fits, and the widget stays content-sized. PluginNode
    // derives its own size from this item in that mode, so anchoring here is a
    // binding loop rather than a layout. See docs/widget-grid.md.
    implicitWidth: contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    // Host context (PluginNode binds these when the item declares them).
    property string screenName: ""
    property real hostX: 0
    property color hostColText: Appearance.colors.colOnLayer0
    property bool wallpaperSafetyTriggered: false
    // Forwarded to the two styles that draw a body of their own, so they lift
    // while the widget is handled. A body never told about the drag silently
    // never lifts.
    property bool hostDragging: false

    // Host opt-ins (PluginNode reads these back off the item).
    //
    // The lock screen has no clock of its own - LockSurface draws the password
    // field and nothing else - so this widget is it. That is why it ignores
    // `lock.showWidgets`, which is about the *other* desktop widgets, and why
    // it still centres itself there exactly as it always has.
    readonly property bool visibleWhenLocked: true
    readonly property bool forceCenter: GlobalStates.screenLocked && Config.options.lock.centerClock
    // Only the digital style paints bare text straight onto the wallpaper, so
    // only it needs the host's wallpaper-adaptive colour - and the least-busy
    // region pass that produces it.
    readonly property bool needsColText: root.clockStyle === "digital"

    // Gap 4: no style draws a panel behind itself, so there is nothing to
    // frost. An empty region list tells the host to skip the blur surface
    // rather than frosting the widget's empty bounding box. The cost is a
    // "Blur background" toggle in the settings panel that does nothing - the
    // known trade, and the same one the visualizer makes.
    readonly property var blurRegions: []

    readonly property var hostScreen: Quickshell.screens.find(screen => screen.name === root.screenName) ?? null
    readonly property real hostScreenWidth: root.hostScreen?.width ?? 0

    readonly property string style: PluginState.option("clock", "style", "cookie")
    readonly property string styleLocked: PluginState.option("clock", "styleLocked", "cookie")
    readonly property bool showOnlyWhenLocked: PluginState.option("clock", "showOnlyWhenLocked", false)

    readonly property bool digitalVertical: PluginState.option("clock", "digitalVertical", false)
    readonly property bool digitalShowDate: PluginState.option("clock", "digitalShowDate", true)
    readonly property bool digitalAnimateChange: PluginState.option("clock", "digitalAnimateChange", true)
    readonly property bool digitalAdaptiveAlignment: PluginState.option("clock", "digitalAdaptiveAlignment", true)
    readonly property string digitalFontFamily: PluginState.option("clock", "digitalFontFamily", "Google Sans Flex")
    readonly property real digitalFontWeight: PluginState.option("clock", "digitalFontWeight", 350)
    readonly property real digitalFontSize: PluginState.option("clock", "digitalFontSize", 90)
    readonly property real digitalFontWidth: PluginState.option("clock", "digitalFontWidth", 100)
    readonly property real digitalFontRoundness: PluginState.option("clock", "digitalFontRoundness", 0)

    readonly property string pixelOrientation: PluginState.option("clock", "pixelOrientation", "vertical")

    readonly property bool quoteEnable: PluginState.option("clock", "quoteEnable", false)
    readonly property string quoteText: PluginState.option("clock", "quoteText", "")
    readonly property bool quoteFollowClock: PluginState.option("clock", "quoteFollowClock", false)

    readonly property string clockStyle: GlobalStates.screenLocked ? root.styleLocked : root.style
    readonly property bool shouldShow: !root.showOnlyWhenLocked || GlobalStates.screenLocked

    readonly property string customClockColorKey: PluginState.option("clock", "color", "")
    readonly property color resolvedClockColor: {
        if (root.customClockColorKey === "") return root.hostColText;
        const propName = "col" + root.customClockColorKey.charAt(0).toUpperCase() + root.customClockColorKey.slice(1);
        return Appearance.colors[propName] ?? root.hostColText;
    }

    // Which third of its own monitor the widget sits in. The host owns the
    // position, so it hands the widget its x rather than the widget digging it
    // back out of a parent chain three Loaders deep.
    property var textHorizontalAlignment: {
        if (!root.digitalAdaptiveAlignment || root.forceCenter || root.digitalVertical)
            return Text.AlignHCenter;
        if (root.hostX < root.hostScreenWidth / 3)
            return Text.AlignLeft;
        if (root.hostX > root.hostScreenWidth * 2 / 3)
            return Text.AlignRight;
        return Text.AlignHCenter;
    }

    Column {
        id: contentColumn
        anchors.centerIn: parent
        spacing: Appearance.spacing.space150

        FadeLoader {
            id: cookieClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "cookie" && root.shouldShow
            fade: false
            sourceComponent: CookieClock {
                anchors.horizontalCenter: parent.horizontalCenter
                dragging: root.hostDragging
            }
        }

        FadeLoader {
            id: digitalClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "digital" && root.shouldShow
            fade: false
            sourceComponent: DigitalClock {
                colText: root.resolvedClockColor
                textHorizontalAlignment: root.textHorizontalAlignment
                isVertical: root.digitalVertical
                showDate: root.digitalShowDate
                animateTimeChange: root.digitalAnimateChange
                clockFontFamily: root.digitalFontFamily
                clockFontSize: root.digitalFontSize
                clockFontWeight: root.digitalFontWeight
                clockFontWidth: root.digitalFontWidth
                clockFontRoundness: root.digitalFontRoundness
                quoteShown: root.quoteEnable && root.quoteText.length > 0
                quoteText: root.quoteText
                quoteFontFamily: root.quoteFollowClock ? root.digitalFontFamily : Appearance.font.family.expressive
            }
        }

        FadeLoader {
            id: pixelClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "pixel" && root.shouldShow
            fade: false
            sourceComponent: PixelClock {
                isVertical: root.pixelOrientation === "vertical"
                dragging: root.hostDragging
            }
        }

        FadeLoader {
            id: quoteLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.quoteEnable && (root.clockStyle === "pixel" || root.clockStyle === "cookie")
                && root.quoteText !== "" && root.shouldShow
            sourceComponent: CookieQuote {
                quoteText: root.quoteText
                aboveHorizontalPixelClock: root.clockStyle === "pixel" && root.pixelOrientation === "horizontal"
                quoteFontFamily: root.quoteFollowClock ? root.digitalFontFamily : Appearance.font.family.reading
            }
        }

        StatusRow {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    component StatusRow: Item {
        id: statusText
        implicitHeight: statusTextBg.implicitHeight
        implicitWidth: statusTextBg.implicitWidth
        StyledRectangularShadow {
            target: statusTextBg
            visible: statusTextBg.visible && root.clockStyle === "cookie"
            opacity: statusTextBg.opacity
        }
        Rectangle {
            id: statusTextBg
            anchors.centerIn: parent
            clip: true
            opacity: (safetyStatusText.shown || lockStatusText.shown) ? 1 : 0
            visible: opacity > 0
            implicitHeight: statusTextRow.implicitHeight + 5 * 2
            implicitWidth: statusTextRow.implicitWidth + 5 * 2
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, root.clockStyle === "cookie" ? 0 : 1)

            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: statusTextRow
                anchors.centerIn: parent
                spacing: Appearance.spacing.space200
                Item {
                    Layout.fillWidth: root.textHorizontalAlignment !== Text.AlignLeft
                    implicitWidth: 1
                }
                ClockStatusText {
                    id: safetyStatusText
                    shown: root.wallpaperSafetyTriggered
                    statusIcon: "hide_image"
                    statusText: Translation.tr("Wallpaper safety enforced")
                }
                ClockStatusText {
                    id: lockStatusText
                    shown: GlobalStates.screenLocked && Config.options.lock.showLockedText
                    statusIcon: "lock"
                    statusText: Translation.tr("Locked")
                }
                Item {
                    Layout.fillWidth: root.textHorizontalAlignment !== Text.AlignRight
                    implicitWidth: 1
                }
            }
        }
    }

    component ClockStatusText: Row {
        id: statusTextRow
        property alias statusIcon: statusIconWidget.text
        property alias statusText: statusTextWidget.text
        property bool shown: true
        property color textColor: root.clockStyle === "cookie" ? Appearance.colors.colOnSecondaryContainer : root.hostColText
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        spacing: Appearance.spacing.space50
        MaterialSymbol {
            id: statusIconWidget
            anchors.verticalCenter: statusTextRow.verticalCenter
            iconSize: Appearance.font.pixelSize.huge
            color: statusTextRow.textColor
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
        ClockText {
            id: statusTextWidget
            clockFontFamily: root.quoteFollowClock ? root.digitalFontFamily : Appearance.font.family.expressive
            animateChange: root.digitalAnimateChange
            color: statusTextRow.textColor
            horizontalAlignment: root.textHorizontalAlignment
            anchors.verticalCenter: statusTextRow.verticalCenter
            font {
                pixelSize: Appearance.font.pixelSize.large
                weight: Font.Normal
            }
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
    }
}
