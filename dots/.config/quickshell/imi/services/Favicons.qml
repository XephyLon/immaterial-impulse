pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Site icons on disk, fetched once and remembered.
 *
 * The Favicon widget used to spawn curl from inside its own file, which made
 * a 32px image the one shared widget that could open a network connection.
 * The fetch lives here now, the way every other network read in the shell
 * has a service behind it; the widget draws a path it is handed and a flag
 * saying the file is there.
 *
 * `pathFor` is pure - a binding may call it. `request` is the side effect,
 * and a host calls it when it learns a URL it will show.
 */
Singleton {
    id: root

    // path -> true once the file is on disk, false while the fetch runs.
    property var ready: ({})

    function domainOf(url, displayText) {
        return `${url}`.includes("vertexaisearch") ? displayText : StringUtils.getDomain(url);
    }

    function pathFor(url, displayText) {
        return `${Directories.favicons}/${root.domainOf(url, displayText ?? "")}.ico`;
    }

    function request(url, displayText) {
        const path = root.pathFor(url, displayText);
        if (root.ready[path] !== undefined)
            return path;
        const next = Object.assign({}, root.ready);
        next[path] = false;
        root.ready = next;
        const domain = root.domainOf(url, displayText ?? "");
        fetcher.createObject(root, {
            path: path,
            source: `https://www.google.com/s2/favicons?domain=${domain}&sz=32`,
        });
        return path;
    }

    function markReady(path) {
        const next = Object.assign({}, root.ready);
        next[path] = true;
        root.ready = next;
    }

    Component {
        id: fetcher
        Process {
            id: proc
            required property string path
            required property string source
            running: true
            command: ["bash", "-c", '[ -f "$1" ] || curl -s "$2" -o "$1" -L -H "User-Agent: $3"',
                      "bash", proc.path, proc.source, Config.options?.networking.userAgent ?? ""]
            onExited: {
                root.markReady(proc.path);
                proc.destroy();
            }
        }
    }
}
