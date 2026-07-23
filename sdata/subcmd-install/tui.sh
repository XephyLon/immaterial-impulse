#!/usr/bin/env bash
# tui.sh — fzf front-end for the installer (fancy variant of the whiptail TUI).
#
# Meant to be RUN (`bash tui.sh` / exec'd), not sourced. It draws an fzf-based
# selection UI (banner + live sysinfo panel + toggle menus) and then shells out
# to the real install pipeline (`./setup install ...`) with exactly the same
# flags/env the whiptail front-end used — see sdata/subcmd-install/options.sh.
# It invents no new flags; the only thing it deploys itself is the fcitx5 IME
# extra, which has no options.sh flag (same as tui-whiptail.sh).
#
# Fallback chain (fzf is not assumed present):
#   1. no TTY                     -> tui-whiptail.sh (which itself -> setup install)
#   2. no fzf, can install it     -> pacman -S --needed fzf, then continue
#   3. no fzf, cannot install it  -> tui-whiptail.sh
#
# Intentionally no `set -e`: fzf's ESC/Ctrl-C exits nonzero and that status
# flows through `var=$(fzf ...)`. Exit codes are checked explicitly instead.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP_BIN="${REPO_ROOT}/setup"
WHIPTAIL_TUI="${REPO_ROOT}/sdata/subcmd-install/tui-whiptail.sh"

#####################################################################################
# Colors (256-color ANSI). Guarded: honour NO_COLOR and non-terminals.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_TEAL=$'\033[38;5;79m'; C_DIM=$'\033[38;5;245m'; C_BOLD=$'\033[1m'
  C_NAVY=$'\033[38;5;60m'; C_WHITE=$'\033[38;5;231m'; C_RST=$'\033[0m'
else
  C_TEAL=''; C_DIM=''; C_BOLD=''; C_NAVY=''; C_WHITE=''; C_RST=''
fi

#####################################################################################
# Fallbacks. Never touch fzf until we know it exists + we have a terminal.
if [[ ! -t 1 ]]; then
  echo "No interactive terminal; using the non-interactive path." >&2
  exec bash "$WHIPTAIL_TUI"
fi

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf not found — the fancy installer needs it." >&2
  if command -v pacman >/dev/null 2>&1; then
    echo "Installing fzf (pacman)..." >&2
    sudo pacman -S --needed --noconfirm fzf || true
  fi
fi
if ! command -v fzf >/dev/null 2>&1; then
  echo "Continuing with the whiptail installer instead." >&2
  exec bash "$WHIPTAIL_TUI"
fi

#####################################################################################
cancelled(){
  echo "Cancelled. No install performed."
  exit 0
}

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '?')"

# --- Banner ------------------------------------------------------------------
banner(){
  printf '%s' "$C_TEAL$C_BOLD"
  cat <<'ART'
   ██╗███╗   ███╗██╗
   ██║████╗ ████║██║
   ██║██╔████╔██║██║
   ██║██║╚██╔╝██║██║
   ██║██║ ╚═╝ ██║██║
   ╚═╝╚═╝     ╚═╝╚═╝
ART
  printf '%s' "$C_RST"
}

# --- Live sysinfo panel (rendered into a temp file, shown as fzf --preview) --
SYSINFO_FILE="$(mktemp -t imi-tui-sysinfo.XXXXXX)"
cleanup(){ rm -f "$SYSINFO_FILE"; }
trap cleanup EXIT

