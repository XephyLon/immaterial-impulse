.pragma library

// The one resolution of "which picture is the user's avatar".
//
// avatarFolder is Config.options.profile.avatarPath (the configured avatar
// FOLDER - it gates the feature), avatarPicture the file picked from it.
// faceExists / faceIconExists are UserAvatar.qml's one-time stat of the two
// ricer conventions (~/.face, ~/.face.icon): resolving to a path that is not
// there makes every widget rebuild retry the missing file and warn, so absence
// resolves to "" and the widgets draw their glyph fallback instead.
function resolve(avatarFolder, avatarPicture, home, faceExists, faceIconExists) {
    if (avatarFolder !== "" && avatarPicture !== "")
        return "file://" + avatarPicture;
    if (faceExists)
        return "file://" + home + "/.face";
    if (faceIconExists)
        return "file://" + home + "/.face.icon";
    return "";
}
