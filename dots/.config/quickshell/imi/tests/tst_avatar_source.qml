import QtQuick
import QtTest
import "../services/avatar_source.js" as AvatarSource

// One derivation of "which picture is the user's avatar". Four widgets used to
// each spell the fallback (`file:///home/$USER/.face`) for themselves, and on a
// machine with no ~/.face every rebuild of any of them retried the missing file
// and warned - 106 failed loads in one session from the bar's media popup alone.
TestCase {
    name: "AvatarSourceTest"

    function test_configured_picture_wins() {
        // avatarPath is the configured avatar FOLDER (the gate), avatarPicture
        // the file picked from it.
        compare(AvatarSource.resolve("/pics/avatars", "/pics/avatars/me.png", "/home/u", true, true),
                "file:///pics/avatars/me.png")
    }

    function test_face_fallback_only_when_it_exists() {
        compare(AvatarSource.resolve("", "", "/home/u", true, false), "file:///home/u/.face")
        compare(AvatarSource.resolve("", "", "/home/u", false, true), "file:///home/u/.face.icon")
        // .face ahead of .face.icon when both exist
        compare(AvatarSource.resolve("", "", "/home/u", true, true), "file:///home/u/.face")
    }

    function test_nothing_available_is_empty_not_a_guess() {
        // An empty url is the real "no avatar" state - the widgets draw their
        // glyph fallback for it. A guessed path is a warn per rebuild.
        compare(AvatarSource.resolve("", "", "/home/u", false, false), "")
    }

    function test_gate_without_picture_still_falls_back() {
        // A configured folder with no picture picked yet is not an avatar.
        compare(AvatarSource.resolve("/pics/avatars", "", "/home/u", true, false),
                "file:///home/u/.face")
        compare(AvatarSource.resolve("/pics/avatars", "", "/home/u", false, false), "")
    }
}
