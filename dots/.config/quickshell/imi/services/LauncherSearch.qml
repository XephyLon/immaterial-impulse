pragma Singleton

import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

Singleton {
    id: root

    property string query: ""

    // Drive the file-search scan imperatively (never from the results binding,
    // which would loop). Only scans while a file-prefixed query is active.
    onQueryChanged: {
        const filePrefix = Config.options.search.prefix.file ?? "~";
        if (root.query.startsWith(filePrefix))
            FileSearch.search(StringUtils.cleanPrefix(root.query, filePrefix));
        else
            FileSearch.reset();
    }

    // One shape for a modpack result, built in both places that need it: the
    // prefix branch (which lists every instance) and the default results
    // (which mixes matching instances in with apps, so Super + a pack name is
    // enough - the prefix is for browsing, not a requirement).
    function makePrismResult(instance) {
        const versionLine = [instance.minecraftVersion, instance.loader].filter(part => part.length > 0).join(" · ");
        return resultComp.createObject(null, {
            id: instance.id,
            name: instance.name,
            comment: versionLine,
            verb: Translation.tr("Play"),
            type: Translation.tr("Modpack"),
            // Prism writes instance icons as files, so the icon is a path, not
            // an icon-theme name; empty means the pack uses a Prism built-in
            // with nothing on disk, and the Material fallback covers it.
            iconName: instance.icon.length > 0 ? instance.icon : "stadia_controller",
            iconType: instance.icon.length > 0 ? LauncherSearchResult.IconType.File : LauncherSearchResult.IconType.Material,
            execute: () => {
                PrismLauncher.launch(instance);
            }
        });
    }

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.symbols, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch,].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }
    
    Process {
        id: keywordHarvester
        property var pendingPages: []
        property string currentPageName: ""
        
        function startHarvesting() {
            root.settingsKeywordsCache = {}; 
            pendingPages = root.settingsIndex.slice();
            next();
        }

        function next() {
            if (pendingPages.length === 0) {
                return;
            }
            
            let currentPage = pendingPages.shift();
            let fullPath = FileUtils.trimFileProtocol(
                Quickshell.shellPath("modules/imi/settings/pages/" + currentPage.path)
            )

            let rawCommand = "grep -oP \"title:\\s*Translation.tr\\(['\\\"].*?['\\\"]\\)\" " + fullPath + " | sed -E \"s/title:\\s*Translation.tr\\(['\\\"](.*)['\\\"]\\)/\\1/g\" | tr '\\n' ' '";
            
            command = ["bash", "-c", rawCommand];
            
            keywordHarvester.currentPageName = currentPage.page;
            running = true;
        }

        onExited: (exitCode, exitStatus) => {
            keywordHarvester.next();
        }

        stdout: SplitParser {
            onRead: data => {
                let cache = root.settingsKeywordsCache;
                cache[keywordHarvester.currentPageName] = (cache[keywordHarvester.currentPageName] || "") + " " + data;
                root.settingsKeywordsCache = cache;
            }
        }
    }

    Component.onCompleted: {
        keywordHarvester.startHarvesting();
        // Constructs the Prism service so its detection runs now rather than
        // on the user's first keystroke - see the note on reload().
        PrismLauncher.reload();
    }


    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    property var settingsKeywordsCache: ({})

    // One entry per page SettingsContent actually declares, named exactly as it
    // names them. Three of the eight entries this replaces ("Bar", "Desktop",
    // "Interface") matched no page in that catalogue, so their results opened
    // the settings window on whatever page was last shown; "Interface" also
    // pointed the keyword harvest at InterfaceConfig.qml, which has not existed
    // for some time - a grep over a missing file exits non-zero with no output,
    // and the harvester ignores its exit code, so that page contributed no
    // section keywords and said nothing about it.
    property var settingsIndex: [
        { page: "Quick",               path: "QuickConfig.qml" },
        { page: "Appearance",          path: "AppearanceConfig.qml" },
        { page: "Cursor",              path: "CursorConfig.qml" },
        { page: "Wallpaper & Desktop", path: "BackgroundConfig.qml" },
        { page: "Bar & Dock",          path: "BarConfig.qml" },
        { page: "Sidebars & Panels",   path: "SidebarsPanelsConfig.qml" },
        { page: "Notifications",       path: "NotificationsConfig.qml" },
        { page: "Lock & Idle",         path: "LockIdleConfig.qml" },
        { page: "Capture",             path: "CaptureConfig.qml" },
        { page: "General",             path: "GeneralConfig.qml" },
        { page: "Services",            path: "ServicesConfig.qml" },
        { page: "Widgets",             path: "PluginsPage.qml" },
        { page: "Hyprland",            path: "HyprlandConfig.qml" },
        { page: "About",               path: "About.qml" },
    ]

    // Load user action scripts from ~/.config/immaterial-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                Hyprland.dispatch("global quickshell:wallpaperSelectorToggle")
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Cliphist.wipe();
            }
        },
        {
            action: "unsplash",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("Usage: /unsplash YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "unsplash"], args.trim());
                Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "wallhaven",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("Usage: /wallhaven YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "wallhaven"], args.trim());
                Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "pexels",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("Usage: /pexels YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "pexels"], args.trim());
                Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    property string mathResult: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    property list<var> results: {
        // Search results are handled here
        ////////////////// Skip? //////////////////
        if (root.query == "")
            return [];

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            const makeClipboardResult = (entry, pinned, shouldBlurImage) => {
                const type = `${pinned ? Translation.tr("Pinned") + " " : ""}#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: type,
                    execute: () => {
                        Cliphist.copy(entry);
                    },
                    actions: [resultComp.createObject(null, {
                            name: pinned ? Translation.tr("Unpin") : Translation.tr("Pin"),
                            iconName: pinned ? "keep_off" : "keep",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.togglePin(entry);
                            }
                        }), resultComp.createObject(null, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }), resultComp.createObject(null, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })],
                    blurImage: shouldBlurImage
                });
            };
            // Pinned entries always shown first, filtered by the search string.
            const search = searchString.trim().toLowerCase();
            const pinnedResults = Cliphist.livePinnedEntries
                .filter(p => search === "" || p.name.toLowerCase().includes(search))
                .map(p => makeClipboardResult(p.entry, true, p.image && root.clipboardWorkSafetyActive));
            // Unpinned live entries, skipping any that are already pinned to avoid duplicates.
            const unpinnedResults = Cliphist.fuzzyQuery(searchString)
                .filter(entry => !Cliphist.pinnedHashes.includes(Cliphist.contentHash(entry)))
                .map((entry, index, array) => {
                    const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                    let shouldBlurImage = mightBlurImage;
                    if (mightBlurImage) {
                        shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                    }
                    return makeClipboardResult(entry, false, shouldBlurImage);
                });
            return pinnedResults.concat(unpinnedResults).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            // Emojis
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: entry.replace(/^\s*\S+\s+/, ""),
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                    }
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.keybinds ?? "<")) {
            // Keybinds
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.keybinds ?? "<");
            const flatBinds = (function flatten(node) {
                let result = [...(node.keybinds ?? [])];
                for (const child of (node.children ?? [])) {
                    result = result.concat(flatten(child));
                }
                return result;
            })(HyprlandKeybinds.keybinds);

            return flatBinds.filter(bind => {
                if (!bind.comment) return false;
                if (searchString.length === 0) return true;
                return bind.comment.toLowerCase().includes(searchString.toLowerCase())
                    || bind.key.toLowerCase().includes(searchString.toLowerCase());
            }).map(bind => {
                const modsStr = bind.mods.join(" + ");
                const keyStr  = modsStr.length > 0 ? `${modsStr} + ${bind.key}` : bind.key;
                return resultComp.createObject(null, {
                    name: bind.comment,
                    iconName: "keyboard",
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: keyStr,
                    type: Translation.tr("Keybind"),
                    comment: keyStr,
                    execute: () => {
                        Quickshell.clipboardText = keyStr;
                    }
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.file ?? "~")) {
            // File / folder search. The scan is kicked imperatively from
            // onQueryChanged (NOT here) - calling search() inside this binding
            // would re-trigger it every time FileSearch.results updates, an
            // infinite scan loop. This binding only maps the latest results.
            return FileSearch.results.map(entry => {
                const path = FileUtils.trimFileProtocol(entry.path);
                const isDir = entry.isDir;
                const displayName = isDir ? FileUtils.folderNameForPath(path) : FileUtils.fileNameForPath(path);
                const parentDir = FileUtils.parentDirectory(path);
                return resultComp.createObject(null, {
                    rawValue: path,
                    name: displayName || path,
                    comment: path,
                    verb: Translation.tr("Open"),
                    type: isDir ? Translation.tr("Folder") : Translation.tr("File"),
                    iconName: isDir ? "folder" : "description",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        Quickshell.execDetached(["xdg-open", path]);
                    },
                    actions: [resultComp.createObject(null, {
                            name: Translation.tr("Open parent folder"),
                            iconName: "folder_open",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                if (parentDir)
                                    Quickshell.execDetached(["xdg-open", parentDir]);
                            }
                        })]
                });
            }).filter(Boolean);
        } else if (PrismLauncher.available && root.query.startsWith(Config.options.search.prefix.prism ?? "%")) {
            // Prism Launcher modpacks. Gated on `available` rather than only on
            // the prefix: without Prism installed the prefix is a normal
            // character again, so typing it still reaches the default results
            // instead of dead-ending in an empty branch.
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.prism ?? "%");
            return PrismLauncher.fuzzyQuery(searchString).map(instance => root.makePrismResult(instance)).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.symbols)) {
            // Material Symbols
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.symbols);
            return MaterialSymbolsSearch.fuzzyQuery(searchString).map(entry => {
                const tabIdx = entry.indexOf("\t");
                const symName = tabIdx >= 0 ? entry.slice(0, tabIdx) : entry;
                const symTags = tabIdx >= 0 ? entry.slice(tabIdx + 1) : "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: symName,
                    iconName: symName,
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Symbol"),
                    comment: symTags,
                    execute: () => {
                        Quickshell.clipboardText = symName;
                    }
                });
            }).filter(Boolean);
        }

        ////////////////// Init ///////////////////
        nonAppResultsTimer.restart();
        const mathResultObject = resultComp.createObject(null, {
            name: root.mathResult,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        });
        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => {
            return resultComp.createObject(null, {
                type: Translation.tr("App"),
                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    if (!entry.runInTerminal)
                        entry.execute();
                    else {
                        // Probably needs more proper escaping, but this will do for now
                        Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
                    }
                },
                comment: entry.comment,
                runInTerminal: entry.runInTerminal,
                genericName: entry.genericName,
                keywords: entry.keywords,
                actions: entry.actions.map(action => {
                    return resultComp.createObject(null, {
                        name: action.name,
                        iconName: action.icon,
                        iconType: LauncherSearchResult.IconType.System,
                        execute: () => {
                            if (!action.runInTerminal)
                                action.execute();
                            else {
                                Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(action.command.join(' '))}'`]);
                            }
                        }
                    });
                })
            });
        });
        // Matching modpacks, mixed into the default results so the prefix is
        // optional. Unprefixed only - a query carrying some other source's
        // prefix is not asking for packs.
        const prismResultObjects = PrismLauncher.available
            ? PrismLauncher.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(instance => root.makePrismResult(instance)).filter(Boolean)
            : [];

        ////////////////// Settings search //////////////////
        const settingsQuery = root.query.toLowerCase().trim();

        const settingsResults = root.settingsIndex.reduce((acc, page) => {
            const dynamicKeywords = (root.settingsKeywordsCache[page.page] || "").toLowerCase();
            const query = root.query.toLowerCase().trim();
            if (query === "") return acc;

            if (page.page.toLowerCase().includes(query) || dynamicKeywords.includes(query)) {
                acc.push(resultComp.createObject(null, {
                    name: page.page,
                    comment: dynamicKeywords.includes(query) ? "Section: " + query : "Settings for " + page.page,
                    verb: Translation.tr("Go"),
                    type: Translation.tr("Settings"),
                    iconName: "settings",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        GlobalStates.settingsOpen = true;
                        Qt.callLater(() => {
                            GlobalStates.settingsPage = page.page + ":" + query;
                        });
                        root.query = "";
                    }
                }));
            }
            return acc;
        }, []);
        const commandResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", ""),
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let cleanedCommand = root.query.replace("file://", "");
                cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                    cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                }
                Quickshell.execDetached(["bash", "-c", root.query.startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand]);
            }
        });
        const webSearchResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch),
            verb: Translation.tr("Search"),
            type: Translation.tr("Web search"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch);
                let url = Config.options.search.engineBaseUrl + query;
                for (let site of Config.options.search.excludedSites) {
                    url += ` -site:${site}`;
                }
                Qt.openUrlExternally(url);
            }
        });
        const launcherActionObjects = root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            if (actionString.startsWith(root.query) || root.query.startsWith(actionString)) {
                return resultComp.createObject(null, {
                    name: root.query.startsWith(actionString) ? root.query : actionString,
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Action"),
                    iconName: 'settings_suggest',
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        action.execute(root.query.split(" ").slice(1).join(" "));
                    }
                });
            }
            return null;
        }).filter(Boolean);

        //////// Prioritized by prefix /////////
        let result = [];
        const startsWithNumber = /^\d/.test(root.query);
        const startsWithMathPrefix = root.query.startsWith(Config.options.search.prefix.math);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
        }

        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);
        //////////////// Modpacks //////////////
        // Ahead of settings and actions, behind apps: launching a pack is the
        // same kind of intent as launching an app, and a pack name is specific
        // enough that a match is rarely accidental. Inert without Prism.
        result = result.concat(prismResultObjects);
        ////////////// Settings ////////////////
        result = result.concat(settingsResults);
        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        /// Math result, command, web search ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!startsWithNumber && !startsWithMathPrefix)
                result.push(mathResultObject);
            if (!startsWithWebSearchPrefix)
                result.push(webSearchResultObject);
        }
        
        return result;
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
