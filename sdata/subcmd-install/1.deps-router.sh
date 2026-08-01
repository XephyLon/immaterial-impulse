# This script is meant to be sourced.
# It's not for directly running.
printf "${STY_CYAN}[$0]: 1. Install dependencies\n${STY_RST}"

#####################################################################################
# Migration: detect a prior illogical-impulse install (renamed to
# immaterial-impulse-* in this project). See sdata/lib/migrate-existing.sh.
source ./sdata/lib/migrate-existing.sh

# The default IMI_PKG_QUERY_CMD ("pacman -Qq") only makes sense on Arch.
# Override per-distro; if the query tool isn't present the eval silently
# fails and has_legacy_packages() just reports false (safe no-op).
case "$OS_GROUP_ID" in
  fedora) IMI_PKG_QUERY_CMD="rpm -qa --qf '%{NAME}\n'" ;;
  gentoo) IMI_PKG_QUERY_CMD="qlist -I -C" ;; # requires app-portage/portage-utils
esac

function migrate_notify_legacy(){
  printf "${STY_YELLOW}"
  printf "===MIGRATION NOTICE===\n"
  printf "A prior illogical-impulse install was detected on this system:\n"
  legacy_packages | sed 's/^/  - /'
  printf "\n"
  printf "The immaterial-impulse-* packages (the renamed successor) will be installed by the step below.\n"
  printf "The old illogical-impulse-* packages listed above will then be removed automatically afterwards, where supported for this distro.\n"
  printf "Your existing ~/.config/quickshell will be backed up (see the backup step under \"3. Copying config files\") before it's overwritten.\n"
  printf "${STY_RST}"
  pause
}

# Package-less prior install (config copied manually, no illogical-impulse-*
# packages): nothing to remove, but flag it so the user knows the config dir is
# recognized and will be migrated at runtime.
function migrate_notify_legacy_config(){
  printf "${STY_YELLOW}"
  printf "===MIGRATION NOTICE===\n"
  printf "A prior illogical-impulse config was detected at \"%s\" (no illogical-impulse-* packages found — a manual/config-only install).\n" "$IMI_LEGACY_CONFIG_DIR"
  printf "It will be migrated to ~/.config/immaterial-impulse automatically on first shell launch.\n"
  printf "Your existing ~/.config/quickshell will be backed up (see the backup step under \"3. Copying config files\") before it's overwritten.\n"
  printf "${STY_RST}"
  pause
}

function migrate_remove_legacy(){
  local pkgs
  pkgs="$(legacy_packages)"
  [[ -z "$pkgs" ]] && return 0
  case "$OS_GROUP_ID" in
    arch)
      # -Rn, NOT -Rns: remove only the old illogical-impulse-* metapackages, not
      # their dependencies. The immaterial-impulse-* successors share those deps
      # (qt6-wayland, cpptrace, kdialog, ...); -s would cascade-remove them as
      # "orphans" and break the new install / the WE build.
      v sudo pacman -Rn --noconfirm $pkgs
      ;;
    fedora)
      v sudo dnf remove -y $pkgs
      ;;
    gentoo)
      printf "${STY_YELLOW}[$0]: Skipping automatic removal of legacy illogical-impulse-* packages on Gentoo (portage category/slot handling isn't uniform enough to do this safely here). Please remove them manually, e.g.:\n"
      printf "  sudo emerge -C ${pkgs}\n${STY_RST}"
      ;;
    *)
      printf "${STY_YELLOW}[$0]: Don't know how to remove legacy illogical-impulse-* packages for OS_GROUP_ID=\"$OS_GROUP_ID\". Please remove them manually: ${pkgs}${STY_RST}\n"
      ;;
  esac
}

if has_legacy_packages; then
  migrate_notify_legacy
elif has_legacy_config; then
  migrate_notify_legacy_config
fi
#####################################################################################

function outdate_detect(){
  # Shallow clone prevent latest_commit_timestamp() from working.
  x git_auto_unshallow 2>&1>/dev/null

  local source_path="$1"
  local target_path="$2"
  local source_timestamp="$(latest_commit_timestamp $source_path 2>/dev/null)"
  local target_timestamp="$(latest_commit_timestamp $target_path 2>/dev/null)"
  local outdate_detect_mode="$(cat ${target_path}/outdate-detect-mode)"

  # outdate-detect-mode possible modes:
  # - WIP: Work in progress (should be taken as outdated)
  # - FORCE_OUTDATED: forcely taken as outdated
  # - FORCE_UPDATED: forcely taken as updated
  # - AUTO: Let the script decide automatically
  #
  # outdate status possible values:
  # - WIP,FORCE_OUTDATED,FORCE_UPDATED: Inherited directly from outdate-detect-mode
  # - EMPTY_SOURCE: source path has empty timestamp, maybe not tracked by git (should be taken as outdated)
  # - EMPTY_TARGET: target path has empty timestamp, maybe not tracked by git (should be taken as outdated)
  # - OUTDATED: target path is older than source path.
  # - UPDATED: target path is not older than source path.

  # Does target path have an outdate-detect-mode file which content is special?
  if [[ "${outdate_detect_mode}" =~ ^(WIP|FORCE_OUTDATED|FORCE_UPDATED)$ ]]; then
    echo "${outdate_detect_mode}"
  # Does source path has an empty timestamp?
  elif [ -z "$source_timestamp" ]; then
    echo "EMPTY_SOURCE"
  # Does target path has an empty timestamp?
  elif [ -z "$target_timestamp" ]; then
    echo "EMPTY_TARGET"
  # If target path is older than source path, it's outdated.
  elif [[ "$target_timestamp" -lt "$source_timestamp" ]]; then
    echo "OUTDATED"
  else
    echo "UPDATED"
  fi
}
#####################################################################################

