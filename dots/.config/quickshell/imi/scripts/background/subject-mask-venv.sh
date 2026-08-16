#!/usr/bin/env bash
# Runs subject_mask.py inside the shell's uv venv, where onnxruntime lives.
#
# Only `run` needs it. `status` and `sweep` are stdlib-only on purpose - the
# shell's read path must not depend on a venv that may not be built yet, and a
# background whose depth layer failed to appear because a venv was missing would
# be indistinguishable from a wallpaper with no mask.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$(eval echo "${IMMATERIAL_IMPULSE_VIRTUAL_ENV:-$ILLOGICAL_IMPULSE_VIRTUAL_ENV}")/bin/activate"
"$SCRIPT_DIR/subject_mask.py" "$@"
SUBJECT_MASK_EXIT_CODE=$?
deactivate

exit $SUBJECT_MASK_EXIT_CODE
