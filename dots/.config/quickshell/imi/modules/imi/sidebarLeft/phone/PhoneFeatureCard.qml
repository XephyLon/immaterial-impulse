pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * One card of the Phone tab's bottom stack: the scrcpy mirror, the phone
 * webcam, the phone microphone.
 *
 * It is a state machine with five rungs - `unavailable | offline | connecting
 * | ready | active` - and the ladder itself lives in phone_cards.js, because
 * nothing about a drawn card is reachable from qmltestrunner
 * (tests/tst_phone_cards.qml drives it). This file is what the rungs LOOK
 * like: a flat container, a shaped glyph, a title, a subtitle, and a trailing
 * mark saying whether the card acts, is working, or is running.
 *
 * `active` is the one rung that changes the card's shape: it grows to carry a
 * detail line (how long the session has been up, and what it is bound to), an
 * inline error banner, a Stop button and the feature's own action chips.
 * Everything else is one height, so a stack of three cards does not reflow
 * every time a phone goes in and out of reach.
 *
 * The card never talks to a service. `clicked()`, `stopClicked()` and
 * `filesDropped(urls)` are announcements; PhoneFeatureCards.qml is what turns
 * them into calls, which is what keeps a card from being a place a fake
 * action can hide.
 *
 * `cardState` rather than QML's own `state`: Item.state drives States/
 * Transitions, and a string property shadowing it means a typo elsewhere in
 * the file silently becomes a state name that matches nothing.
 */
