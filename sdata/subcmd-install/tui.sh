#!/usr/bin/env bash
# tui.sh — whiptail menu front-end for the installer (C1/C5 of the
# "Install TUI" plan). Meant to be RUN (`bash tui.sh` / exec'd), not sourced:
# it drives `whiptail` dialogs and then shells out to the real install
# pipeline (`./setup install ...`) with the flags/env those steps already
# understand (see sdata/subcmd-install/options.sh). It does NOT invent new
# flags — everything it sets is something options.sh (or 4.wallpaperengine.sh)
# already parses, EXCEPT the fcitx5 IME extra (see the note near the bottom):
# there is currently no options.sh flag for it at all, so this script deploys
# that one config file itself instead of pretending a flag exists.
#
# Intentionally no `set -e`: whiptail's Cancel/ESC exits nonzero, and that
# exit status flows through a `var=$(whiptail ...)` assignment. Under `set -e`
# that would abort the script before we get a chance to check $? and handle
# Cancel cleanly. Exit codes are checked explicitly after each dialog instead.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP_BIN="${REPO_ROOT}/setup"

#####################################################################################
# Guard: no real terminal or no whiptail -> fall back to the existing
# non-interactive path. Must not touch whiptail at all in this branch, so it
# can never hang waiting on a TTY that isn't there (CI, piped input, etc.).
if [[ ! -t 1 ]] || ! command -v whiptail >/dev/null 2>&1; then
  echo "Interactive TUI needs whiptail + a terminal; falling back to \`setup install\`." >&2
  exec "$SETUP_BIN" install
fi

#####################################################################################
cancelled(){
  echo "Cancelled. No install performed."
  exit 0
}

# --- 1. Component checklist -------------------------------------------------
# "Core config" is intentionally always-on/informational: whatever the user
# does with that checkbox, we never pass --skip-allfiles, since a plain
# install with no config deployed isn't a supported state.
COMPONENTS=$(whiptail --title "Immaterial Impulse Installer" \
  --checklist "Select components (space to toggle, enter to confirm):" 17 74 5 \
  "CORE" "Core config (always installed)" ON \
  "DEPS" "Dependencies" ON \
  "WE" "Wallpaper Engine (builds a custom quickshell)" OFF \
  "SDDM" "SDDM login theme - ii-sddm-theme (Arch only)" OFF \
  3>&1 1>&2 2>&3)
ret=$?
[[ $ret -eq 0 ]] || cancelled

# --- 2. Fontset picker over dots-extra/fontsets -----------------------------
FONTSET_ITEMS=("none" "No custom fontset (use the default fontconfig)")
while IFS= read -r fs; do
  [[ -n "$fs" ]] || continue
  FONTSET_ITEMS+=("$fs" "Fontset: $fs")
done < <(find "${REPO_ROOT}/dots-extra/fontsets" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)

FONTSET_CHOICE=$(whiptail --title "Fontset" \
  --menu "Choose a fontset:" 16 74 6 \
  "${FONTSET_ITEMS[@]}" \
  3>&1 1>&2 2>&3)
ret=$?
[[ $ret -eq 0 ]] || cancelled

# --- 3. fcitx5 IME toggle ----------------------------------------------------
# NOTE (concern): unlike --fontset, options.sh has no flag/env for fcitx5 at
# all — `dots-extra/fcitx5/conf/classicui.conf` isn't wired into
# 3.files.sh/3.files-legacy.sh either (grep confirms no reference). Rather
# than invent a fake options.sh flag, this toggle is handled entirely here:
# if checked, the TUI copies that one file itself after the install pipeline
# succeeds, mirroring the pattern install_file__auto_backup/install_dir__sync
# use elsewhere for dots-extra/* content.
EXTRAS=$(whiptail --title "Extras" \
  --checklist "Optional extras:" 12 74 1 \
  "FCITX5" "fcitx5 IME config (classic UI)" OFF \
  3>&1 1>&2 2>&3)
ret=$?
[[ $ret -eq 0 ]] || cancelled

# --- 4. Map choices to the existing flags/env -------------------------------
INSTALL_FLAGS=()

case "$COMPONENTS" in
  *WE*) export INSTALL_WE=1 ;;
esac

case "$COMPONENTS" in
  *SDDM*) export INSTALL_SDDM=1 ;;
esac

case "$COMPONENTS" in
  *DEPS*) : ;;
  *) INSTALL_FLAGS+=(--skip-alldeps) ;;
esac

if [[ "$FONTSET_CHOICE" != "none" ]]; then
  INSTALL_FLAGS+=(--fontset "$FONTSET_CHOICE")
fi

# --- 5. Final confirm, then run the existing install pipeline ---------------
SUMMARY="Core config: always installed
Dependencies: $(case "$COMPONENTS" in *DEPS*) echo "yes";; *) echo "no (--skip-alldeps)";; esac)
Wallpaper Engine: $(case "$COMPONENTS" in *WE*) echo "yes (INSTALL_WE=1)";; *) echo "no";; esac)
SDDM login theme: $(case "$COMPONENTS" in *SDDM*) echo "yes (INSTALL_SDDM=1)";; *) echo "no";; esac)
Fontset: ${FONTSET_CHOICE}
fcitx5 IME: $(case "$EXTRAS" in *FCITX5*) echo "yes";; *) echo "no";; esac)

Proceed with installation now?"

whiptail --title "Confirm" --yesno "$SUMMARY" 18 74
ret=$?
[[ $ret -eq 0 ]] || cancelled

"$SETUP_BIN" install "${INSTALL_FLAGS[@]}"
INSTALL_RET=$?

if [[ $INSTALL_RET -eq 0 ]] && [[ "$EXTRAS" == *FCITX5* ]]; then
  echo "[tui] Deploying fcitx5 IME config (dots-extra/fcitx5) — no options.sh flag exists for this yet, so the TUI copies it directly."
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  mkdir -p "${XDG_CONFIG_HOME}/fcitx5/conf"
  cp -f "${REPO_ROOT}/dots-extra/fcitx5/conf/classicui.conf" "${XDG_CONFIG_HOME}/fcitx5/conf/classicui.conf"
fi

exit $INSTALL_RET
