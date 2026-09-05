import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

// The cover-art pipeline shared by every media surface: download the resolved
// artUrl (or use a file:// URL in place), quantize it, and expose the
// displayable path and the palette. This was copy-pasted across the bar,
// dock, sidebar and popup players and had already DRIFTED - the sidebar's copy
// lacked the `curl -4` IPv4 pin (an IPv6 stall hung its downloads) and the
// file:// fast-path (it re-curled local art every track). One copy now.
//
// Feed `artUrl` (typically MediaArt.resolve(...)); read `displayedArtFilePath`
// for an Image source and `colors` for the tint. Each surface keeps its own
// dominant-colour mix, so a per-surface option (the sidebar's artColors gate)
// stays with the surface.
Item {
    id: root

    property var artUrl: ""
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(String(root.artUrl ?? ""))}`
    // True once the art is present locally: a downloaded file, or a file:// URL
    // that needs no download.
    property bool downloaded: false

    readonly property string displayedArtFilePath: {
        if (!root.downloaded) return ""
        const url = String(root.artUrl ?? "")
        if (url.startsWith("file://")) return url
        return Qt.resolvedUrl(root.artFilePath)
    }
    readonly property var colors: colorQuantizer.colors

    onArtUrlChanged: root.refresh()
    Component.onCompleted: root.refresh()
    function refresh() {
        const url = String(root.artUrl ?? "")
        if (url.length === 0) { root.downloaded = false; return }
        // A file:// URL is already on disk: use it in place, no download.
        if (url.startsWith("file://")) { root.downloaded = true; return }
        downloader.targetFile = url
        downloader.filePath = root.artFilePath
        root.downloaded = false
        downloader.running = true
    }

    Process {
        id: downloader
        property string targetFile
        property string filePath
        // Positional args ($1/$2), never spliced into the script body: artUrl
        // is untrusted MPRIS metadata (any bus peer, including a browser tab's
        // Media Session artwork), so interpolating it was a command-injection
        // hole. -4 pins IPv4 (an IPv6 stall hung the download on some
        // networks); -f fails on an HTTP error instead of saving the 404 body
        // as "art", and downloaded follows the exit code for the same reason.
        command: ["bash", "-c", '[ -f "$1" ] || curl -4 -fsSL "$2" -o "$1"', "bash", filePath, targetFile]
        onExited: (exitCode, exitStatus) => root.downloaded = exitCode === 0
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }
}