build_sysinfo(){
  local distro kernel cpu gpu ram shell_name
  distro="$( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-Linux}}" )"
  kernel="$(uname -r 2>/dev/null)"
  cpu="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
  if command -v lspci >/dev/null 2>&1; then
    gpu="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | cut -d: -f3- | sed 's/^ *//')"
  fi
  ram="$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')"
  shell_name="$(basename "${SHELL:-sh}")"

  {
    printf '%s\n' "${C_TEAL}${C_BOLD}  System${C_RST}"
    printf '%s\n' "${C_DIM}  ──────────────────────────${C_RST}"
    printf '  %s %s\n' "${C_TEAL}OS    ${C_RST}" "${distro:-?}"
    printf '  %s %s\n' "${C_TEAL}Kernel${C_RST}" "${kernel:-?}"
    printf '  %s %s\n' "${C_TEAL}CPU   ${C_RST}" "${cpu:-?}"
    printf '  %s %s\n' "${C_TEAL}GPU   ${C_RST}" "${gpu:-N/A}"
    printf '  %s %s\n' "${C_TEAL}RAM   ${C_RST}" "${ram:-?}"
    printf '  %s %s\n' "${C_TEAL}Shell ${C_RST}" "${shell_name:-?}"
    printf '\n'
    printf '%s\n' "${C_TEAL}${C_BOLD}  Immaterial Impulse${C_RST}"
    printf '%s\n' "${C_DIM}  ──────────────────────────${C_RST}"
    printf '  %s v%s\n' "${C_TEAL}Version${C_RST}" "${VERSION}"
    printf '  %s\n' "${C_DIM}  the evil twin of${C_RST}"
    printf '  %s\n' "${C_DIM}  illogical-impulse${C_RST}"
  } > "$SYSINFO_FILE"
}

# --- fzf helpers -------------------------------------------------------------
# Shared fzf invocation: banner as header, sysinfo as the right preview panel.
FZF_COMMON=(
  --ansi --layout=reverse --border=rounded --pointer='▎' --marker='●'
  --height=100% --info=inline
  --color='fg+:15,bg+:-1,pointer:79,marker:79,header:79,border:60,prompt:79'
  --preview="cat '$SYSINFO_FILE'"
  --preview-window='right,32%,border-left'
)

# Toggle menu. Uses globals: ORDER (keys), LABELS[key], STATE[key]=on|off.
# Redraws on every toggle; a "Continue" sentinel breaks the loop. Mutates STATE.
fzf_toggle(){
  local title="$1"
  local pos=1                 # cursor row to restore after each toggle redraw
  while true; do
    local lines=() key mark
    for key in "${ORDER[@]}"; do
      if [[ "${STATE[$key]}" == on ]]; then mark="${C_TEAL}●${C_RST}"; else mark="${C_DIM}◯${C_RST}"; fi
      lines+=("${key}"$'\t'"  ${mark}  ${LABELS[$key]}")
    done
    lines+=("__DONE__"$'\t'"  ${C_TEAL}${C_BOLD}➜  Continue${C_RST}")
    local header
    header="$(banner)"$'\n'"${C_DIM}  Enter = toggle · ESC = cancel${C_RST}"$'\n'"  ${C_BOLD}${title}${C_RST}"
    local pick
    # Re-invoking fzf per toggle otherwise snaps the cursor back to the top;
    # start:pos($pos) restores it to the row that was just acted on.
    pick=$(printf '%s\n' "${lines[@]}" \
      | fzf "${FZF_COMMON[@]}" --with-nth='2..' --delimiter=$'\t' \
            --bind "start:pos($pos)" \
            --header="$header" --prompt='select ▸ ')
    [[ $? -eq 0 ]] || return 130
    key=${pick%%$'\t'*}
    [[ "$key" == "__DONE__" ]] && return 0
    if [[ "${STATE[$key]}" == on ]]; then STATE[$key]=off; else STATE[$key]=on; fi
    # Keep the cursor on this row for the next redraw.
    local i=0 k
    for k in "${ORDER[@]}"; do i=$((i+1)); [[ "$k" == "$key" ]] && { pos=$i; break; }; done
  done
}

