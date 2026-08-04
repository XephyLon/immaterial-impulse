# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################
# The loop above deploys dots/.config/* with rsync --delete, and the SDDM login
# theme keeps its integration *inside* one of those files: its installer appends
# a `[templates.iisddmtheme]` block to ~/.config/matugen/config.toml so the
# greeter's colors are regenerated on every wallpaper change. We ship our own
# config.toml without that block, so each update deleted it and the login screen
# quietly froze at whatever it looked like when the theme was installed.
#
# The block is one unit and has to be restored as one. An earlier version of
# this function put back only the `post_hook`, under [config] rather than under
# the template, which is worse than not restoring anything: the hook fires (now
# after *every* matugen run, not just this template's) while the input_path /
# output_path pair that actually regenerates Colors.qml is gone, so nothing is
# produced for it to publish. The greeter's palette stayed frozen and the
# function reported success. See issue #101.
#
# Idempotent, and it re-derives the mode rather than assuming:
# generate_settings.py is only present for the ii+matugen mode, which
# additionally syncs the shell's own settings.
restore_sddm_matugen_hook(){
  local matugen_conf="${XDG_CONFIG_HOME}/matugen/config.toml"

  # The theme installs as imi-sddm-theme; installs from before that rename are
  # still under ii-sddm-theme until the theme's own installer migrates them, so
  # restore for whichever is actually there. Preferring the new name matters:
  # during a migrating update both directories exist for a moment, and pointing
  # at the one about to be deleted would break it again.
  #
  # SddmColors.qml is the marker rather than sddm-theme-apply.sh: the apply
  # script no longer lives here. It is installed root-owned under
  # /usr/local/lib because a NOPASSWD sudoers rule names it and sudo matches by
  # path. SddmColors.qml is the template's input_path, so it is exactly the file
  # whose absence would make the block pointless.
  local theme_name theme_dir=""
  for theme_name in imi-sddm-theme ii-sddm-theme; do
    if [[ -f "${XDG_CONFIG_HOME}/${theme_name}/SddmColors.qml" ]]; then
      theme_dir="${XDG_CONFIG_HOME}/${theme_name}"
      break
    fi
  done

  [[ -n "$theme_dir" && -f "$matugen_conf" ]] || return 0

  # Guard on the block, not on `^post_hook`. The old guard could not tell "the
  # theme's block survived" from "only the bare hook I restored last time is
  # here", so it never noticed - or corrected - the half-restored state it had
  # created itself.
  grep -q '^\[templates\.iisddmtheme\]' "$matugen_conf" && return 0

  # The apply script's path is what the sudoers rule names, and sudo matches by
  # path: a hook naming any other location prompts for a password from a
  # backgrounded hook and never completes. Prefer the root-owned location, fall
  # back to the in-config one for installs made before that move.
  local apply_script=""
  if [[ -f "/usr/local/lib/${theme_name}/sddm-theme-apply.sh" ]]; then
    apply_script="/usr/local/lib/${theme_name}/sddm-theme-apply.sh"
  elif [[ -f "${theme_dir}/sddm-theme-apply.sh" ]]; then
    apply_script="~/.config/${theme_name}/sddm-theme-apply.sh"
  else
    return 0
  fi

  local hook
  if [[ -f "${theme_dir}/generate_settings.py" ]]; then
    hook="python3 ~/.config/${theme_name}/generate_settings.py && sudo ${apply_script} &"
  else
    hook="sudo ${apply_script} &"
  fi

  # Drop a stray global post_hook left by the earlier half-restore. Left in
  # place it would keep running the apply script (and a sudo call) after every
  # matugen invocation, on top of the template's own hook. Only ours is touched:
  # the line has to name the theme's apply script.
  if grep -qE "^post_hook[[:space:]]*=.*sddm-theme-apply\.sh" "$matugen_conf"; then
    sed -i -E "/^post_hook[[:space:]]*=.*sddm-theme-apply\.sh/d" "$matugen_conf"
    echo -e "${STY_BLUE}[$0]: removed a stray global matugen post_hook for the SDDM theme (it fired on every run and regenerated nothing).${STY_RST}"
  fi

  # Same shape the theme's own setup.sh writes, so a later re-run of the theme
  # installer replaces this block rather than appending a second one.
  cat >> "$matugen_conf" <<EOF

[templates.iisddmtheme]
input_path = '~/.config/${theme_name}/SddmColors.qml'
output_path = '~/.config/${theme_name}/Colors.qml'
post_hook = '${hook}'
EOF
  echo -e "${STY_BLUE}[$0]: restored the SDDM theme's [templates.iisddmtheme] matugen block (our config.toml sync removes it).${STY_RST}"
}

