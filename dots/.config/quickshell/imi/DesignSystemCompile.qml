import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Process {
        id: finder
        command: ["find", Quickshell.shellPath("modules/common/plugins/designsystem"),
            "-type", "f", "-name", "*.qml", "-print"]
        running: true
        stdout: StdioCollector { id: output }
        onExited: (exitCode, exitStatus) => {
            let failures = 0;
            const paths = output.text.trim().split("\n").filter(path => path.length > 0).concat([
                "nandoroid-clock", "nandoroid-at-a-glance", "nandoroid-media",
                "nandoroid-system-monitor", "nandoroid-weather", "nandoroid-currency"
            ].map(name => Quickshell.shellPath(`modules/common/plugins/bundled/${name}/Widget.qml`))).concat([
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
