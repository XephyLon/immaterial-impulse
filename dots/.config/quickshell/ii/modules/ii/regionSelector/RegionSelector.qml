pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
        GlobalStates.settingsHeldForRegionSelector = false
    }

    function holdSettingsIfOpen() {
        GlobalStates.settingsHeldForRegionSelector = GlobalStates.settingsOpen
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    function screenshot() {
        // While a recording is running, snip with plain grim+slurp instead of
        // opening the region-selector UI (which doubles as the recording control).
        if (Persistent.states.record.enable) {
            const saveDir = Config.options.screenSnip.savePath ?? "";
            if (saveDir !== "") {
                // savePath is config data (reachable by imported presets), so it is
                // passed as an argv element ($1), never interpolated into the script.
                const script = `mkdir -p "$1" && filePath="$1/screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && grim -g "$(slurp)" "$filePath" && wl-copy < "$filePath" && notify-send "Screenshot Saved" "Saved to $filePath" -a "Screen Snip" -i "image-x-generic"`;
                Quickshell.execDetached(["bash", "-c", script, "screen-snip", saveDir]);
            } else {
                const cmd = `grim -g "$(slurp)" - | wl-copy && notify-send "Screenshot Copied" "Copied to clipboard" -a "Screen Snip" -i "image-x-generic"`;
                Quickshell.execDetached(["bash", "-c", cmd]);
            }
            return;
        }
        root.holdSettingsIfOpen()
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function search() {
        root.holdSettingsIfOpen()
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.holdSettingsIfOpen()
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function record() {
        // Already recording: re-run the record script, which stops the recording.
        if (Persistent.states.record.enable) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            return;
        }
        root.holdSettingsIfOpen()
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function recordWithSound() {
        // Already recording: re-run the record script, which stops the recording.
        if (Persistent.states.record.enable) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            return;
        }
        root.holdSettingsIfOpen()
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}