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

    // The sidebar's one entrance counter. Two things run on it here, and they
    // are deliberately two channels: each slider's FILL sweeps up from zero
    // (the QuickSlider component below), and each CARD arrives - a fade, a
    // zoom from a derived near-1 start and a rise, all on the one `appear`
    // scalar - the fork's AndroidSliderWidgetBase entrance, spelled with the
    // shared wave and dressing rather than as a fourth copy of the
    // three-channel choreography. Park-and-enter on the trigger, ungated,
    // for the reason SidebarRightContent gives: the wave runs UNDER the
    // slide's curtain, and only the last-ranked card visibly lands after it.
    property int entranceTrigger: -1
    onEntranceTriggerChanged: {
        sliderWave.park();
        sliderWave.enter();
    }
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)

    // The cards are not one container's children - the bottom row packs
    // volume and mic side by side - so the members are handed in as a list,
    // in the order they arrive: the bottom row first, brightness last.
    // `target` stays this card, the thing whose being on screen the runner
    // waits for before it starts.
    StaggerWave {
        id: sliderWave
        target: root
        items: [volumeLoader, micLoader, brightnessLoader]
        // The toggle grid's head start, for its reason: without one the
        // first-ranked card begins fading the instant the panel edge
        // appears and is well-lit before anything above it has started.
        leadIn: 80
    }

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

        // Dresses the one member that is this column's own child; the row
        // below dresses its two. The dressing is per CONTAINER because it
        // installs itself on a container's children, and the wave's list is
        // not a container.
        StaggerEntrance {
            target: contentItem
        }

        Loader {
            id: brightnessLoader
            property real appear: 1
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
            id: bottomRow
            width: parent.width
            height: Math.max(volumeLoader.implicitHeight, micLoader.implicitHeight)
            spacing: Appearance.spacing.space50

            StaggerEntrance {
                target: bottomRow
            }

            Loader {
                id: volumeLoader
                property real appear: 1
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
                property real appear: 1
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
        // The slider's own entrance is a FILL SWEEP, the sibling fork's
        // slider grammar: the value holds at zero while the panel is away
        // and glides up to the real reading when the open's trigger fires,
        // staggered per slider. The CARD's fade is the Loader's, one level
        // up, through the wave - never this control's opacity. Call sites
        // bind `shownValue`; `value` stays this component's own so the hold
        // cannot destroy a binding.
        property int entranceTrigger: -1
        property int sliderIndex: 0
        property real shownValue: 0
        property bool entranceParked: false
        value: entranceParked ? 0 : shownValue
        onEntranceTriggerChanged: {
            // The park must LAND, not glide: a reopen inside the previous
            // sweep's window otherwise rides the slow sweep velocity down -
            // a visible dip the second sweep then has to reverse.
            quickSlider.endSweep();
            quickSlider.valueGlide = false;
            quickSlider.entranceParked = true;
            quickSlider.valueGlide = true;
            sweepTimer.restart();
        }
        // Puts the glide back to the house velocity, whichever way the
        // sweep ends - by landing, or by the reading changing under it.
        function endSweep() {
            sweepRestore.stop();
            quickSlider.valueVelocity =
                Qt.binding(() => Appearance.animation.elementMoveFast.velocity);
        }
        // A reading that changes while the sweep owns the velocity is the
        // user (or another client) acting - choreography yields. Without
        // this, a volume key pressed inside the ~730ms window moved the
        // fill at the sweep's crawl and then snapped on the restore.
        onShownValueChanged: {
            if (sweepRestore.running)
                quickSlider.endSweep();
        }
        Timer {
            id: sweepTimer
            // Tightened from the fork's 180+70ms on the maintainer's call -
            // the sweep starts almost with the slide and the stagger stays.
            interval: Appearance.animation.scale(80 + quickSlider.sliderIndex * 50)
            onTriggered: {
                // The named glide velocity turns the release into the fork's
                // ~650ms sweep; restored (as a binding) once the sweep lands.
                // A near-zero reading gets no override: there is nothing to
                // sweep, and the floor this used to install (0.05 u/s) left
                // the fill nearly frozen against any input in the window.
                const sweepMs = Appearance.animation.scale(650);
                if (quickSlider.shownValue > 0.01) {
                    quickSlider.valueVelocity = quickSlider.shownValue / (sweepMs / 1000);
                    sweepRestore.interval = sweepMs + 80;
                    sweepRestore.restart();
                }
                quickSlider.entranceParked = false;
            }
        }
        Timer {
            id: sweepRestore
            onTriggered: quickSlider.endSweep()
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
            // the whole range. No Behavior here: `value` already glides
            // through the slider's own animation, so the binding is smooth
            // by construction, and a Behavior stacked on an animated source
            // is retargeted every frame of the sweep - the icon sat still
            // for the whole fill and then whipped the turn in one beat.
            rotation: quickSlider.value * 360

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
