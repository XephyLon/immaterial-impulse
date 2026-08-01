pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.services

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound,
        RecordFullscreenWithSound,
        QRCode
    }

    property string imageSearchEngineBaseUrl: (Config.ready && Config.options?.search?.imageSearch?.imageSearchEngineBaseUrl) ? Config.options.search.imageSearch.imageSearchEngineBaseUrl : "https://lens.google.com/uploadbyurl?url="
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        
        const shellEscape = Functions.StringUtils.shellSingleQuoteEscape;
        
        const cropBase = `magick ${shellEscape(screenshotPath)} `
            + `-crop ${rw}x${rh}+${rx}+${ry}`
        const cropToStdout = `${cropBase} -`
        const cropInPlace = `${cropBase} '${shellEscape(screenshotPath)}'`
        const cleanup = `rm '${shellEscape(screenshotPath)}'`
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`
        
        const uploadAndGetUrl = (filePath) => {
            return `curl -sF files[]=@'${shellEscape(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url'`
        }
        
        const useSatty = (Config.ready && Config.options.regionSelector && Config.options.regionSelector.annotation) 
            ? Config.options.regionSelector.annotation.useSatty 
            : false;
        const annotationCommand = `${useSatty ? "satty" : "swappy"} -f -`;
        const recordScript = Quickshell.shellPath("scripts/videos/record.sh");
        


        switch (action) {
            case ScreenshotAction.Action.Copy:
                const autoSave = (Config.ready && Config.options.screenshot) ? Config.options.screenshot.autoSave : true;
                const autoCopy = (Config.ready && Config.options.screenshot) ? Config.options.screenshot.autoCopy : true;
                const rawSaveDir = (Config.ready && Config.options.screenshot) ? Config.options.screenshot.savePath : "~/Pictures/Screenshots";
                const finalSaveDir = Functions.FileUtils.trimFileProtocol(rawSaveDir);
                
                if (!autoSave || saveDir === "temp") {
                    // Just move to temp and conditionally auto-copy to clipboard
                    const copyCmd = autoCopy ? `${cropToStdout} | wl-copy && ` : "";
                    return ["bash", "-c", `${copyCmd}${cropInPlace}`]
                }
                
                const teeCopy = autoCopy ? " | tee >(wl-copy)" : "";
                return [
                    "bash", "-c",
                    `mkdir -p '${shellEscape(finalSaveDir)}' && \
                    saveFileName="Screenshot_$(date '+%Y-%m-%d-%H-%M-%S').png" && \
                    savePath="${finalSaveDir}/$saveFileName" && \
                    ${cropToStdout}${teeCopy} > "$savePath" && \
                    ${cleanup}`
                ]

            case ScreenshotAction.Action.Edit:
                return ["bash", "-c", `${cropToStdout} | ${annotationCommand} && ${cleanup}`]
                
            case ScreenshotAction.Action.Search:
                const uploadCmd = uploadAndGetUrl(screenshotPath);
                return ["bash", "-c", `${cropInPlace} && IMG_LINK=$(${uploadCmd}) && [ -n "$IMG_LINK" ] && xdg-open "${root.imageSearchEngineBaseUrl}$IMG_LINK" && ${cleanup}`]
                
            case ScreenshotAction.Action.CharRecognition:
                return ["bash", "-c", `${cropInPlace} && tesseract '${shellEscape(screenshotPath)}' stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | wl-copy && ${cleanup}`]
                
            case ScreenshotAction.Action.Record:
                const recPath = (Config.ready && Config.options.screenshot) ? Config.options.screenshot.recordPath : "~/Videos/Recordings";
                return ["bash", "-c", `'${recordScript}' --region '${slurpRegion}' --path '${shellEscape(recPath)}'`]
                
            case ScreenshotAction.Action.RecordWithSound:
                const recPathS = (Config.ready && Config.options.screenshot) ? Config.options.screenshot.recordPath : "~/Videos/Recordings";
                return ["bash", "-c", `'${recordScript}' --region '${slurpRegion}' --sound --path '${shellEscape(recPathS)}'`]
            
            case ScreenshotAction.Action.RecordFullscreenWithSound:
                const recPathF = (Config.ready && Config.options.screenshot) ? Config.options.screenshot.recordPath : "~/Videos/Recordings";
                return ["bash", "-c", `'${recordScript}' --fullscreen --sound --path '${shellEscape(recPathF)}'`]

            case ScreenshotAction.Action.QRCode:
                return ["bash", "-c", `${cropInPlace} && zbarimg --raw '${shellEscape(screenshotPath)}' | wl-copy && notify-send "QR Code" "Content copied to clipboard" && ${cleanup}`]
                
            default:

                return [];
        }
    }
}
