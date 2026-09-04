import QtQuick
import QtTest
import "../modules/imi/wallpaperSelector/selector_places.js" as SelectorPlaces

// The wallpaper selector's places sidebar: which folder shortcuts are offered,
// in what order, and which of them is lit for the directory on screen. Pure so
// the visibility rules (weeb gate, empty custom path) and the current-place
// match are testable - nothing about the drawn sidebar is reachable from
// qmltestrunner.
TestCase {
    name: "SelectorPlacesTest"

    readonly property var dirs: ({
        home: "/home/u",
        documents: "/home/u/Documents",
        downloads: "/home/u/Downloads",
        pictures: "/home/u/Pictures",
        videos: "/home/u/Videos"
    })

    function test_standard_places_in_order() {
        var rows = SelectorPlaces.places(dirs, { showHomePath: true, weeb: 0, userPath: "" })
        var names = rows.map(r => r.key)
        // Wallpapers ahead of the generic XDG places: it is what the window
        // is for (the mock's own order).
        compare(names[0], "wallpapers")
        verify(names.includes("home"))
        verify(names.includes("documents"))
        verify(names.includes("downloads"))
        verify(names.includes("pictures"))
        verify(names.includes("videos"))
        verify(names.includes("random"))
    }

    function test_wallpapers_place_is_the_pictures_subdir() {
        var rows = SelectorPlaces.places(dirs, { showHomePath: true, weeb: 0, userPath: "" })
        compare(rows.find(r => r.key === "wallpapers").path, "/home/u/Pictures/Wallpapers")
    }

    function test_weeb_gate_and_home_switch() {
        var rows = SelectorPlaces.places(dirs, { showHomePath: false, weeb: 0, userPath: "" })
        verify(!rows.some(r => r.key === "homework"))
        verify(!rows.some(r => r.key === "home"))

        rows = SelectorPlaces.places(dirs, { showHomePath: true, weeb: 1, userPath: "" })
        verify(rows.some(r => r.key === "homework"))
        verify(rows.some(r => r.key === "home"))
    }

    function test_custom_path_is_named_for_its_basename() {
        var rows = SelectorPlaces.places(dirs, { showHomePath: true, weeb: 0, userPath: "/mnt/art/walls/" })
        var custom = rows.find(r => r.key === "custom")
        verify(custom !== undefined)
        compare(custom.name, "walls")
        compare(custom.path, "/mnt/art/walls/")

        rows = SelectorPlaces.places(dirs, { showHomePath: true, weeb: 0, userPath: "   " })
        verify(!rows.some(r => r.key === "custom"))
    }

    function test_current_place_matches_by_resolved_path() {
        // Wallpapers.directory is a resolved file:// URL; a place stores a
        // plain path. The match has to survive both spellings and a trailing
        // slash, or no row ever lights up.
        verify(SelectorPlaces.isCurrent("/home/u/Pictures/Wallpapers", "file:///home/u/Pictures/Wallpapers"))
        verify(SelectorPlaces.isCurrent("/home/u/Pictures/Wallpapers/", "file:///home/u/Pictures/Wallpapers"))
        verify(!SelectorPlaces.isCurrent("/home/u/Pictures", "file:///home/u/Pictures/Wallpapers"))
    }
}
