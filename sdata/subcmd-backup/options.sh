# Handle args for subcmd: backup
# shellcheck shell=bash

# `setup` cd's into the repo before we run; a relative output path means
# relative to where the user typed the command.
INVOKE_DIR="${OLDPWD:-$PWD}"
BACKUP_OUTPUT=""

showhelp(){
echo -e "Syntax: $0 backup [OPTIONS]

Archive your Immaterial Impulse configuration: the shell's config, plugins
and presets (~/.config/immaterial-impulse), your Hyprland overrides
(hypr/custom, hypr/hyprland/shellOverrides) and hyprlock/hypridle.conf.
Restore on this or another machine with \"$0 restore <archive>\".

Options:
  -h, --help            Show this help message and exit
  -o, --output <path>   Where to write the archive
                        (default: ~/imi-backup-<date>.tar.gz)
"
}
para=$(getopt \
  -o ho: \
  -l help,output: \
  -n "$0" -- "$@")
[ $? != 0 ] && echo "$0: Error when getopt, please recheck parameters." && exit 1
#####################################################################################
eval set -- "$para"
while true ; do
  case "$1" in
    -h|--help) showhelp;exit;;
    -o|--output) BACKUP_OUTPUT="$2";shift 2;;
    --) shift;break ;;
    *) echo -e "$0: Wrong parameters.";exit 1;;
  esac
done
if [[ -n "$BACKUP_OUTPUT" && "$BACKUP_OUTPUT" != /* ]]; then
  BACKUP_OUTPUT="${INVOKE_DIR}/${BACKUP_OUTPUT}"
fi
