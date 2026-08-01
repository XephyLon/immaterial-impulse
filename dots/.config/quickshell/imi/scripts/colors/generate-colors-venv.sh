#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${IMMATERIAL_IMPULSE_VIRTUAL_ENV:-${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-}}"

if [[ -z "$VENV_DIR" || ! -f "$VENV_DIR/bin/activate" ]]; then
    echo "generate-colors-venv: IMMATERIAL_IMPULSE_VIRTUAL_ENV is not a valid virtual environment" >&2
    exit 1
fi

source "$VENV_DIR/bin/activate"

# Resolve `--scheme auto` the same way switchwall.sh does for the desktop
# palette: detect the variant from the image itself (scheme_for_image.py).
# Without this, callers would hand generate_colors_material.py a scheme name
# it doesn't know, and the lock palette would diverge from the desktop one.
args=("$@")
scheme="" imgpath="" scheme_idx=-1
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
        --scheme) scheme_idx=$((i + 1)); scheme="${args[scheme_idx]:-}" ;;
        --path)   imgpath="${args[$((i + 1))]:-}" ;;
    esac
done
if [[ "$scheme" == "auto" && -n "$imgpath" && $scheme_idx -ge 0 ]]; then
    detected="$(python3 "$SCRIPT_DIR/scheme_for_image.py" "$imgpath" 2>/dev/null | tr -d '\n')"
    args[scheme_idx]="${detected:-scheme-tonal-spot}"
fi

exec python3 "$SCRIPT_DIR/generate_colors_material.py" "${args[@]}"
