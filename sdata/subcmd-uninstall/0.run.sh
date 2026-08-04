# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

printf "${STY_RED}"
printf "===CAUTION===\n"
printf "This script will try to revert changes made by \"./setup install\".\n"
printf "However:\n"
printf "1. It is far from enough to precisely revert all changes.\n"
printf "2. It has not been fully tested, use at your own risk.\n"
printf "${STY_RST}"
pause
##############################################################################################################################

# Undo the optional Immaterial Impulse extras (install steps 5 and 4) first,
# in reverse install order, before reverting the core config/deps below.

# Step 5: the imi-sddm-theme SDDM login theme (if present). Hand off to the
# theme's own uninstaller, pinned to the same commit our installer used - it
# removes both the current and the pre-rename name.
#
# Only when it is ours to remove. This used to fire on either directory
# existing, and "ii-sddm-theme" is upstream 3d3f/ii-sddm-theme's install name -
# so a user who installed upstream's theme themselves, years before ImI, then
# installed ImI *without* the SDDM extra (INSTALL_SDDM=0, the default), had
# their working login screen handed to our uninstaller by an ImI uninstall. It
# removes the theme directory, the drop-in carrying their Current=, their
# config dir, fonts, matugen block and sudoers rule - none of which we created.
# Losing the directory while Current= still names it is the login-blocking case.
# Step 4 below already models the right shape: prove ownership, don't infer it.
# See issue #100.
#
# Two forms of evidence, in order of strength:
#   - the marker install step 5 writes on a successful hand-off. Definitive,
#     and the only thing that can authorise removing the legacy name.
#   - /usr/share/sddm/themes/imi-sddm-theme. Installs predating the marker have
#     nothing else, and this name is ours: only this fork installs under it.
# A bare legacy directory is never enough, and is reported instead of acted on.
_sddm_marker="${XDG_STATE_HOME:-$HOME/.local/state}/immaterial-impulse/sddm-theme-installed"
_sddm_ours=false
if [[ -d /usr/share/sddm/themes/imi-sddm-theme ]]; then
  _sddm_ours=true
elif [[ -f "$_sddm_marker" && -d /usr/share/sddm/themes/ii-sddm-theme ]]; then
  # We installed it before the theme renamed itself, and its migration has not
  # run since. Still ours.
  _sddm_ours=true
elif [[ -d /usr/share/sddm/themes/ii-sddm-theme ]]; then
  printf "${STY_YELLOW}Found /usr/share/sddm/themes/ii-sddm-theme, the pre-fork name, with no record that we installed it.${STY_RST}\n"
  printf "${STY_YELLOW}Leaving it alone - it is most likely upstream 3d3f/ii-sddm-theme, installed by you. To remove it, use its own uninstaller; deleting the directory while a Current= still names it will leave you with no graphical login.${STY_RST}\n"
fi

if [[ "$_sddm_ours" == true ]]; then
  printf "${STY_CYAN}Undo install step 5 (imi-sddm-theme SDDM login theme)...\n${STY_RST}"
  if command -v curl >/dev/null; then
    # Must match SDDM_REF in sdata/subcmd-install/5.sddm-theme.sh -
    # tests/test_sddm_theme_source.py pins that they agree.
    _sddm_ref="${SDDM_REF:-ac2e7d47f0998442d7baebee7165b4cc28d217d4}"
    _sddm_un="$(mktemp --suffix=-ii-sddm-uninstall.sh)"
    if curl -fsSL "https://raw.githubusercontent.com/XephyLon/imi-sddm-theme/${_sddm_ref}/uninstall.sh" -o "$_sddm_un"; then
      # The theme's uninstaller exits non-zero when it removes nothing (a
      # decline, or no terminal to ask on), so the marker only goes away when
      # the thing it records is actually gone.
      if bash "$_sddm_un"; then
        rm -f "$_sddm_marker"
      else
        printf "${STY_YELLOW}imi-sddm-theme uninstaller exited non-zero; remove it manually if needed.${STY_RST}\n"
      fi
    else
      printf "${STY_YELLOW}Could not fetch the imi-sddm-theme uninstaller. Remove manually: /usr/share/sddm/themes/imi-sddm-theme, /etc/sddm.conf.d/zz-imi-sddm-theme.conf, ~/.config/imi-sddm-theme, /usr/local/lib/imi-sddm-theme, its /etc/sudoers.d rule and its fonts.${STY_RST}\n"
    fi
    rm -f "$_sddm_un"
  else
    printf "${STY_YELLOW}curl not found; remove the SDDM theme manually.${STY_RST}\n"
  fi
fi

# Step 4: the WE-capable custom quickshell wrapper on PATH. Only remove it if it
# is actually ours (carries the immaterial-impulse marker), never a foreign
# /usr/local/bin/quickshell.
if [[ -f /usr/local/bin/quickshell ]] && grep -q "immaterial-impulse" /usr/local/bin/quickshell 2>/dev/null; then
  printf "${STY_CYAN}Undo install step 4 (Wallpaper Engine custom quickshell wrapper)...\n${STY_RST}"
  v sudo rm -f /usr/local/bin/quickshell
  [[ -L /usr/local/bin/qs ]] && v sudo rm -f /usr/local/bin/qs
