#!/usr/bin/env bash
# 5.sddm-theme.sh — OPTIONAL. Installs the ii-sddm-theme SDDM login theme
# (https://github.com/3d3f/ii-sddm-theme) by fetching and running its own
# upstream installer. No-op unless INSTALL_SDDM=1.
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
# The pin covers the *installer logic*; the theme content it clones tracks the
# upstream repo's default branch (its setup.sh re-clones the theme itself).
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

SDDM_REPO_RAW="${SDDM_REPO_RAW:-https://raw.githubusercontent.com/3d3f/ii-sddm-theme}"
# Pin the installer for reproducibility. Bump this to adopt a newer ii-sddm-theme.
SDDM_REF="${SDDM_REF:-1d4bcb66647f750bcc14d73de025eae8dd1e3db7}"
SETUP_URL="${SDDM_REPO_RAW}/${SDDM_REF}/setup.sh"

echo "[ImI] SDDM theme: fetching ii-sddm-theme installer (${SDDM_REF:0:12})..."
TMP_SETUP="$(mktemp --suffix=-ii-sddm-setup.sh)"
trap 'rm -f "$TMP_SETUP"' EXIT

if ! curl -fsSL "$SETUP_URL" -o "$TMP_SETUP"; then
  echo "[ImI] SDDM theme: failed to download installer from $SETUP_URL; skipping." >&2
  exit 0
fi

echo "[ImI] SDDM theme: handing off to the upstream installer (interactive)..."
# Optional extra — never let a decline/failure abort the whole install.
bash "$TMP_SETUP" || echo "[ImI] SDDM theme: upstream installer exited non-zero (declined or error)."
echo "[ImI] SDDM theme: done."