# MISC (For dots/.config/* but not quickshell, not fish, not Hyprland, not fontconfig)
case "${SKIP_MISCCONF}" in
  true) true;;
  *)
    for i in $(find dots/.config/ -mindepth 1 -maxdepth 1 ! -name 'quickshell' ! -name 'fish' ! -name 'hypr' ! -name 'fontconfig' -exec basename {} \;); do
#      i="dots/.config/$i"
      echo "[$0]: Found target: dots/.config/$i"
      if [ -d "dots/.config/$i" ];then install_dir__sync "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      elif [ -f "dots/.config/$i" ];then install_file "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      fi
    done
    install_dir "dots/.local/share/konsole" "${XDG_DATA_HOME}"/konsole
    restore_sddm_matugen_hook
    ;;
esac

case "${SKIP_QUICKSHELL}" in
  true) true;;
  *)
     # Should overwriting the whole directory not only ~/.config/quickshell/imi/ cuz https://github.com/end-4/dots-hyprland/issues/2294#issuecomment-3448671064
    # Deploy runtime files only: dev/test/doc files stay in the repo but are
    # excluded from the deployed config dir (see sdata/lib/deploy-exclude.txt).
    install_dir__sync_exclude_from dots/.config/quickshell "$XDG_CONFIG_HOME"/quickshell "${REPO_ROOT}/sdata/lib/deploy-exclude.txt"
    ;;
esac

case "${SKIP_FISH}" in
  true) true;;
  *)
    install_dir__sync_exclude dots/.config/fish "$XDG_CONFIG_HOME"/fish "conf.d"
    ;;
esac

case "${SKIP_FONTCONFIG}" in
  true) true;;
  *)
    case "$FONTSET_DIR_NAME" in
      "") install_dir__sync dots/.config/fontconfig "$XDG_CONFIG_HOME"/fontconfig ;;
      *) install_dir__sync dots-extra/fontsets/$FONTSET_DIR_NAME "$XDG_CONFIG_HOME"/fontconfig ;;
    esac;;
esac

# For Hyprland
case "${SKIP_HYPRLAND}" in
  true) true;;
  *)
    # hyprland/shellOverrides/ holds the user's Settings choices, written+managed
    # by the shell at runtime. Exclude it from the --delete sync so an update
    # never clobbers it, then seed defaults per-file with --ignore-existing:
    # this adds newly-shipped managed files (e.g. animations.lua) that existing
    # installs lack, while preserving any file the user's shell already wrote.
    install_dir__sync_exclude dots/.config/hypr/hyprland "$XDG_CONFIG_HOME"/hypr/hyprland shellOverrides
    v rsync_dir__ignore_existing dots/.config/hypr/hyprland/shellOverrides "$XDG_CONFIG_HOME"/hypr/hyprland/shellOverrides
    if [ -f "${XDG_CONFIG_HOME}/hypr/hyprland.conf" ]; then
      mv "${XDG_CONFIG_HOME}/hypr/hyprland.conf" "${XDG_CONFIG_HOME}/hypr/hyprland.conf.old" # disable old config
      echo 'hyprland.conf has been renamed to hyprland.conf.old. This is to allow the new lua config to load.'
    fi
    for i in hyprlock.conf ; do
      install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
    done
    for i in hyprland.lua ; do
      case "${SKIP_HYPRLAND_ENTRY}" in
        true) true;;
        *) install_file "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i" ;;
      esac
    done
    for i in hypridle.conf ; do
      if [[ "${INSTALL_VIA_NIX}" == true ]]; then
        install_file__auto_backup "dots-extra/via-nix/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      else
        install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      fi
    done
    if [ "$OS_GROUP_ID" = "fedora" ];then
      v bash -c "printf \"# For fedora to setup polkit\nexec-once = /usr/libexec/kf6/polkit-kde-authentication-agent-1\n\" >> ${XDG_CONFIG_HOME}/hypr/hyprland/execs.conf"
    fi

    install_dir__ignore_existing "dots/.config/hypr/custom" "${XDG_CONFIG_HOME}/hypr/custom"
    ;;
esac

install_file "dots/.local/share/icons/immaterial-impulse.png" "${XDG_DATA_HOME}"/icons/immaterial-impulse.png
