# This script is meant to be sourced.
# It's not for directly running.
# shellcheck shell=bash

source "${REPO_ROOT}/sdata/lib/backup.sh"

archive="${BACKUP_OUTPUT:-$HOME/imi-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
imi_backup_create "$archive"
log_success "Backup written: $archive"
printf '  contains: '; imi_backup_payload "$archive" | tr '\n' ' '; echo
