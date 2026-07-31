#!/usr/bin/env bash
# 6.plymouth.sh — OPTIONAL. Installs the Immaterial Impulse Plymouth boot
# splash (sdata/plymouth-theme/immaterial-impulse). No-op unless
# INSTALL_PLYMOUTH=1.
#
# Like 4.wallpaperengine.sh / 5.sddm-theme.sh this is meant to be RUN
# (`bash 6.plymouth.sh`), not sourced: self-contained, `exit 0` skip path.
#
# What it does (Arch/mkinitcpio only):
#   1. pacman -S --needed plymouth
#   2. copy the theme to /usr/share/plymouth/themes/immaterial-impulse
#   3. add the `plymouth` hook to /etc/mkinitcpio.conf after `udev`
#      (backing the file up first; never touches a config that already
#      has the hook)
#   4. plymouth-set-default-theme -R (rebuilds the initramfs)
#
# The kernel command line is NOT edited automatically - a broken cmdline is a
# broken boot. Instead the needed `quiet splash` change is printed for the
# user's bootloader (GRUB detected via /etc/default/grub).
set -euo pipefail

[[ "${INSTALL_PLYMOUTH:-0}" == "1" ]] || { echo "[ImI] Plymouth theme: skipped."; exit 0; }

if ! command -v pacman >/dev/null 2>&1 || [[ ! -f /etc/mkinitcpio.conf ]]; then
  echo "[ImI] Plymouth theme: needs pacman + mkinitcpio (Arch); skipping." >&2
  exit 0
fi

THEME_SRC="sdata/plymouth-theme/immaterial-impulse"
THEME_DEST="/usr/share/plymouth/themes/immaterial-impulse"
if [[ ! -f "$THEME_SRC/immaterial-impulse.plymouth" ]]; then
  echo "[ImI] Plymouth theme: $THEME_SRC not found (run from the repo root); skipping." >&2
  exit 0
fi

echo "[ImI] Plymouth theme: installing plymouth..."
sudo pacman -S --needed --noconfirm plymouth

echo "[ImI] Plymouth theme: installing theme to $THEME_DEST..."
sudo mkdir -p "$THEME_DEST"
sudo cp -f "$THEME_SRC"/* "$THEME_DEST/"

if ! grep -Eq '^HOOKS=.*[( ]plymouth[ )]' /etc/mkinitcpio.conf; then
  echo "[ImI] Plymouth theme: adding the plymouth hook to /etc/mkinitcpio.conf (backup: .pre-imi-plymouth)..."
  sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.pre-imi-plymouth
  # After `udev` when present (the recommended slot), else right after `base`.
  if grep -Eq '^HOOKS=.*[( ]udev[ )]' /etc/mkinitcpio.conf; then
    sudo sed -i -E 's/^(HOOKS=.*[( ])udev([ )])/\1udev plymouth\2/' /etc/mkinitcpio.conf
  else
    sudo sed -i -E 's/^(HOOKS=.*[( ])base([ )])/\1base plymouth\2/' /etc/mkinitcpio.conf
  fi
  if ! grep -Eq '^HOOKS=.*[( ]plymouth[ )]' /etc/mkinitcpio.conf; then
    echo "[ImI] Plymouth theme: could not add the hook automatically; restoring backup." >&2
    sudo mv /etc/mkinitcpio.conf.pre-imi-plymouth /etc/mkinitcpio.conf
    exit 0
  fi
else
  echo "[ImI] Plymouth theme: plymouth hook already present."
fi

echo "[ImI] Plymouth theme: setting the default theme + rebuilding the initramfs..."
sudo plymouth-set-default-theme -R immaterial-impulse

echo "[ImI] Plymouth theme: installed."
if [[ -f /etc/default/grub ]] && ! grep -Eq '^GRUB_CMDLINE_LINUX_DEFAULT=.*splash' /etc/default/grub; then
  cat <<'MSG'
[ImI] Plymouth theme: one manual step remains (not automated on purpose -
a broken kernel command line is a broken boot):
  1. Edit /etc/default/grub and add `quiet splash` to
     GRUB_CMDLINE_LINUX_DEFAULT, e.g.:
       GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash"
  2. sudo grub-mkconfig -o /boot/grub/grub.cfg
MSG
fi
