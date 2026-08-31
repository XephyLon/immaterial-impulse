pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common.functions
import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // False until scripts/migrate-config-dir.sh has exited. Nothing may read
    // or write `shellConfig` before that: the migration refuses to migrate
    // into a directory that already holds a config.json, so a Config load that
    // got there first used to write its defaults in and permanently disable
    // the move - the user silently kept none of their settings. It was fired
    // with `execDetached`, which returns immediately, so the ordering was a
    // timing accident that happened to hold. `Config.qml` waits on this;
    // `tests/test_config_dir_migration_runtime.py` forces the losing
    // interleaving and checks it does.
    property bool configDirReady: false

    // XDG Dirs, with "file://"
    readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0]
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0]
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0]
    readonly property string genericCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0]
    readonly property string documents: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
    readonly property string downloads: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
    readonly property string pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
    readonly property string music: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0]
    readonly property string videos: StandardPaths.standardLocations(StandardPaths.MoviesLocation)[0]

    // Other dirs used by the shell, without "file://"
    property string assetsPath: Quickshell.shellPath("assets")
    property string scriptPath: Quickshell.shellPath("scripts")
    property string favicons: FileUtils.trimFileProtocol(`${Directories.cache}/media/favicons`)
    property string coverArt: FileUtils.trimFileProtocol(`${Directories.cache}/media/coverart`)
    property string tempImages: "/tmp/quickshell/media/images"
    property string booruPreviews: FileUtils.trimFileProtocol(`${Directories.cache}/media/boorus`)
    property string booruDownloads: FileUtils.trimFileProtocol(Directories.pictures  + "/homework")
    property string booruDownloadsNsfw: FileUtils.trimFileProtocol(Directories.pictures + "/homework/🌶️")
    property string latexOutput: FileUtils.trimFileProtocol(`${Directories.cache}/media/latex`)
    // Stills of the active Wallpaper Engine project, grabbed off the live
    // surface for the SDDM greeter (which cannot run Wallpaper Engine itself).
    // Unlike the media caches below it is NOT wiped at startup: the greeter
    // reads it while the shell is not running, and re-grabbing costs a frame
    // only when a wallpaper is actually applied.
    property string wallpaperEngineStills: FileUtils.trimFileProtocol(`${Directories.cache}/wallpaperengine-stills`)
    property string shellConfig: FileUtils.trimFileProtocol(`${Directories.config}/immaterial-impulse`)
    // The suite checkout get.sh installs/updates (same resolution as its DEST)
    property string suiteSrc: (Quickshell.env("XDG_DATA_HOME") || `${FileUtils.trimFileProtocol(Directories.home)}/.local/share`) + "/immaterial-impulse/src"
    property string shellConfigName: "config.json"
    property string shellConfigPath: `${Directories.shellConfig}/${Directories.shellConfigName}`
	property string todoPath: FileUtils.trimFileProtocol(`${Directories.state}/user/todo.json`)
	// The note store: a JSON array owned by services/Notes.qml, which the bundled
	// notes plugin and the overlay notes editor both go through. Still named
	// .txt because it used to hold one plaintext scratchpad, and renaming it
	// would strand that scratchpad in a file nothing reads.
	property string notesPath: FileUtils.trimFileProtocol(`${Directories.state}/user/notes.txt`)
	property string clipboardPinsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/clipboard-pins.json`)
	// Launch history for the launcher's frecency ranking, owned by
	// services/AppUsage.qml. State rather than config: it is derived from what
	// the user does, holds nothing they typed, and losing it costs a few days
	// of relearning rather than any of their settings.
	property string appUsagePath: FileUtils.trimFileProtocol(`${Directories.state}/user/app-usage.json`)
	// Where the deleted built-in notes widget kept its note array. Imported into
	// notesPath once (Config.options.notes.importedLegacyStore) and never
	// written to again - it stays on disk as the user's copy of record.
	property string desktopNotesPath: FileUtils.trimFileProtocol(`${Directories.state}/user/desktopnotes.txt`)
	property string conflictCachePath: FileUtils.trimFileProtocol(`${Directories.cache}/conflict-killer`)
    property string notificationsPath: FileUtils.trimFileProtocol(`${Directories.cache}/notifications/notifications.json`)
    property string generatedMaterialThemePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/colors.json`)
    property string generatedWallpaperCategoryPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/wallpaper/category.txt`)
    property string cliphistDecode: FileUtils.trimFileProtocol(`/tmp/quickshell/media/cliphist`)
    property string screenshotTemp: "/tmp/quickshell/media/screenshot"
    property string wallpaperSwitchScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/switchwall.sh`)
    property string defaultAiPrompts: Quickshell.shellPath("defaults/ai/prompts")
    property string userAiPrompts: FileUtils.trimFileProtocol(`${Directories.shellConfig}/ai/prompts`)
    property string userActions: FileUtils.trimFileProtocol(`${Directories.shellConfig}/actions`)
    property string aiChats: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats`)
    property string aiSessions: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats/sessions`)
    // Durable copies of chat attachments: cliphist's decode dir is a /tmp
    // cache that vanishes underneath a message, which is how a request went
    // out pointing at a file that no longer existed.
    property string aiAttachments: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/attachments`)
    property string aiTranslationScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/gemini-translate.sh`)
    property string iconThemeScanScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/icons/scan-icon-themes.py`)
    property string iconThemeApplyScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/icons/apply-icon-theme.sh`)
    property string cursorThemeScanScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/cursor/scan-cursor-themes.py`)
    property string cursorThemeApplyScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/cursor/apply-cursor-theme.sh`)
    property string soundThemeScanScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/sounds/scan-sound-themes.py`)
    property string recordScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/record.sh`)
    property string userAvatarPathAccountsService: FileUtils.trimFileProtocol(`/var/lib/AccountsService/icons/${SystemInfo.username}`)
    property string userAvatarPathRicersAndWeirdSystems: FileUtils.trimFileProtocol(`${Directories.home}.face`)
    property string userAvatarPathRicersAndWeirdSystems2: FileUtils.trimFileProtocol(`${Directories.home}.face.icon`)
    property string userPresetsPath: FileUtils.trimFileProtocol(`${Directories.shellConfig}/presets`)
    property string presetsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/presets.sh`)
    property string generatedLockMaterialThemePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/colors-lock.json`)

    // A Process rather than `execDetached` purely so there is an exit to wait
    // for. It costs one bash spawn on the startup path of every launch, which
    // buys a happens-before instead of a coincidence.
    Process {
        id: configDirMigration
        command: ["bash", Quickshell.shellPath("scripts/migrate-config-dir.sh")]
        stderr: SplitParser {
            onRead: line => console.log(line)
        }
        onExited: (exitCode, exitStatus) => {
            // 3 is the script's DECLINED: it found something it could not
            // safely decide and deliberately changed nothing. Its own stderr
            // above says which directory and why; this line is here so the
            // headline is greppable and cannot be mistaken for noise.
            if (exitCode === 3)
                console.log("[Directories] Your settings were not migrated. The shell left both config directories untouched - see the [ImI] line above for which one still holds them.");
            else if (exitCode !== 0)
                console.log(`[Directories] scripts/migrate-config-dir.sh exited ${exitCode}; continuing with whatever is in ${root.shellConfig}.`);
            root.configDirReady = true;
        }
    }

    // Deliberately not in Component.onCompleted: these three live inside
    // `shellConfig`, and creating them before the migration has run is how the
    // rename loses to a directory appearing underneath it.
    onConfigDirReadyChanged: {
        if (!root.configDirReady)
            return;
        Quickshell.execDetached(["mkdir", "-p", `${root.shellConfig}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.userPresetsPath}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.userActions}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.aiAttachments}`])
    }

    // Cleanup on init
    Component.onCompleted: {
        configDirMigration.running = true
        Quickshell.execDetached(["mkdir", "-p", `${favicons}`])
        // Created, never cleared - see the property. Without this the greeter's
        // still has nowhere to land and saveToFile fails silently.
        Quickshell.execDetached(["mkdir", "-p", `${wallpaperEngineStills}`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${coverArt}'; mkdir -p '${coverArt}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${booruPreviews}'; mkdir -p '${booruPreviews}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${latexOutput}'; mkdir -p '${latexOutput}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${cliphistDecode}'; mkdir -p '${cliphistDecode}'`])
        Quickshell.execDetached(["mkdir", "-p", `${aiChats}`])
        Quickshell.execDetached(["mkdir", "-p", `${aiSessions}`])
        Quickshell.execDetached(["rm", "-rf", `${tempImages}`])
    }
}