# Single-select menu. Args: title, then "value<TAB>label" lines on stdin.
# Echoes the chosen value.
fzf_pick(){
  local title="$1"; shift
  local header
  header="$(banner)"$'\n'"${C_DIM}  Enter = choose · ESC = cancel${C_RST}"$'\n'"  ${C_BOLD}${title}${C_RST}"
  local pick
  pick=$(fzf "${FZF_COMMON[@]}" --with-nth='2..' --delimiter=$'\t' \
             --header="$header" --prompt='choose ▸ ')
  [[ $? -eq 0 ]] || return 130
  printf '%s' "${pick%%$'\t'*}"
}

#####################################################################################
build_sysinfo

# --- 1. Component toggles ----------------------------------------------------
# Core config is always installed (never --skip-allfiles), so it is not a toggle.
declare -A STATE=( [DEPS]=on [WE]=off [SDDM]=off )
declare -A LABELS=(
  [DEPS]="Dependencies"
  [WE]="Wallpaper Engine  ${C_DIM}(builds a custom quickshell)${C_RST}"
  [SDDM]="SDDM login theme  ${C_DIM}(ii-sddm-theme · Arch only)${C_RST}"
)
ORDER=(DEPS WE SDDM)
fzf_toggle "Components  (Core config is always installed)" || cancelled
# Snapshot immediately: fzf_toggle works on the shared STATE global, which the
# extras step reuses, so read the component decisions out now.
DEPS_ON="${STATE[DEPS]}"; WE_ON="${STATE[WE]}"; SDDM_ON="${STATE[SDDM]}"

