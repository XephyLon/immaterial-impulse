.pragma library

// The Apply popup's partition of a preset, and the resolver that turns a
// selection into `presets.sh --only` specs. ONE table: the popup reads it
// for rows, the resolver reads it for the script, so the two cannot drift.
//
// A spec is either a top-level config key ("background"), an appearance
// subsection spelled "appearance:<sub>" (the script deep-merges those over
// the live appearance rather than replacing it), or "_pluginState".
//
// The commands group is the injection fence (spec 2026-08-31): apps.* are
// shell-executed strings, so with online presets planned they are NEVER
// preselected, and "select all" means "all but commands".

var GROUPS = [
    { id: "wallpaper", icon: "wallpaper", label: "Wallpaper & background",
      defaultOn: true, sections: ["background", "wallpaperSelector"] },
    { id: "theming", icon: "palette", label: "Colors & theming",
      defaultOn: true, sections: ["appearance.palette", "appearance.autoTheme",
        "appearance.wallpaperTheming", "appearance.transparency",
        "appearance.extraBackgroundTint", "appearance.fakeScreenRounding", "light"] },
    { id: "fonts", icon: "text_fields", label: "Fonts & icons",
      defaultOn: true, sections: ["appearance.fonts", "appearance.iconTheme",
        "appearance.clockFonts", "appearance.terminal"] },
    { id: "panels", icon: "toolbar", label: "Bar, dock & sidebars",
      defaultOn: true, sections: ["bar", "dock", "sidebar", "tray", "osd",
        "overview", "panelFamily"] },
    { id: "widgets", icon: "widgets", label: "Desktop widgets",
      defaultOn: true, sections: ["_pluginState", "plugins", "appearance.clock",
        "appearance.atAGlance", "appearance.mediaWidget", "appearance.currencyWidget",
        "appearance.weatherWidget", "appearance.systemMonitor", "appearance.openrgb",
        "appearance.motion", "appearance.lyrics"] },
    { id: "rest", icon: "tune", label: "Everything else",
      defaultOn: true, sections: [] },   // implicit: whatever nothing claims
    { id: "commands", icon: "terminal", label: "App launch commands",
      defaultOn: false, sections: ["apps"] }
];

function _claimed() {
    var map = {};
    for (var i = 0; i < GROUPS.length; i++)
        for (var j = 0; j < GROUPS[i].sections.length; j++)
            map[GROUPS[i].sections[j]] = GROUPS[i].id;
    return map;
}

// "background" -> "wallpaper"; "appearance.palette" -> "theming"; a key no
// group names -> "rest", so a future config section cannot escape the popup.
function groupOf(sectionKey) {
    var claimed = _claimed();
    if (claimed[sectionKey] !== undefined) return claimed[sectionKey];
    return "rest";
}

// The keys a preset holds for one group, spelled as specs. For `rest` that
// is every unclaimed top-level key plus every unclaimed appearance
// subsection - _presetMeta never applies and is nobody's.
function sectionsOfGroup(groupId, preset) {
    var claimed = _claimed();
    var out = [];
    var group = null;
    for (var i = 0; i < GROUPS.length; i++)
        if (GROUPS[i].id === groupId) group = GROUPS[i];
    if (!group) return out;
    if (groupId !== "rest") {
        for (var j = 0; j < group.sections.length; j++) {
            var section = group.sections[j];
            if (section === "_pluginState") {
                if (preset && preset._pluginState !== undefined) out.push("_pluginState");
            } else if (section.indexOf("appearance.") === 0) {
                var sub = section.slice("appearance.".length);
                if (preset && preset.appearance && preset.appearance[sub] !== undefined)
                    out.push("appearance:" + sub);
            } else if (preset && preset[section] !== undefined) {
                out.push(section);
            }
        }
        return out;
    }
    for (var key in (preset || {})) {
        if (key === "_presetMeta" || key === "_pluginState") continue;
        if (key === "appearance") {
            for (var subKey in preset.appearance)
                if (claimed["appearance." + subKey] === undefined)
                    out.push("appearance:" + subKey);
            continue;
        }
        if (claimed[key] === undefined) out.push(key);
    }
    return out;
}

// The --only list for a selection: concrete, present-in-this-preset specs.
function sectionsFor(preset, selectedGroupIds) {
    var out = [];
    for (var i = 0; i < (selectedGroupIds || []).length; i++) {
        var sections = sectionsOfGroup(selectedGroupIds[i], preset);
        for (var j = 0; j < sections.length; j++)
            if (out.indexOf(sections[j]) === -1) out.push(sections[j]);
    }
    return out;
}

// { groupId: how many of its sections this preset holds } - the popup's
// subtitles, and its disabled state for absent groups.
function presentCounts(preset) {
    var counts = {};
    for (var i = 0; i < GROUPS.length; i++)
        counts[GROUPS[i].id] = sectionsOfGroup(GROUPS[i].id, preset).length;
    return counts;
}
