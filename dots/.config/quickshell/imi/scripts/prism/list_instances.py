#!/usr/bin/env python3
"""List Prism Launcher instances as JSON for the launcher search.

Emits one object per instance on stdout, most recently launched first:

    {"id", "name", "icon", "minecraftVersion", "loader",
     "lastLaunchTime", "totalTimePlayed", "launch": [argv...]}

`id` is the instance FOLDER name, which is what `prismlauncher --launch`
takes; `name` is the display name from instance.cfg, which the user can
rename independently. The two are not interchangeable.

Errors are never fatal: a machine with no Prism, a half-written mmc-pack.json
or an unreadable instance directory produces fewer entries, not a failure -
the caller is a search bar, and a stack trace there costs the user every other
result too.
"""

import argparse
import json
import os
import shlex
import sys
from pathlib import Path

# uid -> display name. Prism identifies the mod loader by the component uid in
# mmc-pack.json; the cachedName field is absent on instances that have never
# been launched, so the uid is the reliable half.
LOADER_UIDS = {
    "net.minecraftforge": "Forge",
    "net.neoforged": "NeoForge",
    "net.fabricmc.fabric-loader": "Fabric",
    "org.quiltmc.quilt-loader": "Quilt",
    "com.mumfrey.liteloader": "LiteLoader",
}

MINECRAFT_UID = "net.minecraft"

# Prism stores instance icons under icons/<iconKey>.<ext>, but iconKey may also
# name a built-in with no file on disk (e.g. "flame", "default").
ICON_EXTENSIONS = (".png", ".webp", ".jpg", ".jpeg", ".svg", ".gif", ".ico")


def parse_instance_cfg(path):
    """Parse Prism's instance.cfg into a dict.

    Deliberately not configparser: these files are only key=value pairs, but
    values legitimately contain '=' (Env={}, JavaPath, renamed instances), and
    MultiMC-era files have no section header at all. Splitting on the first '='
    handles every real case without configparser's interpolation and
    header requirements.
    """
    values = {}
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return values
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("#", ";", "[")):
            continue
        key, sep, value = line.partition("=")
        if sep:
            values[key.strip()] = value.strip()
    return values


def read_pack(path):
    """Minecraft version and loader name from mmc-pack.json."""
    try:
        with path.open(encoding="utf-8") as handle:
            pack = json.load(handle)
    except (OSError, ValueError):
        return "", ""
    version, loader = "", ""
    for component in pack.get("components", []):
        if not isinstance(component, dict):
            continue
        uid = component.get("uid", "")
        if uid == MINECRAFT_UID:
            version = str(component.get("version", ""))
        elif uid in LOADER_UIDS:
            loader = LOADER_UIDS[uid]
    return version, loader


def resolve_icon(icons_dir, icon_key):
    """Absolute path to the instance's icon file, or "" when there is none.

    Returning "" rather than a guessed path matters: the search item renders
    whatever it is handed, so a path to a nonexistent file shows a broken
    image where a Material symbol fallback belongs.
    """
    if not icon_key:
        return ""
    for extension in ICON_EXTENSIONS:
        candidate = icons_dir / f"{icon_key}{extension}"
        if candidate.is_file():
            return str(candidate)
    return ""


def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def collect(data_dir, launcher_argv):
    instances_dir = data_dir / "instances"
    icons_dir = data_dir / "icons"
    try:
        entries = sorted(instances_dir.iterdir())
    except OSError:
        return []

    out = []
    for entry in entries:
        config_path = entry / "instance.cfg"
        if not config_path.is_file():
            continue
        config = parse_instance_cfg(config_path)
        version, loader = read_pack(entry / "mmc-pack.json")
        out.append({
            "id": entry.name,
            "name": config.get("name") or entry.name,
            "icon": resolve_icon(icons_dir, config.get("iconKey", "")),
            "minecraftVersion": version,
            "loader": loader,
            "lastLaunchTime": to_int(config.get("lastLaunchTime")),
            "totalTimePlayed": to_int(config.get("totalTimePlayed")),
            "launch": launcher_argv + ["--launch", entry.name],
        })

    # Most recently launched first; never-launched instances (timestamp 0)
    # therefore sort last, with a name tiebreak so the order is stable rather
    # than filesystem-dependent.
    out.sort(key=lambda i: (-i["lastLaunchTime"], i["name"].lower()))
    return out


def default_data_dir():
    xdg_data = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    native = Path(xdg_data) / "PrismLauncher"
    if native.is_dir():
        return native
    return Path.home() / ".var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", default=None,
                        help="Prism data directory (default: XDG, then flatpak)")
    parser.add_argument("--launcher", default="prismlauncher",
                        help="launcher command; split with shell quoting rules "
                             "so 'flatpak run org.prismlauncher.PrismLauncher' works")
    args = parser.parse_args()

    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    json.dump(collect(data_dir, shlex.split(args.launcher)), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