fi
_we_build="${HOME}/.cache/immaterial-impulse/qs-wallpaperengine-build"
if [[ -d "$_we_build" ]]; then
  while true; do
    printf "Also remove the qs-wallpaperengine build cache at \"%s\"? [y/n]\n" "$_we_build"
    read -n1 -p "> " _ans < /dev/tty; echo
    case "$_ans" in
      y|Y) x rm -rf -- "$_we_build"; break ;;
      n|N) break ;;
      *) ;;
    esac
  done
fi

# Optional: the runtime data/state dir created by the config-dir migration (M1).
# This is your settings/state, so it is prompted, not force-removed.
_imi_data="${XDG_CONFIG_HOME:-$HOME/.config}/immaterial-impulse"
if [[ -d "$_imi_data" ]]; then
  while true; do
    printf "Also remove your Immaterial Impulse data dir \"%s\" (settings/state)? [y/n]\n" "$_imi_data"
    read -n1 -p "> " _ans < /dev/tty; echo
    case "$_ans" in
      y|Y) x rm -rf -- "$_imi_data"; break ;;
      n|N) break ;;
      *) ;;
    esac
  done
fi
printf "${STY_YELLOW}Note: keyring secrets under the 'immaterial-impulse' application are left intact; remove them via your keyring manager if desired.${STY_RST}\n"

##############################################################################################################################

# Undo Step 3
printf "${STY_CYAN}Undo install step 3...\n${STY_RST}"

function view_listfile(){
  local listfile="$1"
  if command -v less >/dev/null; then
    less "$listfile"
  else
    cat "$listfile"
  fi
}

function edit_listfile(){
  local listfile="$1"
  for ed in "$EDITOR" nano vim nvim vi; do
    if command -v $ed >/dev/null; then
      x $ed "$listfile"
      return
    fi
  done
  printf "Failed to find an available editor, please manually edit \"$listfile\".\n"
}

function delete_targets(){
  local listfile="$1"
  local targets=()
  readarray -t targets < "$listfile"
  for path in "${targets[@]}"; do
    if [[ ! -e "$path" ]]; then
      printf "${STY_YELLOW}Target \"$path\" inexists, skipping...${STY_RST}\n"
      continue
    elif [[ "$path" == "$HOME"* ]]; then
      if [[ -d "$path" ]]; then
		x rm -r -- "$path"
	else
		x rm -- "$path"
	fi

    else
      while true; do
        printf "WARNING: Target \"$path\" is not under \$HOME. Still delete it?\ny=Yes, delete it;\nn=No, skip this one\n"
        read -n1 -p "> " ans < /dev/tty
        echo
        case "$ans" in
          y|Y)
	    if [[ -d "$path" ]]; then
		    x rm -r -- "$path"
	    else
		    x rm -- "$path"
	    fi
            break 1
            ;;
          n|N)
            break 1
            ;;
          *)
            ;;
        esac
      done
    fi
  done
}

function deletion_prompt(){
  local listfile="$1"
  while true; do
    printf "Every target which path as a line inside the list \"$listfile\" will be deleted permanently.\n"
    printf "Please choose:\nv=View the list\ne=Edit the list\nq=Quit\ny=Perform deletion now\n"
    read -n1 -p "> " choice < /dev/tty
    echo
    case "$choice" in
      q|Q)
        printf "Quiting...\n"
        break
        ;;
      y|Y)
        delete_targets "$listfile"
        break
        ;;
      v|V)
        view_listfile "$listfile"
        ;;
      e|E)
        edit_listfile "$listfile"
        ;;
      *)
        ;;
    esac
  done
}

deletion_prompt "${INSTALLED_LISTFILE}"

empty_dir_listfile=$(mktemp)
scan_paths=(${XDG_CONFIG_HOME} "${XDG_DATA_HOME}"/konsole)
for dir in "${scan_paths[@]}"; do
  find "$dir" -type d -empty -print >> $empty_dir_listfile
done
x dedup_and_sort_listfile "$empty_dir_listfile" "$empty_dir_listfile"
deletion_prompt "$empty_dir_listfile"

##############################################################################################################################

printf "${STY_CYAN}Undo install step 2...\n${STY_RST}"
user=$(whoami)
warn_undo_break_system(){
  printf "${STY_YELLOW}WARNING: The command below could break your system functionality. If you are unsure about it, just skip the command.${STY_RST}\n"
}
warn_undo_break_system
v sudo gpasswd -d "$user" video
warn_undo_break_system
v sudo gpasswd -d "$user" i2c
warn_undo_break_system
v sudo gpasswd -d "$user" input
warn_undo_break_system
v sudo rm /etc/modules-load.d/i2c-dev.conf

##############################################################################################################################

printf "${STY_CYAN}Undo install step 1...\n${STY_RST}"

if test -f sdata/dist-$OS_GROUP_ID/uninstall-deps.sh; then
  source sdata/dist-$OS_GROUP_ID/uninstall-deps.sh
else
  printf "${STY_YELLOW}Automatic depedencies uninstallation is not yet avaible for your distro. Skipping...${STY_RST}\n"
fi

printf "${STY_CYAN}Uninstall script finished.\n${STY_RST}"
printf "${STY_CYAN}Hint: If you had agreed to backup when you ran \"./setup install\", you should be able to find it under \"$BACKUP_DIR\".\n${STY_RST}"
