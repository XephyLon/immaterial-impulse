pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "./avatar_source.js" as AvatarSource

/**
 * The one answer to "which picture is the user's avatar".
 *
 * Four widgets (the bar's media popup, the right sidebar's header, the
 * settings header, the user-card desktop widget) each used to spell the same
 * fallback - `file:///home/$USER/.face` - and on a machine with no ~/.face
 * every rebuild of any of them retried the missing file and warned. The two
 * ricer-convention files are stat'ed once here, at construction, and a
 * missing one resolves to "" so the widgets draw their glyph fallback
 * instead of retrying a file that is not there.
 */
Singleton {
    id: root

    property bool faceExists: false
    property bool faceIconExists: false

    readonly property string url: AvatarSource.resolve(
        Config.options.profile.avatarPath,
        Config.options.profile.avatarPicture,
        FileUtils.trimFileProtocol(Directories.home),
        root.faceExists,
        root.faceIconExists)

    Process {
        running: true
        command: ["bash", "-c", 'f=0; i=0; [ -f "$HOME/.face" ] && f=1; [ -f "$HOME/.face.icon" ] && i=1; echo "$f $i"']
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ")
                root.faceExists = parts[0] === "1"
                root.faceIconExists = parts[1] === "1"
            }
        }
    }
}
