#!/usr/bin/env bash
# 5.sddm-theme.sh — OPTIONAL. Installs the SDDM login theme by fetching and
# running its own installer. No-op unless INSTALL_SDDM=1.
#
# Points at XephyLon/imi-sddm-theme, our fork of 3d3f/ii-sddm-theme. The fork
# exists for three reasons upstream could not serve, since it has had no commit
# since 2026-06:
#   - it resolved the shell config as ~/.config/illogical-impulse/config.json,
#     a path that stopped existing when the shell was renamed, so its "ii +
#     matugen" mode silently synced settings frozen at the rename;
#   - every confirmation was a bare `read`, so an unattended caller EOF'd on
#     the first prompt and the installer exited 0 having installed nothing;
#   - it ignored Wallpaper Engine, so the greeter fell back to a stock
#     background exactly when the desktop was at its least default.
#
# Like 4.wallpaperengine.sh, this is meant to be RUN (`bash 5.sddm-theme.sh`),
# not sourced: it is self-contained and uses `exit 0` for the skip path, which
# must not exit the whole `setup` process.
#
# We deliberately do NOT vendor the theme. It ships its own interactive
# setup.sh that clones the theme, installs its deps (sddm, qt6-svg,
# qt6-virtualkeyboard, qt6-multimedia-ffmpeg), writes /etc/sddm.conf.d, a
# matugen block, a sudoers rule and fonts, and guides the user through the
# install mode (ii+matugen / matugen-only / manual). We just fetch that
# installer at a pinned commit and hand off — so the SDDM theme stays a thin,
# opt-in bolt-on rather than code we carry and have to maintain.
#
# The pin covers the *installer logic*. The theme content is a separate clone
# the fetched setup.sh performs itself, from the THEME_REPO baked into it — so
# what lands in /usr/share/sddm/themes is decided by that variable, not by this
# URL. Pointing this file at the fork while the fork's setup.sh still cloned
# 3d3f/ii-sddm-theme installed upstream's theme verbatim, silently undoing
# every fork change to the theme (the immaterial-impulse config path, the
# Wallpaper Engine resolution) on each install. Fixed in the fork at 81353f6.
# If the login theme ever looks like upstream's again, check THEME_REPO first.
#
# Arch-only: the theme's setup.sh uses pacman. Skipped elsewhere.
set -euo pipefail

[[ "${INSTALL_SDDM:-0}" == "1" ]] || { echo "[ImI] SDDM theme: skipped."; exit 0; }

if ! command -v pacman >/dev/null 2>&1; then
  echo "[ImI] SDDM theme: ii-sddm-theme supports Arch Linux only (needs pacman); skipping." >&2
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[ImI] SDDM theme: curl is required to fetch the installer; skipping." >&2
  exit 0
fi

SDDM_REPO_RAW="${SDDM_REPO_RAW:-https://raw.githubusercontent.com/XephyLon/imi-sddm-theme}"
# Pin the installer for reproducibility. Bump this to adopt a newer ii-sddm-theme.
SDDM_REF="${SDDM_REF:-2736aadbb6ed77a2402bd99dc1b57e480ba3038a}"
SETUP_URL="${SDDM_REPO_RAW}/${SDDM_REF}/setup.sh"

echo "[ImI] SDDM theme: fetching ii-sddm-theme installer (${SDDM_REF:0:12})..."
TMP_SETUP="$(mktemp --suffix=-ii-sddm-setup.sh)"
trap 'rm -f "$TMP_SETUP"' EXIT

if ! curl -fsSL "$SETUP_URL" -o "$TMP_SETUP"; then
  echo "[ImI] SDDM theme: failed to download installer from $SETUP_URL; skipping." >&2
  exit 0
fi

# The fork takes IMI_SDDM_ASSUME_YES and IMI_SDDM_MODE, so this runs unattended
# and needs no terminal. Upstream had neither: every confirmation was a bare
# `read`, so a caller whose stdin was not a tty hit EOF on the first prompt,
# fell through to the default case and exited 0 - installing nothing, silently.
# That is what the /dev/tty reconnection here used to work around.
#
# ii-matugen is the mode worth having: it syncs the shell's own settings,
# wallpaper and colors to the greeter. The fork validates the mode against what
# the run can actually offer, so if the shell config is not there yet it falls
# back to asking rather than being forced into a state that cannot work.
echo "[ImI] SDDM theme: handing off to the theme installer (unattended)..."
# Optional extra - never let a decline/failure abort the whole install.
IMI_SDDM_ASSUME_YES="${IMI_SDDM_ASSUME_YES:-1}" \
IMI_SDDM_MODE="${IMI_SDDM_MODE:-ii-matugen}" \
  bash "$TMP_SETUP" \
  || echo "[ImI] SDDM theme: theme installer exited non-zero (declined or error)."
echo "[ImI] SDDM theme: done."
