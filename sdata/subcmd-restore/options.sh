# Handle args for subcmd: restore
# shellcheck shell=bash

INVOKE_DIR="${OLDPWD:-$PWD}"
RESTORE_ARCHIVE=""
RESTORE_FORCE=false

showhelp(){
echo -e "Syntax: $0 restore [OPTIONS] <archive>

Restore a backup made by \"$0 backup\" into ~/.config. Anything already
there is moved aside as <path>.pre-restore-<stamp>, never deleted.

Refuses to run while the shell is up: it rewrites config.json as it runs.
Quit it first (\"qs kill -c imi\") or pass --force.

Options:
  -h, --help     Show this help message and exit
  -f, --force    Restore even if the shell is running
"
}
para=$(getopt \
  -o hf \
  -l help,force \
  -n "$0" -- "$@")
[ $? != 0 ] && echo "$0: Error when getopt, please recheck parameters." && exit 1
#####################################################################################
eval set -- "$para"
while true ; do
  case "$1" in
    -h|--help) showhelp;exit;;
    -f|--force) RESTORE_FORCE=true;shift;;
    --) shift;break ;;
    *) echo -e "$0: Wrong parameters.";exit 1;;
  esac
done
RESTORE_ARCHIVE="${1:-}"
if [[ -z "$RESTORE_ARCHIVE" ]]; then
  echo -e "$0: restore needs an archive path."; showhelp; exit 1
fi
if [[ "$RESTORE_ARCHIVE" != /* ]]; then
  RESTORE_ARCHIVE="${INVOKE_DIR}/${RESTORE_ARCHIVE}"
fi