Item {
    id: root

    property string cardState: "ready"
    property string iconName: "smart_display"
    property var iconShape: MaterialShape.Shape.Cookie9Sided
    property string title: ""
    property string subtitle: ""
    // The line under the title while the card is active - built by the caller,
    // because only it knows whether "for 7m 05s" is followed by a device node,
    // an address or a gain.
    property string detailLine: ""
    // The feature's own last error, drawn inline while the card is active.
    // Never the card's only report of a failure: a card that is not running
    // carries it in the subtitle instead.
    property string lastError: ""
    // [{ icon, label, action }] - `action` is called with no arguments.
    property var inlineActions: []
    property bool dropEnabled: false
    // A card whose feature has a sub-page draws a settings button beside the
    // status mark. It is a second affordance rather than a second meaning for
    // the card's own click, because the page has to be reachable in every one
    // of the five states - including `unavailable`, where the card's click is
    // the install guide, and `active`, where it is the feature's own toggle.
    property bool hasSettings: false

    signal clicked
    signal settingsClicked
    signal stopClicked
    signal filesDropped(var urls)

    readonly property bool isActive: root.cardState === "active"
    readonly property bool isConnecting: root.cardState === "connecting"
    readonly property bool isMuted: root.cardState === "unavailable" || root.cardState === "offline"
    readonly property color colForeground: root.isMuted
        ? Appearance.colors.colOnLayer3
        : Appearance.colors.colOnPrimaryContainer

    implicitHeight: root.isActive ? cardColumn.implicitHeight + Appearance.spacing.space100 * 2 : cardHeight
    readonly property real cardHeight: 68

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        id: cardBackground
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root.isMuted ? Appearance.colors.colLayer3 : Appearance.colors.colPrimaryContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // The press/hover wash. Drawn as its own rectangle rather than by
        // mixing the body's colour, so the two Behaviors do not fight over one
        // property while a state change is also recolouring the card.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.colForeground
            opacity: cardArea.containsPress ? 0.14 : (cardArea.containsMouse ? 0.07 : 0)

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFaster.numberAnimation.createObject(this)
            }
        }
    }

    MouseArea {
        id: cardArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: cardColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: Appearance.spacing.space150
            rightMargin: Appearance.spacing.space150
            topMargin: Appearance.spacing.space100
        }
        spacing: Appearance.spacing.space75

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.cardHeight - Appearance.spacing.space100 * 2
            spacing: Appearance.spacing.space125

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                // The glyph says what the card would DO, which for an
                // unreachable or uninstalled feature is not what it is: a
                // download mark and a cast mark are the two states where the
                // feature's own icon would be a promise.
                text: root.cardState === "unavailable" ? "download"
                    : root.cardState === "offline" ? "cast"
                    : root.iconName
                wrappedShape: root.iconShape
                iconSize: Appearance.font.pixelSize.large
                padding: Appearance.spacing.space125
                color: ColorUtils.transparentize(root.colForeground, 0.82)
                colSymbol: root.colForeground
                // No `animateChange` here, deliberately, and it is a fix
                // rather than an omission. StyledText's deferred swap fades
                // the GLYPH to zero, holds it there for the PropertyAction
                // that applies the pending text, and fades it back - inside a
                // MaterialShape that does not fade with it, so every frame of
                // the swap is a badge with a hole in it. Two things make that
                // worse here than anywhere else the idiom is used. This
                // card's other three elements - the title, the subtitle and
                // the trailing mark - change in one frame, so the glyph was
                // the only part of the card out of step with its own state.
                // And a rung can move twice inside one tier (offline ->
                // connecting -> offline is what a launch that cannot start
                // does), which retriggers the fade from wherever it had got
                // to: measured in PhoneTabRuntimeTest, the glyph sat at or
                // under 0.02 opacity for over 200ms of a 150ms tier and came
                // out the other side still drawing the icon it went in with,
                // having swapped nothing at all. Read on screen that is "the
                // card's icon is gone".
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.colForeground
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ColorUtils.transparentize(root.colForeground, 0.3)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            RippleButton {
                id: settingsButton
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                visible: root.hasSettings
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(root.colForeground, 0.85)
                colBackgroundHover: ColorUtils.transparentize(root.colForeground, 0.72)
                colRipple: ColorUtils.transparentize(root.colForeground, 0.62)
                onClicked: root.settingsClicked()

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "tune"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.colForeground
                }

                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }

            // Three marks, one slot: a chevron for a card that acts, the house
            // spinner while it is working, a filled check while it runs.
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Appearance.font.pixelSize.huge
                Layout.preferredHeight: Appearance.font.pixelSize.huge

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.isActive && !root.isConnecting
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    color: ColorUtils.transparentize(root.colForeground, 0.5)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.isActive
                    text: "check_circle"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.colForeground
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.isConnecting
                    loading: root.isConnecting
                    implicitSize: Appearance.font.pixelSize.huge
                    colBg: "transparent"
                    colShape: root.colForeground
                }
            }
        }

        // Everything below is the `active` rung. It is declared inside the
        // column rather than in a Loader so the column's implicitHeight - what
        // the card animates to - is the height the content will actually take
        // rather than a measurement taken a frame later.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Appearance.spacing.space100
            visible: root.isActive
            spacing: Appearance.spacing.space75

            StyledText {
                Layout.fillWidth: true
                visible: root.detailLine.length > 0
                text: root.detailLine
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: ColorUtils.transparentize(root.colForeground, 0.2)
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: errorText.implicitHeight + Appearance.spacing.space100
                visible: root.lastError.length > 0
                radius: Appearance.rounding.small
                color: Appearance.colors.colErrorContainer

                StyledText {
                    id: errorText
                    anchors {
                        fill: parent
                        leftMargin: Appearance.spacing.space100
                        rightMargin: Appearance.spacing.space100
                    }
                    verticalAlignment: Text.AlignVCenter
                    text: root.lastError
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnErrorContainer
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space75

                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.colors.colErrorContainerActive
                    onClicked: root.stopClicked()

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space75

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "stop_circle"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnErrorContainer
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Stop")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }
                }

                Repeater {
                    model: root.inlineActions

                    delegate: RippleButton {
                        id: chip
                        required property var modelData

                        Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                        Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                        buttonRadius: Appearance.rounding.small
                        colBackground: ColorUtils.transparentize(root.colForeground, 0.82)
                        colBackgroundHover: ColorUtils.transparentize(root.colForeground, 0.7)
                        colRipple: ColorUtils.transparentize(root.colForeground, 0.6)
                        onClicked: {
                            const action = chip.modelData?.action;
                            if (typeof action === "function")
                                action();
                        }

                        // A Control sizes and positions its content item
                        // itself, so an anchor on the glyph is decoration and
                        // both alignments are what centre it.
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: chip.modelData?.icon ?? ""
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.colForeground
                            animateChange: true
                        }

                        StyledToolTip {
                            text: chip.modelData?.label ?? ""
                        }
                    }
                }
            }
        }
    }

    // Files dropped on a running card go to the phone. Only while it IS
    // running: a card offering to send a file to a feature that is not up is a
    // drop that silently does nothing.
    DropArea {
        id: dropArea
        anchors.fill: parent
        enabled: root.dropEnabled && root.isActive

        onEntered: drag => {
            if (drag.hasUrls)
                drag.acceptProposedAction();
        }
        onDropped: drag => {
            if (drag.hasUrls && drag.urls.length > 0)
                root.filesDropped(Array.from(drag.urls));
            drag.acceptProposedAction();
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colPrimaryContainer
            border.color: Appearance.colors.colPrimary
            border.width: Appearance.borderWidth.emphasis
            opacity: dropArea.containsDrag ? 0.85 : 0
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Appearance.spacing.space50

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "drive_file_move"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drop to share on phone")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}
