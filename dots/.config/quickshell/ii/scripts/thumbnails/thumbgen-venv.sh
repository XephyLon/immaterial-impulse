#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source $(eval echo ${IMMATERIAL_IMPULSE_VIRTUAL_ENV:-$ILLOGICAL_IMPULSE_VIRTUAL_ENV})/bin/activate
GIO_USE_VFS=local "$SCRIPT_DIR/thumbgen.py" "$@"
THUMBGEN_EXIT_CODE=$?
deactivate

exit $THUMBGEN_EXIT_CODE
