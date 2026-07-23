#!/usr/bin/env bash
# Immaterial Impulse bootstrap installer.
#
# Fetch the whole suite and launch its installer with one command:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/XephyLon/end4-pC/main/get.sh)
#
# Use the `bash <(curl ...)` form, NOT `curl ... | bash`: the installer is
# interactive (whiptail menu), and piping the script into bash would occupy
# stdin and break the prompts.
#
# The suite installer (`setup` + `sdata/`) needs the full repository tree, so
# this just clones it (to a stable location, reused for updates) and hands off.
#
# Overridable via env: IMI_REPO, IMI_REF (branch/tag/commit), IMI_DEST.
set -euo pipefail

REPO="${IMI_REPO:-https://github.com/XephyLon/end4-pC}"
REF="${IMI_REF:-main}"
DEST="${IMI_DEST:-${XDG_DATA_HOME:-$HOME/.local/share}/immaterial-impulse/src}"

if ! command -v git >/dev/null 2>&1; then
  echo "[ImI] git is required to fetch Immaterial Impulse. Install git and re-run." >&2
  exit 1
fi

if [[ -d "$DEST/.git" ]]; then
  echo "[ImI] Updating existing checkout at $DEST ..."
  git -C "$DEST" fetch --depth 1 origin "$REF"
  git -C "$DEST" checkout -f "$REF" 2>/dev/null || git -C "$DEST" checkout -f FETCH_HEAD
  git -C "$DEST" reset --hard FETCH_HEAD
else
  echo "[ImI] Cloning $REPO ($REF) into $DEST ..."
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --branch "$REF" "$REPO" "$DEST" 2>/dev/null \
    || git clone "$REPO" "$DEST"
fi

cd "$DEST"
echo "[ImI] Launching the installer (source: $DEST) ..."
exec ./setup "$@"
