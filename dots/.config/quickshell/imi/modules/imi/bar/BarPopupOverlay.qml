pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets

// One always-mapped layer surface per screen, hosting the single card every bar
// popup morphs. The surface itself never moves, resizes or unmaps: on a
// layer-shell surface position *is* `margins`, so animating a popup along the
// bar reconfigures its surface every frame, which is the create-map-destroy
// loop StyledPopup's imperative positioning already exists to avoid.
//
// The card carries all the motion instead, and `mask: Region { item: card }`
// keeps the rest of the screen click-through. A 0x0 card builds an empty input
// region, which makes Qt mark the whole surface transparent for input - that is
// the invariant that lets a full-screen Overlay surface stay mapped forever.
Scope {
    id: overlayScope

    Variants {
        // Same screen set as both bars: the vertical bar loads the same widget
        // files, so one overlay family entry serves either orientation.
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        PanelWindow {
            id: overlayWindow
            required property ShellScreen modelData

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            // Anchoring all four edges makes this window's coordinate space the
            // screen's, so no bar-edge arithmetic survives at surface level.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Reused deliberately rather than minting a namespace: rules.lua
            // gives quickshell:popup ignore_alpha = 1, which blurs the card's
            // opaque body and skips its translucent shadow. A new namespace
            // would fall through to the catch-all 0.05, under which this
            // surface's transparent pixels ask the compositor to blur the
            // entire screen.
            WlrLayershell.namespace: "quickshell:popup"
            WlrLayershell.layer: WlrLayer.Overlay

            mask: Region {
                item: card
            }

            StyledRectangularShadow {
                target: card
                visible: card.visible
                opacity: card.opacity
            }

            Rectangle {
                id: card
                width: 0
                height: 0
                opacity: 0
                visible: width > 0 && height > 0

                color: Appearance.colors.colLayer1Base
                radius: Appearance.rounding.normal + 4
                border.width: Appearance.borderWidth.standard
                border.color: Appearance.colors.colLayer0Border
            }
        }
    }
}
