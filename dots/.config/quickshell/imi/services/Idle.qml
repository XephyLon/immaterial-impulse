pragma Singleton
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../modules/common/functions/monitorDetection.js" as MonitorDetection

/**
 * Keep-awake (idle inhibitor) state.
 *
 * Three inputs are ORed into the actual Wayland inhibitor:
 * - `inhibit`: the manual "Keep system awake" toggle (persisted per Hyprland
 *   instance via Persistent.states.idle.inhibit).
 * - auto keep-awake (ported from end-4/dots-hyprland PR #2109): while
 *   Config.options.idleInhibitor.autoOnExternalMonitor is enabled and any
 *   external monitor is connected, the inhibitor is held active regardless of
 *   the manual toggle. The manual toggle only ever controls its own bit, so
 *   switching it off while a monitor is connected is honored (no forced
 *   re-toggle); the automatic part is stopped by unplugging the monitor or
 *   disabling the config option.
 * - `screensaverHold`: a monitor the user deliberately blanked. Each input owns
 *   its own bit and none of them writes another's, so a deliberate blank cannot
 *   flip the manual toggle back on the way out.
 */
Singleton {
    id: root

    // Manual toggle. Deliberately NOT an alias of idleInhibitor.enabled
    // anymore: the inhibitor's enabled state is the OR below.
    property bool inhibit: false

    readonly property bool autoOnExternalMonitor: Config.options.idleInhibitor.autoOnExternalMonitor
    readonly property bool hasExternalMonitor: MonitorDetection.hasExternal(Quickshell.screens.map(s => s.name))
    readonly property bool autoInhibitActive: root.autoOnExternalMonitor && root.hasExternalMonitor

    // A monitor blanked on purpose keeps hypridle's ladder (lock 300s, DPMS off
    // 600s, suspend 900s) from running out from under a user who is working on
    // another screen. An *idle*-raised screensaver deliberately holds nothing:
    // there the ladder is the point.
    //
    // Derived from the screen list rather than stored as a flag the screensaver
    // sets and clears, because a stored bit has a release path to get wrong and
    // this has none. If the shell dies while a monitor is blanked the inhibitor
    // goes with it either way - a zwp_idle_inhibitor is destroyed with the
    // wl_surface it was created on, and the client's surfaces die with the
    // connection, so the compositor drops the inhibit without anyone asking.
    readonly property bool screensaverHold: GlobalStates.screensaverScreens.length > 0

    readonly property bool effectiveInhibit: root.inhibit || root.autoInhibitActive || root.screensaverHold

    onAutoInhibitActiveChanged: {
        // Only announce when the automatic part actually changes the effective
        // state (i.e. the manual toggle wasn't already keeping the system awake).
        if (root.autoInhibitActive && !root.inhibit) {
            Quickshell.execDetached([
                "notify-send",
                Translation.tr("Keep system awake"),
                Translation.tr("External monitor detected"),
                "-a", "Shell",
                "-i", "video-display",
                "-t", "3000",
            ]);
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.inhibit;
            }
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // Touched from shell.qml on startup so the auto keep-awake logic runs even
    // before any UI (quick toggles, lock screen) references this singleton.
    function load() { }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.effectiveInhibit
        // A zwp_idle_inhibitor only takes effect while its surface is actually
        // mapped. A 0x0 window maps unreliably, so Hyprland's ext-idle-notify
        // (which hypridle reads) would sometimes ignore the inhibitor and the
        // session locked/hibernated anyway. Give it a reliably-mapped 1x1
        // transparent, input-transparent surface on the background layer so it
        // is present but never seen or interactable.
        window: PanelWindow {
            implicitWidth: 1
            implicitHeight: 1
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:idleInhibitor"
            anchors {
                right: true
                bottom: true
            }
            // Input-transparent: clicks pass straight through.
            mask: Region {
                item: null
            }
        }
    }
}
