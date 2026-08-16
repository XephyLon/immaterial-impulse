import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string designSystemRoot: Quickshell.shellPath("modules/common/plugins/designsystem")
    readonly property string bundledRoot: Quickshell.shellPath("modules/common/plugins/bundled")
    // Every settings page, because a settings page only ever compiles when the
    // user opens that page: a bad property or a renamed signal handler on one
    // of them leaves the whole shell green until someone clicks it.
    readonly property string settingsPagesRoot: Quickshell.shellPath("modules/imi/settings/pages")

    Process {
        id: finder
        // Both roots are swept rather than listed. The bundled packages used to
        // be a hardcoded array, which rotted: it still named `nandoroid-clock`
        // and `nandoroid-at-a-glance` long after those directories stopped
        // existing, so every run reported two failures that meant nothing.
        command: ["find", root.designSystemRoot, root.bundledRoot, root.settingsPagesRoot,
            "-type", "f", "-name", "*.qml", "-print"]
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
            const settingsPages = found.filter(path => path.startsWith(root.settingsPagesRoot));

            // A sweep that finds nothing would otherwise pass silently, which is
            // the same failure the hardcoded list had in the other direction.
            if (designSystem.length === 0 || packages.length === 0 || settingsPages.length === 0) {
                console.error(`[DesignSystemCompile] swept nothing: designsystem=${designSystem.length} packages=${packages.length} settingsPages=${settingsPages.length}`);
                Qt.exit(1);
                return;
            }

            const paths = designSystem.concat(packages).concat(settingsPages).concat([
                // The media widget's per-span layouts. A package is otherwise
                // swept through its entry point only, on the reasoning that a
                // sibling file is a type resolved through the package's qmldir.
                // These are not: Widget.qml loads one of them by URL, so each is
                // a standalone component and compiles - or does not - on its own.
                Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-media/Widget.qml"),
                Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-media/MediaTransportButton.qml"),
                Quickshell.shellPath("modules/common/plugins/PluginOptions.qml"),
                // The desktop-widget host. It only compiles once a plugin is
                // enabled on some monitor, so a bad property on it is invisible
                // to a shell whose widgets are all off.
                Quickshell.shellPath("modules/common/plugins/PluginWidget.qml"),
                Quickshell.shellPath("modules/common/widgets/AutostartApps.qml"),
                Quickshell.shellPath("modules/common/widgets/WallpaperSubmenu.qml"),
                // The clock depth picker sits behind an inactive Loader in the
                // wallpaper selector, so it compiles for the first time when
                // someone clicks its toolbar button - which on a shell where
                // nobody has is never.
                Quickshell.shellPath("modules/imi/wallpaperSelector/ClockDepthPicker.qml"),
                // The cheatsheet only compiles when the user presses Super+/,
                // and the keybind editor only when a row's pencil is clicked.
                Quickshell.shellPath("modules/imi/cheatsheet/CheatsheetKeybinds.qml"),
                Quickshell.shellPath("modules/common/widgets/KeybindEditor.qml"),
                Quickshell.shellPath("modules/common/widgets/KeybindChordCapture.qml"),
                // Every bar popup and the one surface they now share. A popup
                // only compiles when its widget is in the user's bar layout,
                // and the plugin ones only when that plugin is enabled, so a
                // bad property on any of them stays invisible until a hover.
                Quickshell.shellPath("modules/common/widgets/StyledPopup.qml"),
                Quickshell.shellPath("modules/imi/bar/BarPopupOverlay.qml"),
                Quickshell.shellPath("modules/imi/bar/ClockWidgetPopup.qml"),
                Quickshell.shellPath("modules/imi/bar/WeatherPopup.qml"),
                Quickshell.shellPath("modules/imi/bar/BatteryPopup.qml"),
                Quickshell.shellPath("modules/imi/bar/ResourcesPopup.qml"),
                Quickshell.shellPath("modules/imi/bar/NetworkSpeedPopup.qml"),
                Quickshell.shellPath("modules/imi/bar/PrivacyIndicatorPopup.qml"),
                Quickshell.shellPath("modules/imi/bar/SysTray.qml"),
                Quickshell.shellPath("modules/imi/bar/DockerPlugin.qml"),
                Quickshell.shellPath("modules/imi/bar/DiscordVoicePlugin.qml"),
                // The generic package bar host, which compiles only once some
                // installed plugin's widget is in the user's bar layout.
                Quickshell.shellPath("modules/imi/bar/PluginBarWidget.qml"),
                // Both bars. The vertical one is the dock's case exactly -
                // bar.vertical defaults false, so a bad property or a missing
                // import in it passes every test and is found by whoever turns
                // it on. The two bars drifting apart unobserved is the whole
                // defect a47462fcc ("fix(verticalBar): render plugin bar
                // widgets instead of an empty stub") came out of.
                Quickshell.shellPath("modules/imi/bar/BarContent.qml"),
                Quickshell.shellPath("modules/imi/verticalBar/VerticalBar.qml"),
                Quickshell.shellPath("modules/imi/verticalBar/VerticalBarContent.qml"),
                Quickshell.shellPath("modules/common/plugins/bundled/docker/DockerPopup.qml"),
                Quickshell.shellPath("modules/common/plugins/bundled/docker/DockerWidget.qml"),
                Quickshell.shellPath("modules/common/plugins/bundled/discordVoice/DiscordVoicePopup.qml"),
                // The dock. It is opt-in - dock.enable defaults to false - so
                // on a shell without it a FINAL override or a missing import in
                // any of these passes every test and is found by whoever
                // switches the dock on. Now that all four edges reach one tree,
                // that is every user of it rather than the ones who moved it.
                Quickshell.shellPath("modules/imi/dock/Dock.qml"),
                Quickshell.shellPath("modules/imi/dock/DockMedia.qml"),
                Quickshell.shellPath("modules/common/widgets/DockButton.qml"),
                Quickshell.shellPath("modules/common/widgets/DockAppButton.qml"),
                Quickshell.shellPath("modules/common/widgets/DockSeparator.qml"),
                Quickshell.shellPath("modules/common/widgets/DockIconMotion.qml"),
                Quickshell.shellPath("modules/common/widgets/DockContextMenu.qml"),
                Quickshell.shellPath("modules/common/widgets/DragApps.qml")
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
