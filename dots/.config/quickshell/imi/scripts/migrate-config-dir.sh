#!/usr/bin/env bash
# migrate-config-dir.sh — one-time migration of the ImI data dir from the old
# illogical-impulse name to immaterial-impulse.
#
# Idempotent, and never deletes user data: the only path that removes the old
# directory is the plain rename, where there is nothing to lose.
#
#   1. no old dir           -> nothing to do
#   2. old exists, no new   -> rename (mv -T)
#   3. old exists, new too  -> merge the old data in WITHOUT clobbering
#      anything already there (cp -an), so the installer's own files
#      (installed_true, ...) survive, and keep the old dir as a backup.
#
# Case 3 turns entirely on one question: is the config.json already sitting in
# the new directory the user's, or a file they have never seen? "It exists" is
# not an answer to that, and it used to be the whole guard - which made this
# migration a no-op for precisely the people it was written for:
#
#   * The installer's seed_default_config (sdata/subcmd-install/3.files.sh)
#     copies defaults/config.json into the new directory verbatim on any
#     install that finds no config.json there - which is every arriving
#     upstream user, because theirs is still under the old name. That alone
#     disabled the migration deterministically, with no race involved.
#   * The shell's own Config writer could win a startup race with this script
#     and drop a default config.json there. That race is closed in
#     modules/common/Directories.qml, which now waits for this script to exit
#     before Config may touch the directory at all - which is also what makes
#     the byte comparison below sound, since nothing can have rewritten the
#     file between the installer copying it in and this script running.
#
# A config.json byte-identical to the defaults/config.json shipping next to
# this script therefore records no decision the user has ever made, and can be
# dropped so the old config takes its place. Anything else is treated as theirs
# and left completely alone: the script declines, exits $DECLINED, and says
# why. A migration that silently picks the wrong config.json is the bug being
# fixed here, so where it cannot tell, it changes nothing and says so instead
# of guessing.
set -euo pipefail

# Distinct from the shell-error codes so Directories.qml can tell "I refused to
# touch anything, tell the user" apart from "the script broke".
DECLINED=3

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
old="$config_home/illogical-impulse"
new="$config_home/immaterial-impulse"
shipped_default="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/defaults/config.json"
# A merge deliberately keeps the old directory as a backup, so without a record
# of it every later launch would see "both dirs, both with a config.json" - the
# one shape that must be declined - and would either nag forever or re-copy
# files the user has since deleted.
stamp="$new/.migrated-from-illogical-impulse"

[[ -d "$old" ]] || exit 0            # nothing to migrate
[[ -f "$stamp" ]] && exit 0          # already merged; the old dir is just a backup now

# -T so a directory appearing underneath us mid-flight fails the rename instead
# of quietly producing $new/illogical-impulse. Other singletons write into the
# new directory at startup, so this is a race we cannot prevent from here, only
# refuse to be fooled by - the merge path below handles it correctly.
if [[ ! -d "$new" ]] && mv -T "$old" "$new" 2>/dev/null; then
    echo "[ImI] migrated config dir: $old -> $new" >&2
    exit 0
fi

if [[ -f "$old/config.json" && -f "$new/config.json" ]]; then
    if [[ ! -f "$shipped_default" ]]; then
        echo "[ImI] NOT migrating: cannot tell whether $new/config.json is yours, because the shipped defaults ($shipped_default) are missing. Nothing was changed - your settings are still in $old." >&2
        exit $DECLINED
    fi
    if ! cmp -s "$new/config.json" "$shipped_default"; then
        echo "[ImI] NOT migrating: $new/config.json differs from the config this shell ships, so it looks like settings you have already changed here and overwriting it would lose them. Nothing was changed. Your settings from before the rename are still in $old - merge that config.json in by hand, or delete/rename $old once you no longer want it." >&2
        exit $DECLINED
    fi
    rm -f "$new/config.json"
    echo "[ImI] $new/config.json was the installer's untouched default; replacing it with your settings from $old" >&2
fi

# cp -an = archive, no-clobber: brings over config.json, actions/, presets/,
# ai/prompts, etc. while leaving the installer's files and anything already
# present untouched.
if ! cp -an "$old/." "$new/"; then
    echo "[ImI] NOT migrating: copying $old into $new did not finish cleanly. Your settings are still in $old." >&2
    exit $DECLINED
fi
touch "$stamp"
echo "[ImI] migrated user config from $old into existing $new (kept $old as a backup)" >&2
exit 0