if [[ "$INSTALL_VIA_NIX" == "true" ]]; then

  TARGET_ID=nix
  printf "${STY_YELLOW}"
  printf "===WARNING===\n"
  printf "./sdata/dist-${TARGET_ID}/install-deps.sh will be used.\n"
  printf "The process is still WIP.\n"
  printf "Proceed only at your own risk.\n"
  printf "\n"
  printf "${STY_RST}"
  pause
  source ./sdata/dist-${TARGET_ID}/install-deps.sh

elif [[ "$OS_GROUP_ID" =~ ^(arch|gentoo|fedora)$ ]]; then

  TARGET_ID=$OS_GROUP_ID
  if ! [[ "${TARGET_ID}" = "arch" ]]; then
    tmp_update_status="$(outdate_detect sdata/dist-arch sdata/dist-${TARGET_ID})"
    if [[ "${tmp_update_status}" =~ ^(OUTDATED|EMPTY_TARGET|EMPTY_SOURCE|FORCE_OUTDATED|WIP)$ ]]; then
      printf "${STY_RED}${STY_BOLD}===URGENT===${STY_RST}\n"
      printf "${STY_RED}"
      printf "Status code: ${tmp_update_status}\n"
      printf "The community provided ./sdata/dist-${TARGET_ID}/ seems to be outdated,\n"
      printf "which means it probably does not reflect all latest changes of ./sdata/dist-arch/ .\n"
      printf "In such case it may work unexpectedly.${STY_RST}\n"
      printf "\n"
      printf "${STY_RED}It's highly recommended to check the following links before continue.${STY_RST}\n"
      printf "${STY_RED}1. Normally just check discussion#2140 to see if there's any valid update notice.${STY_RST}\n"
      printf "   ${STY_UNDERLINE}https://github.com/end-4/dots-hyprland/discussions/2140${STY_RST}\n"
      printf "   ${STY_RED}Note that the timeliness relies on manual maintenance.${STY_RST}\n"
      printf "${STY_RED}2. For details please compare the two lists of commit history:${STY_RST}\n"
      printf "   ${STY_UNDERLINE}https://github.com/end-4/dots-hyprland/commits/main/sdata/dist-arch${STY_RST}\n"
      printf "   ${STY_UNDERLINE}https://github.com/end-4/dots-hyprland/commits/main/sdata/dist-${TARGET_ID}${STY_RST}\n"
      printf "\n"
      printf "${STY_PURPLE}PR on ./sdata/dist-${TARGET_ID}/ to properly reflect the latest changes of ./sdata/dist-arch is welcomed.${STY_RST}\n"
      printf "${STY_PURPLE}${STY_BOLD}Again, do not create any issue,${STY_RST}\n"
      printf "${STY_PURPLE}but you can create a discussion under \"Extra Distros\" category: ${STY_RST}\n"
      printf "${STY_PURPLE}${STY_UNDERLINE}https://github.com/end-4/dots-hyprland/discussions/new?category=extra-distros${STY_RST}\n"
      printf "\n"
      if [[ "${tmp_update_status}" = "OUTDATED" ]]; then
        printf "${STY_RED}NOTE: The conclusion above is determined automatically by comparing latest Git commit time,\n"
        printf "however sometimes the changes on \"dist-arch\" are actually not needed for \"dist-${TARGET_ID}\",\n"
        printf "in such case you should just ignore it and continue.\n"
        printf "${STY_RST}\n"
      fi
      printf "\n"
      if ! [[ "$IGNORE_OUTDATE_CHECK" = "true" ]]; then
        if [ "$ask" = "false" ]; then
          printf "${STY_RED}Urgent problem encountered, aborting...${STY_RST}\n";exit 1
        else
          printf "${STY_RED}Still proceed?${STY_RST}\n"
          read -p "[y/N]: " p
          case "$p" in
            [yY])true;;
            *)echo "Aborting...";exit 1;;
          esac
        fi
      fi
    fi
  fi
  printf "./sdata/dist-${TARGET_ID}/install-deps.sh will be used.\n"
  source ./sdata/dist-${TARGET_ID}/install-deps.sh

  # Migration: the immaterial-impulse-* packages were just installed above.
  # Now remove the old illogical-impulse-* ones, if any were detected earlier.
  if has_legacy_packages; then
    migrate_remove_legacy
  fi
fi
