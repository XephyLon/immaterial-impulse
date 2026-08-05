pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// Keeps the SDDM greeter's inputs in step with the desktop, reactively.
//
// The greeter used to be refreshed only as a side effect of color generation
// (matugen's post_hook), so anything that changed the generated Settings.qml
// without changing colors - WE scaling, clock style - went stale until the
// next wallpaper switch, and the still grabbed after a scene switch could
// land AFTER the copy and miss the login screen entirely.
//
// This service observes the greeter-relevant config leaves directly, and is
// poked by Background.captureGreeterStill when a still finishes writing - the
// grab's completion is an observed event, which is what closes that race.
//
// What it runs is the SATELLITE's sync wrapper, not the root apply script:
// the wrapper generates Settings.qml, hashes the greeter-consumed outputs and
// only escalates to the privileged copy when something actually changed. That
// diff gate is what makes observation cheap to be generous with - an
// over-observed leaf costs a hash, not a root copy. Absent wrapper (machine
// without the SDDM theme, or a satellite older than the wrapper) = silent
// no-op; matugen's post_hook still covers those installs the old way.
Singleton {
    id: root

    readonly property string syncScript: FileUtils.trimFileProtocol(
        `${Directories.config}/imi-sddm-theme/sddm-theme-sync.sh`)

    // Public entry point: anything that changes what the greeter shows calls
    // this. Debounced, because the leaves below often change in bursts (a
    // wallpaper switch writes four of them back to back).
    function request() {
        if (!Config.ready) return;
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 1500
        onTriggered: {
            // Serialize: a run arriving while one is in flight waits a full
            // debounce rather than stacking a second wrapper process.
            if (sync.running) { debounce.restart(); return; }
            sync.running = true;
        }
    }

    Process {
        id: sync
        // Existence-checked at fire time, not bound at load: the wrapper
        // appears when the satellite installs it, which can happen while the
        // shell is up.
        command: ["bash", "-c",
            `[ -f "${root.syncScript}" ] && exec bash "${root.syncScript}" || exit 0`]
        onExited: exitCode => {
            if (exitCode !== 0)
                console.log("[GreeterSync] sync wrapper exited", exitCode);
        }
    }

    // The observed leaves. Over-observation is tolerable (the wrapper's diff
    // gate turns a spurious fire into a hash comparison); UNDER-observation is
    // the staleness bug this service exists to end, so when in doubt, add the
    // leaf.
    Connections {
        target: Config.options.wallpaperSelector.wallpaperEngine
        function onActiveProjectChanged() { root.request(); }
        function onActivePathChanged() { root.request(); }
        function onActiveTypeChanged() { root.request(); }
        function onActivePreviewChanged() { root.request(); }
        function onScalingChanged() { root.request(); }
    }
    Connections {
        target: Config.options.background
        function onWallpaperPathChanged() { root.request(); }
    }
}
