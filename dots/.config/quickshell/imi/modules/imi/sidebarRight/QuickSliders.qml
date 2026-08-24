import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower

Rectangle {
    id: root

    property int entranceTrigger: -1
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)

    implicitWidth: contentItem.implicitWidth + root.horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + root.verticalPadding * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    property real verticalPadding: Appearance.spacing.space50
    property real horizontalPadding: Appearance.spacing.space150

    Column {
        id: contentItem
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
        }

        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showBrightness
            sourceComponent: QuickSlider {
                entranceTrigger: root.entranceTrigger
                sliderIndex: 0
                materialSymbol: "brightness_medium"
                secondaryMaterialSymbol: "wb_twilight"
                stopIndicatorValues: Hyprsunset.gamma !== 100 && root.brightnessMonitor?.brightness !== 0 ? [0.3 + root.brightnessMonitor?.brightness * 0.7] : []
                shownValue: Hyprsunset.gamma === 100? 0.3 + root.brightnessMonitor?.brightness * 0.7 : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * 0.3
                tooltipContent: Hyprsunset.gamma === 100 ? `${Math.round(root.brightnessMonitor?.brightness * 100)}%` : `${Translation.tr("Gamma")} ${Hyprsunset.gamma}%`
                onMoved: {
                    if (value >= 0.3) {
                        // 0.3 - 1.0 brightness
                        root.brightnessMonitor.setBrightness((value - 0.3) / 0.7);
                        if (Hyprsunset.gamma !== 100) {
                            Hyprsunset.setGamma(100);
                        }
                    } else {
                        // 0 - 0.3 gamma
                        if (root.brightnessMonitor.brightness !== 0) {
                            root.brightnessMonitor.setBrightness(0);
                        }
                        Hyprsunset.setGamma((value / 0.3 * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit));
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: Math.max(volumeLoader.implicitHeight, micLoader.implicitHeight)
            spacing: Appearance.spacing.space50

            Loader {
                id: volumeLoader
                width: micLoader.active ? (parent.width - parent.spacing) / 2 : parent.width
                visible: active
                active: Config.options.sidebar.quickSliders.showVolume
                sourceComponent: QuickSlider {
                    entranceTrigger: root.entranceTrigger
                    sliderIndex: 1
                    materialSymbol: "volume_up"
                    shownValue: Audio.sink?.audio?.volume ?? 0
                    onMoved: {
                        if (Audio.sink?.audio)
                            Audio.sink.audio.volume = value
                    }
                }
            }

            Loader {
                id: micLoader
                width: volumeLoader.active ? (parent.width - parent.spacing) / 2 : parent.width
                visible: active
                active: Config.options.sidebar.quickSliders.showMic
                sourceComponent: QuickSlider {
                    entranceTrigger: root.entranceTrigger
                    sliderIndex: 2
                    materialSymbol: "mic"
                    shownValue: Audio.source?.audio?.volume ?? 0
                    onMoved: {
                        if (Audio.source?.audio)
                            Audio.source.audio.volume = value
                    }
                }
            }
        }
    }

    component QuickSlider: StyledSlider { 
        id: quickSlider
        required property string materialSymbol
        property string secondaryMaterialSymbol
        // The entrance is a FILL SWEEP, the sibling fork's slider grammar:
        // the value holds at zero while the panel is away and glides up to
        // the real reading when the open's trigger fires, staggered per
        // slider - no fade anywhere. Call sites bind `shownValue`; `value`
        // stays this component's own so the hold cannot destroy a binding.
        property int entranceTrigger: -1
        property int sliderIndex: 0
        property real shownValue: 0
        property bool entranceParked: false
        value: entranceParked ? 0 : shownValue
        onEntranceTriggerChanged: {
            quickSlider.entranceParked = true;
            sweepTimer.restart();
        }
        Timer {
            id: sweepTimer
            // The fork's cadence: 180ms head start, 70ms per slider.
            interval: Appearance.animation.scale(180 + quickSlider.sliderIndex * 70)
            onTriggered: {
                // The named glide velocity turns the release into the fork's
                // ~650ms sweep; restored (as a binding) once the sweep lands.
                const sweepMs = Appearance.animation.scale(650);
                quickSlider.valueVelocity = Math.max(0.05, quickSlider.shownValue / (sweepMs / 1000));
                quickSlider.entranceParked = false;
                sweepRestore.interval = sweepMs + 80;
                sweepRestore.restart();
            }
        }
        Timer {
            id: sweepRestore
            onTriggered: quickSlider.valueVelocity =
                Qt.binding(() => Appearance.animation.elementMoveFast.velocity)
        }
        configuration: StyledSlider.Configuration.M
        stopIndicatorValues: []
        dividerValues: secondaryMaterialSymbol.length > 0 ? [secondaryIcon.iconLocation] : []
        
        MaterialSymbol {
            id: icon
            property bool nearFull: quickSlider.value >= 0.9
            anchors {
                verticalCenter: quickSlider.verticalCenter
                right: nearFull ? quickSlider.handle.right : quickSlider.right
                rightMargin: nearFull ? 14 : 8
            }
            iconSize: 20
            color: nearFull ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: quickSlider.materialSymbol
            // The fork's slider icon spins with the fill - one turn across
            // the whole range, settling with the same slight overshoot.
            rotation: quickSlider.value * 360
            Behavior on rotation {
                NumberAnimation {
                    duration: Appearance.animation.scale(350)
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.5
                }
            }

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on anchors.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            id: secondaryIcon
            visible: secondaryMaterialSymbol.length > 0
            property real iconLocation: 0.3
            property bool nearIcon: iconLocation - quickSlider.value <= 0.1 && iconLocation - quickSlider.value > (quickSlider.handleWidth + 8 - 14) / quickSlider.effectiveDraggingWidth
            anchors {
                verticalCenter: quickSlider.verticalCenter
                right: nearIcon ? quickSlider.handle.right : quickSlider.right
                rightMargin: nearIcon ? 14 : (1 - iconLocation) * quickSlider.effectiveDraggingWidth + quickSlider.rightPadding + 8
            }
            iconSize: 20
            color: quickSlider.value >= iconLocation - 0.1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: secondaryMaterialSymbol

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
