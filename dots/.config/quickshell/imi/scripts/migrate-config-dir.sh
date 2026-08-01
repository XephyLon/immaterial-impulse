#!/usr/bin/env bash
# migrate-config-dir.sh — one-time migration of the ImI data dir from the old
# illogical-impulse name to immaterial-impulse.
#
# Idempotent. Handles three cases:
#   1. no old dir             -> nothing to do
#   2. old exists, no new     -> plain rename (mv)
#   3. old exists, new exists  -> the installer already created the new dir
#      (installed_true etc.) but the user's real settings still live under the
#      old name. Copy the old data in WITHOUT clobbering anything already in the
#      new dir, but only while the new dir has no config.json yet (i.e. the shell
#      hasn't written a real config there) so a genuine new config on later runs
#      is never overwritten. This is the case that previously lost bar/Settings,
#      because the guard used to be dir-level ("skip if the new dir exists").
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
old="$config_home/illogical-impulse"
new="$config_home/immaterial-impulse"

[[ -d "$old" ]] || exit 0            # nothing to migrate

if [[ ! -d "$new" ]]; then
    mv "$old" "$new"
    echo "[ImI] migrated config dir: $old -> $new" >&2
    exit 0
fi

# Both dirs exist. Only migrate if the user's config hasn't been carried over
# yet (no config.json in the new dir). cp -an = archive, no-clobber: brings over
# config.json, actions/, presets/, ai/prompts, etc. while leaving the installer's
# files (installed_true, ...) and anything already present untouched. The old
# dir is left in place as a natural backup.
if [[ -f "$old/config.json" && ! -f "$new/config.json" ]]; then
    cp -an "$old/." "$new/" 2>/dev/null || true
    echo "[ImI] migrated user config from $old into existing $new" >&2
fi
exit 0