# --- 2. Fontset picker over dots-extra/fontsets ------------------------------
fontset_lines(){
  printf '%s\t%s\n' "none" "  No custom fontset  ${C_DIM}(default fontconfig)${C_RST}"
  while IFS= read -r fs; do
    [[ -n "$fs" ]] || continue
    printf '%s\t%s\n' "$fs" "  Fontset: ${fs}"
  done < <(find "${REPO_ROOT}/dots-extra/fontsets" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
}
FONTSET_CHOICE=$(fontset_lines | fzf_pick "Fontset")
[[ -n "$FONTSET_CHOICE" ]] || cancelled

# --- 3. Extras toggles (reuses the STATE/LABELS/ORDER globals) ---------------
STATE=( [FCITX5]=off [VERBOSE]=off )
LABELS=(
  [FCITX5]="fcitx5 IME config  ${C_DIM}(classic UI)${C_RST}"
  [VERBOSE]="Verbose output  ${C_DIM}(raw install stream; default is a clean progress bar)${C_RST}"
)
ORDER=(FCITX5 VERBOSE)
fzf_toggle "Optional extras" || cancelled
FCITX5_ON="${STATE[FCITX5]}"
VERBOSE_ON="${STATE[VERBOSE]}"

# --- 4. Map choices to the existing flags/env --------------------------------
INSTALL_FLAGS=()
[[ "$WE_ON"   == on ]] && export INSTALL_WE=1
[[ "$SDDM_ON" == on ]] && export INSTALL_SDDM=1
[[ "$DEPS_ON" == on ]] || INSTALL_FLAGS+=(--skip-alldeps)
[[ "$FONTSET_CHOICE" != "none" ]] && INSTALL_FLAGS+=(--fontset "$FONTSET_CHOICE")

# --- Quiet-mode install runner (fancy ASCII progress bar) --------------------
# Renders an eighth-block progress bar whose fill is driven by phase markers the
# install pipeline prints to its log. Between markers the percentage eases so it
# never looks frozen during the long deps/WE build phases.
C_RED=$'\033[38;5;203m'
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# Eighth-block bar. $1=percent(0-100) $2=cell width. Teal fill, dim track.
draw_bar(){
  local pct=$1 width=$2
  local eighths=('' ▏ ▎ ▍ ▌ ▋ ▊ ▉)
  local total=$(( width * 8 ))
  local filled=$(( pct * total / 100 ))
  local full=$(( filled / 8 )) rem=$(( filled % 8 ))
  local bar="" i
  for (( i = 0; i < full; i++ )); do bar+='█'; done
  local cells=$full
  if [[ -n "${eighths[rem]}" ]]; then bar+="${eighths[rem]}"; cells=$(( cells + 1 )); fi
  local empty=$(( width - cells )); (( empty < 0 )) && empty=0
  local track="" ; for (( i = 0; i < empty; i++ )); do track+='░'; done
  printf '%s%s%s%s%s' "$C_TEAL" "$bar" "$C_DIM" "$track" "$C_RST"
}

# Map the furthest phase marker present in the log to "pct|phase". Ordered high
# -> low; first match wins (the log is cumulative, so the latest phase is the
# highest marker present).
log_milestone(){
  local log="$1"
  if   grep -q "SDDM theme: done"                    "$log" 2>/dev/null; then echo "98|Finishing up"
  elif grep -q "SDDM theme: fetching"                "$log" 2>/dev/null; then echo "93|Installing SDDM login theme"
  elif grep -q "Wallpaper Engine: installed a WE"    "$log" 2>/dev/null; then echo "90|Wallpaper Engine ready"
  elif grep -q "Wallpaper Engine: building"          "$log" 2>/dev/null; then echo "66|Building Wallpaper Engine (slow)"
  elif grep -q "3. Copying config files"             "$log" 2>/dev/null; then echo "55|Copying config files"
  elif grep -q "1. Install dependencies"             "$log" 2>/dev/null; then echo "12|Installing dependencies"
  else echo "3|Starting"
  fi
}

# Redraw the 3-line progress area in place. $1 pct $2 phase $3 elapsed $4 spinner $5 lastline
draw_progress(){
  local pct=$1 phase=$2 el=$3 spin=$4 last=$5
  local m=$(( el / 60 )) s=$(( el % 60 ))
  printf '\033[3A'
  printf '\r\033[K   %s  %s%3d%%%s\n'        "$(draw_bar "$pct" 32)" "$C_BOLD" "$pct" "$C_RST"
  printf '\r\033[K   %s%s%s  %s%s%s  %s·  %dm%02ds%s\n' "$C_TEAL" "$spin" "$C_RST" "$C_BOLD" "$phase" "$C_RST" "$C_DIM" "$m" "$s" "$C_RST"
  printf '\r\033[K   %s› %.60s%s\n'          "$C_DIM" "$last" "$C_RST"
}

# Animate the bar while $1(pid) runs, reading phase from $2(log).
progress_loop(){
  local pid="$1" log="$2"
  local start cur=0 frame=0
  start=$(date +%s)
  printf '\033[?25l'          # hide cursor
  printf '\n\n\n'             # reserve the 3-line area
  while kill -0 "$pid" 2>/dev/null; do
    local ms target phase
    ms="$(log_milestone "$log")"; target=${ms%%|*}; phase=${ms#*|}
    (( cur < target )) && cur=$(( cur + (target - cur + 3) / 4 ))
    (( cur > 99 )) && cur=99
    local last
    last="$(grep -av '^[[:space:]]*$' "$log" 2>/dev/null | tail -n1 | sed 's/\x1b\[[0-9;]*m//g')"
    draw_progress "$cur" "$phase" "$(( $(date +%s) - start ))" "${SPIN[frame % 10]}" "$last"
    frame=$(( frame + 1 ))
    sleep 0.12
  done
  printf '\033[?25h'          # show cursor
}

run_quiet_install(){
  local log="${XDG_CACHE_HOME:-$HOME/.cache}/immaterial-impulse/install-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$(dirname "$log")"

  clear; banner
  printf '\n  %sPreparing…%s enter your password if prompted (sudo, once).\n\n' "$C_DIM" "$C_RST"
  if ! sudo -v; then
    printf '  %s✗ sudo authorization failed. Nothing installed.%s\n' "$C_RED" "$C_RST"
    INSTALL_RET=1; return
  fi
  # Keep the sudo timestamp warm through the long build (setup has its own
  # keepalive too, but ours guarantees the hidden run never stalls on a prompt).
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 30; done ) &
  local keepalive=$!

  clear; banner; printf '\n'
  # --force -> ask=false (no pauses/confirms); </dev/null -> functions.sh x()
  # aborts on failure instead of prompting; all output goes to the log.
  "$SETUP_BIN" install "${INSTALL_FLAGS[@]}" --force </dev/null >"$log" 2>&1 &
  local pid=$!
  progress_loop "$pid" "$log"
  wait "$pid"; INSTALL_RET=$?
  kill "$keepalive" 2>/dev/null

  printf '\033[3A'
  if [[ $INSTALL_RET -eq 0 ]]; then
    printf '\r\033[K   %s  %s100%%%s\n'  "$(draw_bar 100 32)" "$C_BOLD" "$C_RST"
    printf '\r\033[K   %s✓%s  Installation complete.%s\n' "$C_TEAL" "$C_BOLD" "$C_RST"
    printf '\r\033[K   %slog: %s%s\n' "$C_DIM" "$log" "$C_RST"
  else
    printf '\r\033[K   %s✗  Installation failed (exit %d).%s\n' "$C_RED" "$INSTALL_RET" "$C_RST"
    printf '\r\033[K   %slast lines of %s:%s\n' "$C_DIM" "$log" "$C_RST"
    printf '\r\033[K\n'
    tail -n 25 "$log" | sed 's/^/     /'
    printf '\n   Re-run and enable the %sVerbose output%s toggle to watch it live.\n' "$C_BOLD" "$C_RST"
  fi
}

# --- 5. Summary + confirm ----------------------------------------------------
yn(){ [[ "$1" == on ]] && echo "yes" || echo "no"; }
clear
banner
cat <<EOF

${C_BOLD}  Review${C_RST}
${C_DIM}  ────────────────────────────────${C_RST}
  Core config      ${C_TEAL}always installed${C_RST}
  Dependencies     $(yn "$DEPS_ON")$([[ "$DEPS_ON" == on ]] || echo "  ${C_DIM}(--skip-alldeps)${C_RST}")
  Wallpaper Engine $(yn "$WE_ON")$([[ "$WE_ON" == on ]] && echo "  ${C_DIM}(INSTALL_WE=1)${C_RST}")
  SDDM login theme $(yn "$SDDM_ON")$([[ "$SDDM_ON" == on ]] && echo "  ${C_DIM}(INSTALL_SDDM=1)${C_RST}")
  Fontset          ${FONTSET_CHOICE}
  fcitx5 IME       $(yn "$FCITX5_ON")
  Output           $([[ "$VERBOSE_ON" == on ]] && echo "verbose ${C_DIM}(raw stream)${C_RST}" || echo "quiet ${C_DIM}(progress bar)${C_RST}")

EOF
read -rp "$(printf '%b' "  ${C_TEAL}${C_BOLD}Proceed with installation?${C_RST} [y/N]: ")" confirm
case "$confirm" in
  y|Y|yes|YES) : ;;
  *) cancelled ;;
esac

# --- 6. Run the install pipeline ---------------------------------------------
if [[ "$VERBOSE_ON" == on ]]; then
  # Verbose: stream live and stay fully interactive (no --force).
  "$SETUP_BIN" install "${INSTALL_FLAGS[@]}"
  INSTALL_RET=$?
else
  # Quiet: fancy progress bar, output -> logfile, non-interactive.
  run_quiet_install
fi

# fcitx5 has no options.sh flag, so (as in tui-whiptail.sh) the TUI deploys that
# one config file itself after a successful install.
if [[ $INSTALL_RET -eq 0 && "$FCITX5_ON" == on ]]; then
  echo "[tui] Deploying fcitx5 IME config (dots-extra/fcitx5)."
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  mkdir -p "${XDG_CONFIG_HOME}/fcitx5/conf"
  cp -f "${REPO_ROOT}/dots-extra/fcitx5/conf/classicui.conf" "${XDG_CONFIG_HOME}/fcitx5/conf/classicui.conf"
fi

exit $INSTALL_RET
