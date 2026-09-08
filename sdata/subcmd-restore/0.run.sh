# This script is meant to be sourced.
# It's not for directly running.
# shellcheck shell=bash

source "${REPO_ROOT}/sdata/lib/backup.sh"

[[ -r "$RESTORE_ARCHIVE" ]] || log_die "Cannot read $RESTORE_ARCHIVE"
if [[ "$RESTORE_FORCE" != true ]] && imi_shell_is_running; then
  log_die "The shell is running and would overwrite the restored config. Quit it first (qs kill -c imi) or pass --force."
fi
imi_backup_restore "$RESTORE_ARCHIVE"
log_success "Restored $RESTORE_ARCHIVE into ${XDG_CONFIG_HOME}. Start the shell (or log back in) to pick it up."
