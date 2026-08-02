import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string designSystemRoot: Quickshell.shellPath("modules/common/plugins/designsystem")
    readonly property string bundledRoot: Quickshell.shellPath("modules/common/plugins/bundled")

    Process {
        id: finder
        // Both roots are swept rather than listed. The bundled packages used to
        // be a hardcoded array, which rotted: it still named `nandoroid-clock`
        // and `nandoroid-at-a-glance` long after those directories stopped
        // existing, so every run reported two failures that meant nothing.
        command: ["find", root.designSystemRoot, root.bundledRoot, "-type", "f", "-name", "*.qml", "-print"]
        running: true
        stdout: StdioCollector { id: output }
        onExited: (exitCode, exitStatus) => {
            let failures = 0;
            const found = output.text.trim().split("\n").filter(path => path.length > 0);
            // Every design-system file is checked; a bundled package is checked
            // through its entry point only, since a multi-file package's
            // siblings are types resolved via its qmldir rather than
            // standalone components.
            const designSystem = found.filter(path => path.startsWith(root.designSystemRoot));
            const packages = found.filter(path => path.startsWith(root.bundledRoot)
                && path.endsWith("/Widget.qml"));

            // A sweep that finds nothing would otherwise pass silently, which is
            // the same failure the hardcoded list had in the other direction.
            if (designSystem.length === 0 || packages.length === 0) {
                console.error(`[DesignSystemCompile] swept nothing: designsystem=${designSystem.length} packages=${packages.length}`);
                Qt.exit(1);
                return;
            }

            const paths = designSystem.concat(packages).concat([
                Quickshell.shellPath("modules/common/plugins/PluginOptions.qml"),
                Quickshell.shellPath("modules/imi/settings/pages/PluginsPage.qml")
            ]);
            for (const path of paths) {
                const component = Qt.createComponent(`file://${path}`, Component.PreferSynchronous);
                if (component.status !== Component.Ready) {
                    failures++;
                    console.error(`[DesignSystemCompile] ${path}: ${component.errorString()}`);
                }
            }
            console.log(`[DesignSystemCompile] checked=${paths.length} failures=${failures}`);
            Qt.exit(failures === 0 ? 0 : 1);
        }
    }
}
