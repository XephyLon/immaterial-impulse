# Shared by `setup backup` and `setup restore`. Meant to be sourced.
# shellcheck shell=bash

# What a backup carries, relative to XDG_CONFIG_HOME. These are the files
# the installer treats as the user's own: it never overwrites them on an
# update (shellOverrides, custom/, hyprlock/hypridle get a `.new` beside
# them) and it never created them (the shell's config, plugins, presets).
# Install state (installed_true, installed_listfile) stays out: a restore
# onto a fresh machine must not pretend the install already happened.
IMI_BACKUP_PATHS=(
  "immaterial-impulse"
  "hypr/custom"
  "hypr/hyprland/shellOverrides"
  "hypr/hyprlock.conf"
  "hypr/hypridle.conf"
)
IMI_BACKUP_EXCLUDES=(
  "immaterial-impulse/installed_true"
  "immaterial-impulse/installed_listfile"
)
IMI_BACKUP_MANIFEST="imi-backup.json"

# The shell rewrites config.json as it runs and re-reads it on change, so a
# restore under a live shell is a race the user loses. The pgrep is
# overridable so a test can fake either answer.
imi_shell_is_running(){
  local pgrep_cmd="${IMI_PGREP:-pgrep}"
  "$pgrep_cmd" -u "$(id -u)" -x quickshell >/dev/null 2>&1 \
    || "$pgrep_cmd" -u "$(id -u)" -x qs >/dev/null 2>&1
}

# Writes the archive at $1. Returns 1 when nothing to back up exists.
imi_backup_create(){
  local archive="$1"
  local present=() p
  for p in "${IMI_BACKUP_PATHS[@]}"; do
    [[ -e "${XDG_CONFIG_HOME}/${p}" ]] && present+=("$p")
  done
  if (( ${#present[@]} == 0 )); then
    log_error "Nothing to back up under ${XDG_CONFIG_HOME}: none of ${IMI_BACKUP_PATHS[*]} exist."
    return 1
  fi
  local manifest_dir
  manifest_dir="$(mktemp -d)"
  register_temp_file "$manifest_dir"
  local version="unknown"
  [[ -r "${REPO_ROOT}/VERSION" ]] && version="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
  printf '{"format":1,"created":"%s","host":"%s","imi_version":"%s","config_home":"%s","paths":[%s]}\n' \
    "$(date -Iseconds)" "$(hostname 2>/dev/null || echo unknown)" "$version" "$XDG_CONFIG_HOME" \
    "$(printf '"%s",' "${present[@]}" | sed 's/,$//')" > "${manifest_dir}/${IMI_BACKUP_MANIFEST}"
  local excludes=()
  for p in "${IMI_BACKUP_EXCLUDES[@]}"; do excludes+=(--exclude="./${p}"); done
  mkdir -p "$(dirname "$archive")"
  # Two -C's: the manifest from its temp dir, the payload from the config
  # home, both stored with relative paths so restore is `tar -C config_home`.
  tar -czf "$archive" \
    -C "$manifest_dir" "./${IMI_BACKUP_MANIFEST}" \
    "${excludes[@]}" \
    -C "$XDG_CONFIG_HOME" "${present[@]/#/./}"
}

# Lists the payload paths (no manifest) an archive holds, one per line,
# top-level entries only.
imi_backup_payload(){
  tar -tzf "$1" | sed -e 's#^\./##' -e 's#/.*##' -e '/^$/d' \
    | grep -v -x -F "$IMI_BACKUP_MANIFEST" | sort -u
}

# Restores $1 into XDG_CONFIG_HOME. Every target that already exists is
# moved aside to <path>.pre-restore-<stamp> first, never deleted.
imi_backup_restore(){
  local archive="$1"
  if ! tar -tzf "$archive" 2>/dev/null | grep -q -x -F "./${IMI_BACKUP_MANIFEST}"; then
    log_error "$archive is not an Immaterial Impulse backup (no ${IMI_BACKUP_MANIFEST} inside)."
    return 1
  fi
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local p target moved=()
  while IFS= read -r p; do
    for target in "${IMI_BACKUP_PATHS[@]}"; do
      [[ "$target" == "$p"* ]] || continue
      local full="${XDG_CONFIG_HOME}/${target}"
      if [[ -e "$full" ]]; then
        mv "$full" "${full}.pre-restore-${stamp}"
        moved+=("${full}.pre-restore-${stamp}")
      fi
    done
  done < <(imi_backup_payload "$archive")
  mkdir -p "$XDG_CONFIG_HOME"
  tar -xzf "$archive" -C "$XDG_CONFIG_HOME" --exclude="./${IMI_BACKUP_MANIFEST}"
  if (( ${#moved[@]} > 0 )); then
    log_info "Previous files kept beside their replacements:"
    printf '  %s\n' "${moved[@]}"
  fi
}
