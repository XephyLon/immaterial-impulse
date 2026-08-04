# This script is meant to be sourced.
# It's not for directly running.

# A login shell that is about to be uninstalled locks the user out of their
# desktop. `fish` is a `depends` of immaterial-impulse-fonts-themes, so the
# `yay -Rns` loop below removes it along with the meta package. SDDM then has no
# shell to start the session with: /usr/share/sddm/scripts/wayland-session has an
# explicit `*/fish)` branch that runs `exec $SHELL --login -c ...`, and when that
# exec fails the script falls through to `exit 1`. The session dies the instant
# it starts, so the greeter comes straight back after a *correct* password - a
# login loop that reads as a rejected password. The same applies to any display
# manager that starts the session through the user's login shell.
#
# imi never sets anyone's login shell (nothing in this repo runs chsh or
# usermod -s), so this only moves a shell we are ourselves about to delete, and
# only for the user running the uninstall - other accounts on the machine are
# not ours to touch, and are reported instead.
FALLBACK_LOGIN_SHELL="${FALLBACK_LOGIN_SHELL:-/bin/bash}"

# True when `yay -Rns` on our meta packages would actually take $1 with it.
# A package the user installed explicitly is kept by -Rs, and so is one that
# something outside this suite still needs; changing a shell in either case
# would be a gratuitous edit to a system we did not configure.
pkg_removed_with_our_metapackages(){
  local pkg="$1" reason required r
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Qi "$pkg" >/dev/null 2>&1 || return 1
  reason="$(pacman -Qi "$pkg" 2>/dev/null | awk -F': +' '/^Install Reason/{print $2; exit}')"
  [[ "$reason" == *dependency* ]] || return 1
  required="$(pacman -Qi "$pkg" 2>/dev/null | awk -F': +' '/^Required By/{print $2; exit}')"
  for r in $required; do
    [[ "$r" == "None" ]] && continue
    [[ "$r" == immaterial-impulse-* ]] || return 1
  done
  return 0
}

login_shell_of(){ getent passwd "$1" 2>/dev/null | cut -d: -f7; }

# Other accounts whose login shell we are about to delete. We do not edit them -
# a shell we never set on a user we were never asked about - but leaving the
# machine with a locked-out account and saying nothing is worse than a warning.
warn_other_users_on_doomed_shell(){
  local doomed="$1" me="$2" other uid othershell
  while IFS=: read -r other _ uid _ _ _ othershell; do
    [[ "$other" == "$me" ]] && continue
    (( uid >= 1000 && uid < 65534 )) || continue
    [[ "$othershell" == */"$doomed" ]] || continue
    printf "${STY_YELLOW}[$0]: WARNING: user \"%s\" also logs in with %s, which is being removed.\n" "$other" "$othershell"
    printf "Their next login will fail until you run: sudo chsh -s %s %s${STY_RST}\n" "$FALLBACK_LOGIN_SHELL" "$other"
  done < <(getent passwd)
}

rescue_login_shell(){
  local me current
  me="$(whoami)"
  current="$(login_shell_of "$me")"
  case "$current" in
    */fish) ;;
    *) return 0 ;;
  esac
  pkg_removed_with_our_metapackages fish || return 0

  if [[ ! -x "$FALLBACK_LOGIN_SHELL" ]]; then
    printf "${STY_RED}[$0]: Your login shell (%s) is about to be uninstalled, but the fallback %s does not exist.\n" \
      "$current" "$FALLBACK_LOGIN_SHELL"
    printf "Set a shell that will survive BEFORE rebooting, e.g. sudo chsh -s /usr/bin/sh %s${STY_RST}\n" "$me"
    return 0
  fi

  printf "${STY_CYAN}[$0]: Your login shell (%s) is a dependency being uninstalled below.\n" "$current"
  printf "Changing it to %s first, otherwise the next login would fail after a correct password.\n" "$FALLBACK_LOGIN_SHELL"
  printf "To go back once fish is reinstalled: chsh -s %s${STY_RST}\n" "$current"
  x sudo chsh -s "$FALLBACK_LOGIN_SHELL" "$me"
  warn_other_users_on_doomed_shell fish "$me"
}

showfun rescue_login_shell
v rescue_login_shell

for i in immaterial-impulse-{quickshell-git,audio,backlight,basic,bibata-modern-classic-bin,fonts-themes,hyprland,kde,microtex-git,portal,python,screencapture,toolkit,widgets} plasma-browser-integration; do
  v yay -Rns $i
done
